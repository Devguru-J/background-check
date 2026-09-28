import Foundation

public struct ProjectInfo: Equatable, Sendable {
    public var name: String
    public var path: String?

    public init(name: String, path: String?) {
        self.name = name
        self.path = path
    }
}

public struct ProjectNameResolver: Sendable {
    public static let markerFiles = ["package.json", "pyproject.toml", ".git"]

    public let roots: [String]
    public let home: String
    public let fileExists: @Sendable (String) -> Bool

    public init(roots: [String], home: String,
                fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.roots = roots
        self.home = home
        self.fileExists = fileExists
    }

    /// cwds: 세션 루트가 먼저 오는 멤버 cwd 목록
    public func resolve(cwds: [String]) -> ProjectInfo {
        let usable = cwds.filter { $0 != "/" }
        guard let cwd = usable.first(where: { root(containing: $0) != nil }) ?? usable.first else {
            return ProjectInfo(name: "(unknown)", path: nil)
        }
        let stop = root(containing: cwd) ?? home
        var dir = cwd
        while true {
            if Self.markerFiles.contains(where: { fileExists(dir + "/" + $0) }) {
                return ProjectInfo(name: (dir as NSString).lastPathComponent, path: dir)
            }
            guard dir != stop, dir != "/", dir.hasPrefix(stop + "/") else { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return ProjectInfo(name: (cwd as NSString).lastPathComponent, path: cwd)
    }

    private func root(containing path: String) -> String? {
        roots.first { path == $0 || path.hasPrefix($0 + "/") }
    }
}
