import Foundation

public struct DevSession: Identifiable, Equatable, Sendable {
    public var id: Int32 { rootPID }
    public var rootPID: Int32
    /// 루트가 먼저 오는 BFS 순서
    public var memberPIDs: [Int32]
    /// 루트 프로세스의 명령어
    public var command: String
    /// "항상 무시"에 넣을 문자열. 경로 인자가 있는 첫 dev 바이너리 멤버의 명령어, 없으면 루트 명령어
    public var ignoreKey: String
    public var toolName: String
    public var projectName: String
    public var projectPath: String?
    public var ports: [Int]
    public var uptime: TimeInterval
    public var isStale: Bool

    public init(rootPID: Int32, memberPIDs: [Int32], command: String, ignoreKey: String, toolName: String,
                projectName: String, projectPath: String?, ports: [Int], uptime: TimeInterval, isStale: Bool) {
        self.rootPID = rootPID
        self.memberPIDs = memberPIDs
        self.command = command
        self.ignoreKey = ignoreKey
        self.toolName = toolName
        self.projectName = projectName
        self.projectPath = projectPath
        self.ports = ports
        self.uptime = uptime
        self.isStale = isStale
    }
}

public enum SessionMatcher {
    /// 목록을 띄운 뒤 PID가 재사용됐을 수 있으므로, 최신 스캔에서 같은 루트 PID·같은 명령어인 세션만 돌려준다.
    public static func fresh(_ session: DevSession, in current: [DevSession]) -> DevSession? {
        current.first { $0.rootPID == session.rootPID && $0.command == session.command }
    }
}
