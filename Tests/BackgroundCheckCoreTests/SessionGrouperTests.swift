import Testing
@testable import BackgroundCheckCore

private let home = "/Users/me"
private let node = "/opt/homebrew/Cellar/node/26.10.0_1/bin/node"
private let site = "/Users/me/Devguru/site"

private func grouper(ignore: [String] = ScanSettings.defaultIgnorePatterns,
                     existing: Set<String> = ["/Users/me/Devguru/site/package.json"]) -> SessionGrouper {
    let settings = ScanSettings(projectRoots: ["/Users/me/Devguru"], ignorePatterns: ignore)
    return SessionGrouper(
        classifier: DevProcessClassifier(settings: settings, home: home),
        projectNames: ProjectNameResolver(roots: settings.projectRoots, home: home, fileExists: { existing.contains($0) }))
}

/// claude → zsh → npm → sh → node(astro) → esbuild
private func claudeTree(npmCwd: String = site) -> [RawProcess] {
    [
        RawProcess(pid: 100, ppid: 50, elapsed: 9000, command: "claude",
                   executablePath: "/Users/me/.local/share/claude/versions/2.1.283", cwd: site),
        RawProcess(pid: 101, ppid: 100, elapsed: 7400, command: "/bin/zsh -c npm run dev", executablePath: "/bin/zsh", cwd: site),
        RawProcess(pid: 102, ppid: 101, elapsed: 7300, command: "npm run dev", executablePath: node, cwd: npmCwd),
        RawProcess(pid: 103, ppid: 102, elapsed: 7290, command: "sh -c astro dev", executablePath: "/bin/sh", cwd: site),
        RawProcess(pid: 104, ppid: 103, elapsed: 7280, command: "node \(site)/node_modules/.bin/astro dev",
                   executablePath: node, cwd: site, ports: [4321]),
        RawProcess(pid: 105, ppid: 104, elapsed: 7270, command: "esbuild --service=0.21.5 --ping",
                   executablePath: "\(site)/node_modules/@esbuild/darwin-arm64/bin/esbuild", cwd: site),
    ]
}

@Suite struct SessionGrouperTests {
    @Test func groupsNpmTreeUnderClaudeIntoOneSession() {
        let sessions = grouper().sessions(from: claudeTree())
        #expect(sessions.count == 1)
        let s = sessions[0]
        #expect(s.rootPID == 102)
        #expect(s.memberPIDs == [102, 103, 104, 105])
        #expect(!s.memberPIDs.contains(100) && !s.memberPIDs.contains(101))
        #expect(s.toolName == "astro dev")
        #expect(s.projectName == "site")
        #expect(s.projectPath == site)
        #expect(s.ports == [4321])
        #expect(s.uptime == 7300)
        #expect(!s.isStale)
        #expect(s.command == "npm run dev")
        #expect(s.ignoreKey == "node \(site)/node_modules/.bin/astro dev")
    }

    @Test func groupsUnderNpmEvenWhenProjectIsOutsideRoots() {
        let outside = "/Users/me/other"
        let tree = claudeTree(npmCwd: outside).map { p -> RawProcess in
            var p = p
            if p.pid != 104 { p.ports = [] }
            p.cwd = outside
            return p
        }
        let sessions = grouper().sessions(from: tree)
        #expect(sessions.map(\.rootPID) == [102])
    }

    @Test func orphanIsItsOwnStaleSession() {
        let orphan = RawProcess(pid: 200, ppid: 1, elapsed: 3 * 86400,
                                command: "node /Users/me/Devguru/blog/node_modules/.bin/astro dev",
                                executablePath: node, cwd: "/Users/me/Devguru/blog", ports: [4322])
        let sessions = grouper().sessions(from: [orphan])
        #expect(sessions.count == 1)
        #expect(sessions[0].memberPIDs == [200])
        #expect(sessions[0].isStale)
        #expect(sessions[0].projectName == "blog")
    }

    @Test func sortsByUptimeDescending() {
        let orphan = RawProcess(pid: 200, ppid: 1, elapsed: 3 * 86400, command: "node a.js",
                                executablePath: node, cwd: "/Users/me/Devguru/blog", ports: [4322])
        let sessions = grouper().sessions(from: claudeTree() + [orphan])
        #expect(sessions.map(\.rootPID) == [200, 102])
    }

    @Test func excludedProcessesProduceNoSession() {
        let mcp = RawProcess(pid: 300, ppid: 100, command: "node /Users/me/.npm/_npx/abc/node_modules/.bin/context7-mcp",
                             executablePath: node, cwd: site)
        let claude = claudeTree()[0]
        #expect(grouper().sessions(from: [claude, mcp]).isEmpty)
    }

    @Test func npmExecSessionRunningFromNpxCacheIsHidden() {
        // Claude Code가 띄운 MCP 서버: claude → npm exec (cwd=프로젝트) → node ~/.npm/_npx/...
        let npmExec = RawProcess(pid: 400, ppid: 100, command: "npm exec @upstash/context7-mcp --api-key x",
                                 executablePath: node, cwd: site)
        let mcp = RawProcess(pid: 401, ppid: 400,
                             command: "node /Users/me/.npm/_npx/eea2/node_modules/.bin/context7-mcp --api-key x",
                             executablePath: node, cwd: site)
        #expect(grouper().sessions(from: [claudeTree()[0], npmExec, mcp]).isEmpty)
    }

    @Test func npmExecOfLocalToolIsStillShown() {
        let npmExec = RawProcess(pid: 410, ppid: 1, command: "npm exec vite", executablePath: node, cwd: site)
        let vite = RawProcess(pid: 411, ppid: 410, command: "node \(site)/node_modules/.bin/vite",
                              executablePath: node, cwd: site, ports: [5173])
        #expect(grouper().sessions(from: [npmExec, vite]).map(\.rootPID) == [410])
    }

    @Test func ignoringChildHidesWholeSession() {
        let sessions = grouper(ignore: ["site/node_modules/.bin/astro"]).sessions(from: claudeTree())
        #expect(sessions.isEmpty)
    }

    @Test func freshMatchGuardsAgainstPidReuse() {
        let s = grouper().sessions(from: claudeTree())[0]
        #expect(SessionMatcher.fresh(s, in: [s]) == s)
        var reused = s
        reused.command = "node unrelated.js"
        #expect(SessionMatcher.fresh(s, in: [reused]) == nil)
        #expect(SessionMatcher.fresh(s, in: []) == nil)
    }
}
