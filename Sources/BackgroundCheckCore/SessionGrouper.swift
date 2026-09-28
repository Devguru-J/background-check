import Foundation

public struct SessionGrouper: Sendable {
    public let classifier: DevProcessClassifier
    public let projectNames: ProjectNameResolver

    public init(classifier: DevProcessClassifier, projectNames: ProjectNameResolver) {
        self.classifier = classifier
        self.projectNames = projectNames
    }

    public func sessions(from processes: [RawProcess]) -> [DevSession] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let children = Dictionary(grouping: processes, by: \.ppid)

        var roots: [Int32] = []
        for p in processes where classifier.isCandidate(p) {
            let root = climb(from: p, byPID: byPID)
            // 에이전트가 셸을 거치지 않고 직접 띄운 프로세스는 MCP 서버다 (Bash 도구로 띄운 dev 서버는 셸을 거친다)
            if let parent = byPID[root.ppid], classifier.isAgent(parent) { continue }
            if !roots.contains(root.pid) { roots.append(root.pid) }
        }
        let memberLists = roots.map { members(of: $0, children: children) }

        var sessions: [DevSession] = []
        for (i, root) in roots.enumerated() {
            // 다른 세션 안에 들어 있는 루트는 그 세션에 합쳐진다
            let nested = memberLists.indices.contains { j in j != i && memberLists[j].contains(root) }
            if nested { continue }
            if let session = makeSession(memberPIDs: memberLists[i], byPID: byPID) { sessions.append(session) }
        }
        return sessions.sorted { $0.uptime != $1.uptime ? $0.uptime > $1.uptime : $0.rootPID < $1.rootPID }
    }

    func climb(from start: RawProcess, byPID: [Int32: RawProcess]) -> RawProcess {
        var current = start
        var seen: Set<Int32> = [start.pid]
        while let parent = byPID[current.ppid], !seen.contains(parent.pid) {
            if !classifier.isBoundary(parent) {
                current = parent
            } else if DevProcessClassifier.shells.contains(DevProcessClassifier.basename(of: parent)),
                      let grand = byPID[parent.ppid], !seen.contains(grand.pid), !classifier.isBoundary(grand) {
                // npm → sh -c → node: 패키지 매니저가 띄운 sh는 건너뛴다
                seen.insert(parent.pid)
                current = grand
            } else {
                break
            }
            seen.insert(current.pid)
        }
        return current
    }

    func members(of root: Int32, children: [Int32: [RawProcess]]) -> [Int32] {
        var result: [Int32] = [root]
        var i = 0
        while i < result.count {
            for child in (children[result[i]] ?? []).sorted(by: { $0.pid < $1.pid }) where !result.contains(child.pid) {
                result.append(child.pid)
            }
            i += 1
        }
        return result
    }

    func makeSession(memberPIDs: [Int32], byPID: [Int32: RawProcess]) -> DevSession? {
        let procs = memberPIDs.compactMap { byPID[$0] }
        guard let root = procs.first else { return nil }
        if procs.contains(where: { classifier.isIgnored(command: $0.command) }) { return nil }
        // `npm exec <패키지>`의 부모 npm은 프로젝트 폴더에서 떠 있어 후보가 되지만, 실제 실행은 npx 캐시에서 한다
        if procs.contains(where: classifier.runsFromNpxCache) { return nil }

        let project = projectNames.resolve(cwds: procs.compactMap(\.cwd))
        let ignoreKey = procs.first {
            DevProcessClassifier.isDevBinary(DevProcessClassifier.basename(of: $0))
                && DevProcessClassifier.arguments(of: $0).contains("/")
        }?.command ?? root.command

        return DevSession(
            rootPID: root.pid,
            memberPIDs: memberPIDs,
            command: root.command,
            ignoreKey: ignoreKey,
            toolName: ToolNameResolver.resolve(commands: procs.map(\.command),
                                               fallback: DevProcessClassifier.basename(of: root)),
            projectName: project.name,
            projectPath: project.path,
            ports: Array(Set(procs.flatMap(\.ports))).sorted(),
            uptime: root.elapsed,
            isStale: root.elapsed >= classifier.settings.staleHours * 3600)
    }
}
