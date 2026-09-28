import Darwin
import Foundation

public protocol Signaler: Sendable {
    /// 성공하면 0, 실패하면 errno
    func send(_ signal: Int32, to pid: Int32) -> Int32
    func isAlive(_ pid: Int32) -> Bool
}

public struct KillResult: Equatable, Sendable {
    /// pid → errno (ESRCH 제외)
    public var failures: [Int32: Int32]
    /// SIGKILL 후에도 살아 있는 pid
    public var survivors: [Int32]
    public var succeeded: Bool { failures.isEmpty && survivors.isEmpty }
}

public struct ProcessKiller: Sendable {
    public let signaler: any Signaler
    public let grace: TimeInterval
    public let pollInterval: TimeInterval
    public let sleep: @Sendable (TimeInterval) -> Void

    public init(signaler: any Signaler, grace: TimeInterval = 3, pollInterval: TimeInterval = 0.25,
                sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.signaler = signaler
        self.grace = grace
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    /// 자식부터 SIGTERM, grace 동안 기다린 뒤 남은 프로세스에 SIGKILL. 호출한 스레드를 막으므로 메인 스레드에서 부르지 말 것.
    public func terminate(pids memberPIDs: [Int32]) -> KillResult {
        var failures: [Int32: Int32] = [:]
        let order = Array(memberPIDs.reversed())
        for pid in order {
            let err = signaler.send(SIGTERM, to: pid)
            if err != 0 && err != ESRCH { failures[pid] = err }
        }

        var alive = order.filter { failures[$0] == nil && signaler.isAlive($0) }
        var waited: TimeInterval = 0
        while !alive.isEmpty && waited < grace {
            sleep(pollInterval)
            waited += pollInterval
            alive = alive.filter { signaler.isAlive($0) }
        }
        guard !alive.isEmpty else { return KillResult(failures: failures, survivors: []) }

        for pid in alive {
            let err = signaler.send(SIGKILL, to: pid)
            if err != 0 && err != ESRCH { failures[pid] = err }
        }
        sleep(pollInterval)
        let survivors = alive.filter { failures[$0] == nil && signaler.isAlive($0) }
        return KillResult(failures: failures, survivors: survivors)
    }
}
