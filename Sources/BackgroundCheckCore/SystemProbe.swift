import Darwin
import Foundation

public struct CommandRunner: Sendable {
    public init() {}

    /// 실행에 실패하거나 타임아웃이면 nil. 그 외에는 종료 코드와 표준 출력.
    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // 출력이 파이프 버퍼보다 클 수 있으므로 종료를 기다리기 전에 끝까지 읽는다
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard process.terminationReason == .exit else { return nil }
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

public enum ProbeError: Error {
    case psFailed
}

public protocol SystemProbe: Sendable {
    func snapshot() throws -> [RawProcess]
}

public struct LiveSystemProbe: SystemProbe {
    public let uid: UInt32
    public let runner: CommandRunner

    public init(uid: UInt32 = getuid(), runner: CommandRunner = CommandRunner()) {
        self.uid = uid
        self.runner = runner
    }

    public func snapshot() throws -> [RawProcess] {
        guard let ps = runner.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,uid=,etime=,command="], timeout: 3),
              ps.status == 0 else { throw ProbeError.psFailed }

        var ports: [Int32: [Int]] = [:]
        // lsof는 결과가 없으면 1을 반환한다. 실패해도 포트 없이 진행
        if let lsof = runner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pn"], timeout: 2),
           lsof.status <= 1 {
            ports = LsofParser.parse(lsof.output)
        }

        let me = getpid()
        return PsParser.parse(ps.output)
            .filter { $0.uid == uid && $0.pid != me }
            .map { row in
                RawProcess(pid: row.pid, ppid: row.ppid, elapsed: row.elapsed, command: row.command,
                           executablePath: LibProc.path(row.pid), cwd: LibProc.cwd(row.pid),
                           ports: ports[row.pid] ?? [])
            }
    }
}

public struct SessionScanner: Sendable {
    public let probe: any SystemProbe
    public let settings: ScanSettings
    public let home: String

    public init(probe: any SystemProbe, settings: ScanSettings, home: String = NSHomeDirectory()) {
        self.probe = probe
        self.settings = settings
        self.home = home
    }

    public func scan() throws -> [DevSession] {
        let normalized = settings.normalized(home: home)
        let grouper = SessionGrouper(
            classifier: DevProcessClassifier(settings: normalized, home: home),
            projectNames: ProjectNameResolver(roots: normalized.projectRoots, home: home))
        return grouper.sessions(from: try probe.snapshot())
    }
}
