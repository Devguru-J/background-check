import Foundation
import Testing
@testable import BackgroundCheckCore

private let home = "/Users/me"
private let node = "/opt/homebrew/Cellar/node/26.10.0_1/bin/node"
private let root = "/Users/me/Devguru"

private func classifier(ignore: [String] = ScanSettings.defaultIgnorePatterns) -> DevProcessClassifier {
    DevProcessClassifier(settings: ScanSettings(projectRoots: [root], ignorePatterns: ignore), home: home)
}

@Suite struct ClassifierTests {
    @Test func appHelpersAreExcluded() {
        let helper = RawProcess(pid: 10, ppid: 1,
            command: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=utility",
            executablePath: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper",
            cwd: "/", ports: [51000])
        let adobe = RawProcess(pid: 11, ppid: 1,
            command: "/Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app/Contents/MacOS/Creative Cloud Content Manager.node main.js",
            executablePath: "/Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app/Contents/MacOS/Creative Cloud Content Manager.node",
            cwd: "/", ports: [])
        let system = RawProcess(pid: 12, ppid: 1, command: "/usr/libexec/foo", executablePath: "/usr/libexec/foo", ports: [7000])
        let c = classifier()
        #expect(!c.isCandidate(helper))
        #expect(!c.isCandidate(adobe))
        #expect(!c.isCandidate(system))
    }

    @Test func npmInstalledAgentsAreNeverCandidatesEvenWithEmptyIgnoreList() {
        // ps에 실제로 보이는 형태: 프로세스 제목 "claude", 또는 bin 심볼릭 링크 경로
        let titled = RawProcess(pid: 70, ppid: 69, command: "claude", executablePath: node, cwd: "/Users/me/Devguru/site")
        let viaBin = RawProcess(pid: 71, ppid: 69, command: "node /opt/homebrew/bin/claude",
                                executablePath: node, cwd: "/Users/me/Devguru/site")
        let codex = RawProcess(pid: 72, ppid: 69, command: "node /opt/homebrew/bin/codex app-server",
                               executablePath: node, cwd: "/Users/me/Devguru/site", ports: [8123])
        let c = classifier(ignore: [])
        for p in [titled, viaBin, codex] {
            #expect(!c.isCandidate(p), "\(p.command)")
            #expect(c.isBoundary(p), "\(p.command)")
            #expect(c.isAgent(p), "\(p.command)")
        }
    }

    @Test func appBundledRuntimesWithPortsAreExcluded() {
        let bundledNode = RawProcess(pid: 80, ppid: 1, command: "node server.js",
            executablePath: "/Applications/Foo.app/Contents/Resources/node", cwd: "/", ports: [3000])
        let jetbrainsJava = RawProcess(pid: 81, ppid: 1, command: "java -Xmx2g GradleDaemon",
            executablePath: "/Applications/IntelliJ IDEA.app/Contents/jbr/Contents/Home/bin/java", cwd: "/", ports: [51234])
        let brewPython = RawProcess(pid: 82, ppid: 1, command: "python3 -m http.server",
            executablePath: "/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python",
            cwd: "/Users/me", ports: [8000])
        let c = classifier()
        #expect(!c.isCandidate(bundledNode))
        #expect(!c.isCandidate(jetbrainsJava))
        #expect(c.isCandidate(brewPython))
    }

    @Test func runtimesBundledUnderUserLibraryAreExcluded() {
        let raycast = RawProcess(pid: 13, ppid: 1, command: "Raycast Backend",
            executablePath: "/Users/me/Library/Application Support/com.raycast.macos/node/runtime/node-v22.22.2-darwin-arm64/bin/node",
            cwd: "/", ports: [7265])
        #expect(!classifier().isCandidate(raycast))
    }

    @Test func npxMcpServersAreExcluded() {
        let mcp = RawProcess(pid: 20, ppid: 19,
            command: "node /Users/me/.npm/_npx/eea2bd7412d4593b/node_modules/.bin/context7-mcp --api-key x",
            executablePath: node, cwd: "/Users/me/Devguru/site")
        #expect(classifier().isExcluded(mcp))
        #expect(!classifier().isCandidate(mcp))
    }

