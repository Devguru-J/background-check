import Foundation
import Testing
@testable import BackgroundCheckCore

private let nodePath = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

/// URL.resolvingSymlinksInPath는 /private를 떼어내므로 libproc cwd와 맞추려면 realpath를 쓴다
private func realPath(_ url: URL) -> URL {
    guard let resolved = realpath(url.path, nil) else { return url }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved))
}

@Suite(.serialized) struct LiveIntegrationTests {
    @Test(.enabled(if: nodePath != nil, "node가 설치되어 있어야 함"))
    func detectsAndKillsNodeServerTree() throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("bgc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let dir = realPath(raw)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "{}".write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try """
        const { spawn } = require('child_process');
        const http = require('http');
        spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
        const server = http.createServer((q, s) => s.end('ok')).listen(0, '127.0.0.1', () => {
          console.log('PORT ' + server.address().port);
        });
        """.write(to: dir.appendingPathComponent("server.js"), atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath!)
        process.arguments = ["server.js"]
        process.currentDirectoryURL = dir
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        defer { if process.isRunning { process.terminate() } }

        let line = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self)
        let port = try #require(Int(line.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst("PORT ".count)))

        let scanner = SessionScanner(probe: LiveSystemProbe(), settings: ScanSettings(projectRoots: [dir.path]))
        var session: DevSession?
        for _ in 0..<30 {
            session = try scanner.scan().first { $0.projectPath == dir.path }
            if let s = session, s.memberPIDs.count == 2, s.ports.contains(port) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let found = try #require(session)
        #expect(found.rootPID == process.processIdentifier)
        #expect(found.memberPIDs.count == 2)
        #expect(found.ports.contains(port))
        #expect(found.projectName == dir.lastPathComponent)

        let result = ProcessKiller(signaler: LiveSignaler()).terminate(pids: found.memberPIDs)
        #expect(result.succeeded)
        process.waitUntilExit()
        for pid in found.memberPIDs { #expect(!LiveSignaler().isAlive(pid)) }
        #expect(try scanner.scan().first { $0.projectPath == dir.path } == nil)
    }

    @Test func liveSnapshotNeverListsClaudeCodeOrShells() throws {
        let sessions = try SessionScanner(probe: LiveSystemProbe(),
                                          settings: .defaults(home: NSHomeDirectory())).scan()
        let probe = try LiveSystemProbe().snapshot()
        let byPID = Dictionary(probe.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        for s in sessions {
            for pid in s.memberPIDs {
                guard let p = byPID[pid] else { continue }
                let name = DevProcessClassifier.basename(of: p)
                #expect(!["zsh", "bash", "fish"].contains(name), "\(p.command)")
                #expect(!(p.executablePath ?? "").contains("/claude/versions/"), "\(p.command)")
                #expect(!(p.executablePath ?? "").contains(".app/Contents/MacOS/Claude"), "\(p.command)")
            }
        }
    }
}
