import BackgroundCheckCore
import Darwin
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var sessions: [DevSession] = []
    private(set) var scanFailed = false
    private(set) var terminating: Set<Int32> = []
    private(set) var terminateErrors: [Int32: String] = [:]

    var settings: ScanSettings {
        didSet {
            SettingsStore.save(settings)
            Task { await scan() }
        }
    }

    /// 패널이 열려 있으면 3초, 닫혀 있으면 15초마다 스캔한다.
    var isPanelOpen = false {
        didSet { if isPanelOpen != oldValue { restartLoop() } }
    }

    var staleCount: Int { sessions.filter(\.isStale).count }

    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var loop: Task<Void, Never>?

    init() {
        settings = SettingsStore.load()
        restartLoop()
    }

    private func restartLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.scan()
                let interval: Double = self.isPanelOpen ? 3 : 15
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let scanner = SessionScanner(probe: LiveSystemProbe(), settings: settings)
        do {
            sessions = try await Task.detached(priority: .utility) { try scanner.scan() }.value
            scanFailed = false
        } catch {
            scanFailed = true
        }
    }

    func terminate(_ session: DevSession) async {
        guard !terminating.contains(session.id) else { return }
        terminating.insert(session.id)
        terminateErrors[session.id] = nil
        let scanner = SessionScanner(probe: LiveSystemProbe(), settings: settings)
        let result: KillResult? = await Task.detached(priority: .userInitiated) {
            // PID 재사용 방지: 최신 스캔에서 같은 세션일 때만 종료
            guard let current = try? scanner.scan(),
                  let fresh = SessionMatcher.fresh(session, in: current) else { return nil }
            return ProcessKiller(signaler: LiveSignaler()).terminate(pids: fresh.memberPIDs)
        }.value
        terminating.remove(session.id)
        if let result, !result.succeeded {
            terminateErrors[session.id] = result.failures.values.contains(EPERM) ? "권한 없음" : "종료 실패"
        }
        await scan()
    }

    func terminateAll() async {
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { await self.terminate(session) }
            }
        }
    }

    func ignore(_ session: DevSession) {
        guard !settings.ignorePatterns.contains(session.ignoreKey) else { return }
        settings.ignorePatterns.append(session.ignoreKey)
    }
}
