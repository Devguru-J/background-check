import Foundation

/// 프로세스가 dev 서버 후보인지, 제외 대상인지, 세션 묶기의 경계인지 판정한다.
public struct DevProcessClassifier: Sendable {
    public static let runtimes: Set<String> = [
        "node", "bun", "deno", "python", "python3", "Python", "ruby", "php", "java", "go",
        "air", "uvicorn", "gunicorn", "hugo", "caddy",
    ]
    public static let packageManagers: Set<String> = ["npm", "npx", "pnpm", "yarn", "bunx"]
    public static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]
    static let agentNames: Set<String> = ["claude", "codex"]
    static let agentMarkers = [
        "/claude/versions/", "@anthropic-ai/claude-code", "@openai/codex", "/Claude.app/Contents/", "/ChatGPT.app/Contents/",
    ]

    public let settings: ScanSettings
    public let home: String

    public init(settings: ScanSettings, home: String) {
        self.settings = settings
        self.home = home
    }

    public static func basename(of p: RawProcess) -> String {
        (executable(of: p) as NSString).lastPathComponent
    }

    public static func isDevBinary(_ name: String) -> Bool {
        runtimes.contains(name) || packageManagers.contains(name) || name.hasPrefix("python3.")
    }

    public func isCandidate(_ p: RawProcess) -> Bool {
        guard Self.isDevBinary(Self.basename(of: p)), !isExcluded(p) else { return false }
        return !p.ports.isEmpty || projectRoot(containing: p.cwd) != nil
    }

    public func isExcluded(_ p: RawProcess) -> Bool {
        if isAgent(p) { return true }
        let exe = Self.executable(of: p)
        if exe.hasPrefix("/System/") || exe.hasPrefix("/usr/libexec/") { return true }
        // 앱이 자체 번들한 런타임 (예: Raycast의 ~/Library/Application Support/.../node)
        if exe.hasPrefix(home + "/Library/") { return true }
        // 앱 번들 안의 프로세스는 helper로 본다. 번들 런타임(JetBrains java, 앱 내장 node)도 포함하되 Xcode·Python 프레임워크는 허용
        if exe.contains(".app/Contents/") && !Self.isAllowedBundledRuntime(exe) { return true }
        let args = Self.arguments(of: p)
        let excludedArgMarkers = [
            ".app/Contents/", home + "/.npm/_npx/", home + "/Library/", home + "/.vscode/", home + "/.cursor/",
        ]
        if excludedArgMarkers.contains(where: { args.contains($0) }) { return true }
        return isIgnored(command: p.command)
    }

    /// 세션 루트를 찾아 부모를 따라 올라갈 때 멈추는 지점
    public func isBoundary(_ p: RawProcess) -> Bool {
        p.pid <= 1 || !Self.isDevBinary(Self.basename(of: p)) || isExcluded(p)
    }

    /// npx 캐시(~/.npm/_npx)에서 실행 중인지. npx/`npm exec`로 받아 띄운 MCP 서버 등.
    public func runsFromNpxCache(_ p: RawProcess) -> Bool {
        let marker = home + "/.npm/_npx/"
        return Self.executable(of: p).contains(marker) || p.command.contains(marker)
    }

    /// 코딩 에이전트 자체. 무시 목록(사용자가 지울 수 있음)과 무관하게 항상 제외·경계로 취급한다.
    public func isAgent(_ p: RawProcess) -> Bool {
        let exe = Self.executable(of: p)
        if Self.agentMarkers.contains(where: { exe.contains($0) || p.command.contains($0) }) { return true }
        // "claude" (프로세스 제목), "node /opt/homebrew/bin/claude" (npm 설치의 bin 링크)
        let leading = p.command.split(separator: " ").prefix(2).map { (String($0) as NSString).lastPathComponent }
        return leading.contains { Self.agentNames.contains($0) }
    }

    public func isIgnored(command: String) -> Bool {
        settings.ignorePatterns.contains { !$0.isEmpty && command.contains($0) }
    }

    public func projectRoot(containing path: String?) -> String? {
        guard let path else { return nil }
        return settings.projectRoots.first { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func isAllowedBundledRuntime(_ exe: String) -> Bool {
        exe.hasPrefix("/Applications/Xcode.app/") || exe.contains("/Python.framework/") || exe.contains("/Python3.framework/")
    }

    static func executable(of p: RawProcess) -> String {
        p.executablePath ?? p.command.split(separator: " ").first.map(String.init) ?? ""
    }

    /// 명령어에서 실행 파일 부분을 뺀 인자 문자열
    static func arguments(of p: RawProcess) -> Substring {
        if let exe = p.executablePath, p.command.hasPrefix(exe) { return p.command.dropFirst(exe.count) }
        guard let space = p.command.firstIndex(of: " ") else { return "" }
        return p.command[space...]
    }
}
