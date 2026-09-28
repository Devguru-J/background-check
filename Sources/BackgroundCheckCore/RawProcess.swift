import Foundation

/// 한 번의 스캔에서 수집한 프로세스 하나.
public struct RawProcess: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    public var elapsed: TimeInterval
    public var command: String
    /// `proc_pidpath` 결과. 읽지 못하면 nil
    public var executablePath: String?
    public var cwd: String?
    public var ports: [Int]

    public init(pid: Int32, ppid: Int32, elapsed: TimeInterval = 0, command: String,
                executablePath: String? = nil, cwd: String? = nil, ports: [Int] = []) {
        self.pid = pid
        self.ppid = ppid
        self.elapsed = elapsed
        self.command = command
        self.executablePath = executablePath
        self.cwd = cwd
        self.ports = ports
    }
}