    @Test func claudeCodeShellsAndEditorsAreNeverCandidates() {
        let claude = RawProcess(pid: 30, ppid: 29, command: "claude",
            executablePath: "/Users/me/.local/share/claude/versions/2.1.283", cwd: "/Users/me/Devguru/site")
        let claudeViaNpm = RawProcess(pid: 31, ppid: 29,
            command: "node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js",
            executablePath: node, cwd: "/Users/me/Devguru/site")
        let vim = RawProcess(pid: 32, ppid: 29, command: "vim README.md", executablePath: "/usr/bin/vim", cwd: "/Users/me/Devguru/site")
        let zsh = RawProcess(pid: 33, ppid: 29, command: "-zsh", executablePath: "/bin/zsh", cwd: "/Users/me/Devguru/site")
        let c = classifier()
        for p in [claude, claudeViaNpm, vim, zsh] { #expect(!c.isCandidate(p), "\(p.command)") }
        #expect(c.isBoundary(claude))
        #expect(c.isBoundary(claudeViaNpm))
        #expect(c.isBoundary(zsh))
    }

    @Test func devServersAreCandidates() {
        let astro = RawProcess(pid: 40, ppid: 1,
            command: "node /Users/me/Devguru/site/node_modules/.bin/astro dev",
            executablePath: node, cwd: "/Users/me/Devguru/site", ports: [4321])
        let outsideWithPort = RawProcess(pid: 41, ppid: 1, command: "node server.js",
            executablePath: node, cwd: "/Users/me/elsewhere", ports: [3000])
        let watcherInRoot = RawProcess(pid: 42, ppid: 1, command: "node node_modules/.bin/tsc --watch",
            executablePath: node, cwd: "/Users/me/Devguru/site")
        let xcodePython = RawProcess(pid: 43, ppid: 1,
            command: "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python -m http.server 0",
            executablePath: "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python",
            cwd: "/Users/me", ports: [63355])
        let c = classifier()
        for p in [astro, outsideWithPort, watcherInRoot, xcodePython] { #expect(c.isCandidate(p), "\(p.command)") }
    }

    @Test func nodeOutsideRootWithoutPortIsNotCandidate() {
        let p = RawProcess(pid: 50, ppid: 1, command: "node script.js", executablePath: node, cwd: "/Users/me/tmp")
        #expect(!classifier().isCandidate(p))
    }

    @Test func vanishedProcessWithNoInfoIsNotCandidate() {
        let p = RawProcess(pid: 51, ppid: 1, command: "node server.js")
        #expect(!classifier().isCandidate(p))
        #expect(DevProcessClassifier.basename(of: p) == "node")
    }

    @Test func ignorePatterns() {
        let p = RawProcess(pid: 60, ppid: 1, command: "node /Users/me/Devguru/x/my-daemon.js",
                           executablePath: node, cwd: "/Users/me/Devguru/x")
        #expect(!classifier(ignore: ["my-daemon"]).isCandidate(p))
        #expect(classifier(ignore: [""]).isCandidate(p))
    }

    @Test func devBinaryNames() {
        #expect(DevProcessClassifier.isDevBinary("python3.14"))
        #expect(DevProcessClassifier.isDevBinary("npm"))
        #expect(!DevProcessClassifier.isDevBinary("2.1.283"))
        #expect(!DevProcessClassifier.isDevBinary("zsh"))
    }

    @Test func rootMatchingRequiresPathBoundary() {
        let c = classifier()
        #expect(c.projectRoot(containing: "/Users/me/Devguru") == root)
        #expect(c.projectRoot(containing: "/Users/me/Devguru/a/b") == root)
        #expect(c.projectRoot(containing: "/Users/me/DevguruOld") == nil)
        #expect(c.projectRoot(containing: nil) == nil)
    }

    @Test func settingsNormalization() {
        let s = ScanSettings(projectRoots: ["~/Devguru/", "  ", "/Users/nobody-bgc/Devguru"],
                             staleHours: 0, ignorePatterns: ["", "  x "])
            .normalized(home: "/Users/nobody-bgc")
        #expect(s.projectRoots == ["/Users/nobody-bgc/Devguru"])
        #expect(s.staleHours == 6)
        #expect(s.ignorePatterns == ["x"])
    }

    @Test func settingsNormalizationResolvesSymlinks() {
        let tmp = FileManager.default.temporaryDirectory.path  // /var/folders/... → /private/var/folders/...
        let s = ScanSettings(projectRoots: [tmp]).normalized(home: home)
        #expect(s.projectRoots.first?.hasPrefix("/private/") == true)
        #expect(s.projectRoots.first?.hasSuffix("/") == false)
    }
}
