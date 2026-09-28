import Darwin
import Foundation
import Testing
@testable import BackgroundCheckCore

final class FakeSignaler: Signaler, @unchecked Sendable {
    private let lock = NSLock()
    private var alive: Set<Int32>
    private let ignoresTerm: Set<Int32>
    private let errors: [Int32: Int32]
    private(set) var sent: [(signal: Int32, pid: Int32)] = []

    init(alive: Set<Int32>, ignoresTerm: Set<Int32> = [], errors: [Int32: Int32] = [:]) {
        self.alive = alive
        self.ignoresTerm = ignoresTerm
        self.errors = errors
    }

    func send(_ signal: Int32, to pid: Int32) -> Int32 {
        lock.lock(); defer { lock.unlock() }
        sent.append((signal, pid))
        if let e = errors[pid] { return e }
        guard alive.contains(pid) else { return ESRCH }
        if signal == SIGKILL || !ignoresTerm.contains(pid) { alive.remove(pid) }
        return 0
    }

    func isAlive(_ pid: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return alive.contains(pid)
    }
}

@Suite struct ProcessKillerTests {
    private func killer(_ s: FakeSignaler) -> ProcessKiller {
        ProcessKiller(signaler: s, grace: 1, pollInterval: 0.25, sleep: { _ in })
    }

    @Test func termsChildrenFirstAndSkipsKillWhenAllExit() {
        let s = FakeSignaler(alive: [1, 2, 3])
        let result = killer(s).terminate(pids: [1, 2, 3])
        #expect(result.succeeded)
        #expect(s.sent.map(\.pid) == [3, 2, 1])
        #expect(s.sent.allSatisfy { $0.signal == SIGTERM })
    }

    @Test func killsStubbornProcessAfterGrace() {
        let s = FakeSignaler(alive: [1, 2], ignoresTerm: [2])
        let result = killer(s).terminate(pids: [1, 2])
        #expect(result.succeeded)
        #expect(s.sent.last.map { [$0.signal, $0.pid] } == [SIGKILL, 2])
        #expect(!s.sent.contains { $0.signal == SIGKILL && $0.pid == 1 })
    }

    @Test func alreadyGoneIsSuccessAndPermissionErrorIsReported() {
        let s = FakeSignaler(alive: [2], errors: [3: EPERM])
        let result = killer(s).terminate(pids: [1, 2, 3])
        #expect(result.failures == [3: EPERM])
        #expect(result.survivors.isEmpty)
        #expect(!result.succeeded)
        #expect(!s.sent.contains { $0.signal == SIGKILL })
    }

    @Test func liveSignalerSeesOwnProcess() {
        #expect(LiveSignaler().isAlive(getpid()))
        #expect(LibProc.path(getpid()) != nil)
        #expect(LibProc.cwd(getpid()) != nil)
    }
}
