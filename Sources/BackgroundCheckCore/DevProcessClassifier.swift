import Foundation

/// 프로세스가 dev 서버 후보인지, 제외 대상인지, 세션 묶기의 경계인지 판정한다.
public struct DevProcessClassifier: Sendable {
    public static let runtimes: Set<String> = [
        "node", "bun", "deno", "python", "python3", "Python", "ruby", "php", "java", "go",
        "air", "uvicorn", "gunicorn", "hugo", "caddy",
    ]
    public static let packageManagers: Set<String> = ["npm", "npx", "pnpm", "yarn", "bunx"]
    public static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]

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
        let exe = Self.executable(of: p)
        if exe.hasPrefix("/System/") || exe.hasPrefix("/usr/libexec/") { return true }
        if !Self.isDevBinary(Self.basename(of: p)) && exe.contains(".app/Contents/") { return true }
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

    public func isIgnored(command: String) -> Bool {
        settings.ignorePatterns.contains { !$0.isEmpty && command.contains($0) }
    }

    public func projectRoot(containing path: String?) -> String? {
        guard let path else { return nil }
        return settings.projectRoots.first { path == $0 || path.hasPrefix($0 + "/") }
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
