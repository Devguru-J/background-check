import Foundation

public struct ScanSettings: Equatable, Codable, Sendable {
    public var projectRoots: [String]
    public var staleHours: Double
    public var ignorePatterns: [String]

    /// npm으로 설치한 Claude Code/Codex가 dev 서버로 잡히지 않게 막는다.
    public static let defaultIgnorePatterns = ["@anthropic-ai/claude-code", "claude/versions/", "codex"]

    public init(projectRoots: [String], staleHours: Double = 6,
                ignorePatterns: [String] = ScanSettings.defaultIgnorePatterns) {
        self.projectRoots = projectRoots
        self.staleHours = staleHours
        self.ignorePatterns = ignorePatterns
    }

    public static func defaults(home: String) -> ScanSettings {
        ScanSettings(projectRoots: [home + "/Devguru"])
    }

    /// ~ 확장, 끝 슬래시 제거, 심볼릭 링크 해석, 빈 값·중복 제거, 잘못된 기준 시간 복구
    public func normalized(home: String) -> ScanSettings {
        var roots: [String] = []
        for raw in projectRoots {
            var path = raw.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            if path.hasPrefix("~") { path = home + path.dropFirst() }
            // URL.resolvingSymlinksInPath는 /private를 떼어내므로 libproc cwd(/private/var/...)와 맞추려면 realpath를 쓴다
            if let resolved = realpath(path, nil) {
                path = String(cString: resolved)
                free(resolved)
            }
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            if !roots.contains(path) { roots.append(path) }
        }
        let patterns = ignorePatterns
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return ScanSettings(projectRoots: roots,
                            staleHours: staleHours > 0 ? staleHours : 6,
                            ignorePatterns: patterns)
    }
}
