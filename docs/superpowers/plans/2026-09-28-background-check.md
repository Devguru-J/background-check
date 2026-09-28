# Background Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 켜둔 채 잊어버린 dev 서버(astro, vite, node 등)를 macOS 메뉴바에서 보고 클릭 한 번으로 종료하는 앱을 만든다.

**Architecture:** SwiftPM 패키지. 로직은 `BackgroundCheckCore` 라이브러리에 둔다(ps/lsof/libproc으로 수집 → 분류 → 세션 묶기 → 종료). UI 의존이 없어 Swift Testing으로 테스트한다. `BackgroundCheck` 실행 타깃은 SwiftUI `MenuBarExtra` 앱으로, Core를 호출해 결과를 그리기만 한다. 스크립트로 `.app` 번들을 조립해 `~/Applications`에 설치한다.

**Tech Stack:** Swift 6.4 toolchain (language mode 5), SwiftUI, Observation, ServiceManagement, Darwin libproc, Swift Testing, macOS 14+

**Spec:** `docs/superpowers/specs/2026-09-28-background-check-design.md`

## Global Constraints

- 최소 macOS 14 (`platforms: [.macOS(.v14)]`)
- 외부 의존성 없음 (Apple 프레임워크만)
- Dock 아이콘 없음: Info.plist `LSUIElement = true`
- 번들 ID `dev.memory.backgroundcheck`, 앱 이름 `Background Check`, 실행 파일 `BackgroundCheck`
- 현재 사용자 소유 프로세스만 대상
- 기본 프로젝트 루트 `~/Devguru`, 오래됨 기준 기본 6시간
- 기본 무시 목록: `@anthropic-ai/claude-code`, `claude/versions/`, `codex`
- 스캔 주기: 패널 닫힘 15초, 열림 3초(열 때 즉시 1회). lsof 타임아웃 2초, ps 3초
- 종료: SIGTERM → 0.25초 간격 확인 → 3초 후 SIGKILL. ESRCH는 성공
- UI 문구는 한국어
- **Claude Code(`claude`), 셸, 에디터는 절대 목록/종료 대상이 되어선 안 된다**
- Core의 설정 타입 이름은 `ScanSettings` (SwiftUI `Settings` scene과 이름 충돌 방지)

## Review Focus

1. **목록을 띄운 뒤 ✕를 누르는 사이 PID가 재사용됨** → 엉뚱한 프로세스를 죽이면 안 된다. 종료 직전 재스캔해서 같은 루트 PID·같은 명령어인 세션만 종료 (Task 6 `SessionMatcher` 테스트)
2. **프로젝트 루트를 `~/Devguru/`, 끝 슬래시, `/tmp`(→`/private/tmp`) 심볼릭 링크로 입력** → 정상 매칭돼야 한다 (Task 3 `normalized` 테스트)
3. **경로에 공백이 있는 프로젝트** (`~/My Projects/site`) → 도구 이름·분류가 깨지지 않아야 한다 (Task 4 테스트)
4. **스캔 도중 프로세스가 사라져 exe/cwd가 nil** → 크래시 없이 후보에서 빠져야 한다 (Task 3 테스트)
5. **자식 node 하나만 무시 목록에 넣음** → npm 루트 세션 전체가 숨겨져야 하고, 빈 무시 패턴은 모든 걸 숨기면 안 된다 (Task 3, Task 6 테스트)

---

## File Structure

```
Package.swift
Sources/BackgroundCheckCore/
  PsParser.swift            ps 출력 → PsRow, etime 파싱
  LsofParser.swift          lsof -F pn 출력 → pid별 포트
  RawProcess.swift          수집 결과 모델
  ScanSettings.swift        설정 값 + 정규화
  DevProcessClassifier.swift 후보/제외/경계 판정
  ToolNameResolver.swift    명령어 → "astro dev"
  ProjectNameResolver.swift cwd → 프로젝트 이름/경로
  DevSession.swift          세션 모델 + SessionMatcher
  SessionGrouper.swift      프로세스 트리 → 세션
  ProcessKiller.swift       Signaler 프로토콜, TERM→KILL
  LibProc.swift             libproc 래퍼 + LiveSignaler
  SystemProbe.swift         CommandRunner, LiveSystemProbe, SessionScanner
  Formatting.swift          UptimeFormatter, PathDisplay
Sources/BackgroundCheck/
  BackgroundCheckApp.swift  @main, MenuBarExtra, Settings scene
  SettingsStore.swift       UserDefaults 저장
  AppModel.swift            @Observable 상태, 스캔 루프, 종료
  MenuBarLabel.swift        메뉴바 아이콘 + 개수
  MenuPanelView.swift       패널
  SessionRowView.swift      세션 행
  WindowKeyObserver.swift   패널 열림/닫힘 감지
  SettingsView.swift        설정 창
Tests/BackgroundCheckCoreTests/
  PsParserTests.swift, LsofParserTests.swift, ClassifierTests.swift,
  ToolNameResolverTests.swift, ProjectNameResolverTests.swift,
  SessionGrouperTests.swift, ProcessKillerTests.swift,
  LiveIntegrationTests.swift, FormattingTests.swift
scripts/build-app.sh, scripts/install.sh
```

---

### Task 1: 패키지 뼈대 + PsParser

**Files:**
- Create: `Package.swift`
- Create: `Sources/BackgroundCheckCore/PsParser.swift`
- Test: `Tests/BackgroundCheckCoreTests/PsParserTests.swift`

**Interfaces:**
- Produces: `struct PsRow { pid: Int32, ppid: Int32, uid: UInt32, elapsed: TimeInterval, command: String }`, `PsParser.parse(_ output: String) -> [PsRow]`, `PsParser.parseElapsed(_ s: String) -> TimeInterval?`

- [ ] **Step 1: Package.swift 작성**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackgroundCheck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BackgroundCheckCore"),
        .testTarget(name: "BackgroundCheckCoreTests", dependencies: ["BackgroundCheckCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: 실패하는 테스트 작성** — `Tests/BackgroundCheckCoreTests/PsParserTests.swift`

```swift
import Testing
@testable import BackgroundCheckCore

@Suite struct PsParserTests {
    @Test func elapsedFormats() {
        #expect(PsParser.parseElapsed("00:05") == 5)
        #expect(PsParser.parseElapsed("12:34") == 754)
        #expect(PsParser.parseElapsed("01:00:00") == 3600)
        #expect(PsParser.parseElapsed("11-03:02:26") == Double(11 * 86400 + 3 * 3600 + 2 * 60 + 26))
        #expect(PsParser.parseElapsed("abc") == nil)
        #expect(PsParser.parseElapsed("5") == nil)
    }

    @Test func parsesRowsWithSpacesInCommand() {
        let out = """
          543     1   501 11-03:03:06 /System/Library/CoreServices/powerd.bundle/powerd
        19482 18582   501       43:18 claude
        24606     1   501 06-04:27:22 /Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app/Contents/MacOS/Creative Cloud Content Manager.node --flag
        garbage line
        """
        let rows = PsParser.parse(out)
        #expect(rows.count == 3)
        #expect(rows[1] == PsRow(pid: 19482, ppid: 18582, uid: 501, elapsed: 2598, command: "claude"))
        #expect(rows[2].command.hasSuffix("Content Manager.node --flag"))
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter PsParserTests`
Expected: 컴파일 실패 (`cannot find 'PsParser' in scope`)

- [ ] **Step 4: 구현** — `Sources/BackgroundCheckCore/PsParser.swift`

```swift
import Foundation

public struct PsRow: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var elapsed: TimeInterval
    public var command: String

    public init(pid: Int32, ppid: Int32, uid: UInt32, elapsed: TimeInterval, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.elapsed = elapsed
        self.command = command
    }
}

public enum PsParser {
    /// `ps -axww -o pid=,ppid=,uid=,etime=,command=` 출력을 파싱한다. 형식이 깨진 줄은 버린다.
    public static func parse(_ output: String) -> [PsRow] {
        output.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> PsRow? {
        let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        var rest = Substring(line)
        var fields: [Substring] = []
        for _ in 0..<4 {
            rest = rest.drop(while: isBlank)
            guard let end = rest.firstIndex(where: isBlank) else { return nil }
            fields.append(rest[..<end])
            rest = rest[end...]
        }
        let command = rest.drop(while: isBlank)
        guard !command.isEmpty,
              let pid = Int32(fields[0]),
              let ppid = Int32(fields[1]),
              let uid = UInt32(fields[2]),
              let elapsed = parseElapsed(String(fields[3])) else { return nil }
        return PsRow(pid: pid, ppid: ppid, uid: uid, elapsed: elapsed, command: String(command))
    }

    /// `[[DD-]HH:]MM:SS` 형식의 etime을 초로 바꾼다.
    public static func parseElapsed(_ s: String) -> TimeInterval? {
        var days = 0
        var clock = Substring(s)
        if let dash = clock.firstIndex(of: "-") {
            guard let d = Int(clock[..<dash]) else { return nil }
            days = d
            clock = clock[clock.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == clock.split(separator: ":").count, (2...3).contains(parts.count) else { return nil }
        let (h, m, sec) = parts.count == 3 ? (parts[0], parts[1], parts[2]) : (0, parts[0], parts[1])
        return TimeInterval(((days * 24 + h) * 60 + m) * 60 + sec)
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift test --filter PsParserTests`
Expected: 2 tests passed

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat(core): package scaffold and ps output parser"
```

---

### Task 2: LsofParser

**Files:**
- Create: `Sources/BackgroundCheckCore/LsofParser.swift`
- Test: `Tests/BackgroundCheckCoreTests/LsofParserTests.swift`

**Interfaces:**
- Produces: `LsofParser.parse(_ output: String) -> [Int32: [Int]]` (포트 중복 제거·오름차순)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
@testable import BackgroundCheckCore

@Suite struct LsofParserTests {
    @Test func parsesPortsPerPid() {
        let out = "p949\nf10\nn*:62686\nf15\nn*:62686\np1782\nf6\nn127.0.0.1:14440\nf7\nn[::1]:3000\nf8\nn*:*\n"
        #expect(LsofParser.parse(out) == [949: [62686], 1782: [3000, 14440]])
    }

    @Test func emptyOutput() {
        #expect(LsofParser.parse("").isEmpty)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter LsofParserTests`
Expected: 컴파일 실패 (`cannot find 'LsofParser'`)

- [ ] **Step 3: 구현**

```swift
import Foundation

public enum LsofParser {
    /// `lsof -nP -iTCP -sTCP:LISTEN -F pn` 출력을 pid별 LISTEN 포트(중복 제거, 오름차순)로 바꾼다.
    public static func parse(_ output: String) -> [Int32: [Int]] {
        var result: [Int32: Set<Int>] = [:]
        var current: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                current = Int32(value)
            case "n":
                guard let pid = current,
                      let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                result[pid, default: []].insert(port)
            default:
                continue
            }
        }
        return result.mapValues { $0.sorted() }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter LsofParserTests`
Expected: 2 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/BackgroundCheckCore/LsofParser.swift Tests/BackgroundCheckCoreTests/LsofParserTests.swift
git commit -m "feat(core): lsof listen-port parser"
```

---

### Task 3: RawProcess, ScanSettings, DevProcessClassifier

**Files:**
- Create: `Sources/BackgroundCheckCore/RawProcess.swift`
- Create: `Sources/BackgroundCheckCore/ScanSettings.swift`
- Create: `Sources/BackgroundCheckCore/DevProcessClassifier.swift`
- Test: `Tests/BackgroundCheckCoreTests/ClassifierTests.swift`

**Interfaces:**
- Produces:
  - `struct RawProcess { pid: Int32, ppid: Int32, elapsed: TimeInterval, command: String, executablePath: String?, cwd: String?, ports: [Int] }` + memberwise init with defaults `elapsed = 0, executablePath = nil, cwd = nil, ports = []`
  - `struct ScanSettings: Codable { projectRoots: [String], staleHours: Double, ignorePatterns: [String] }`, `ScanSettings.defaultIgnorePatterns`, `ScanSettings.defaults(home:)`, `func normalized(home:) -> ScanSettings`
  - `struct DevProcessClassifier { init(settings: ScanSettings, home: String); let settings; let home }`
    - `static basename(of: RawProcess) -> String`, `static isDevBinary(_ name: String) -> Bool`, `static shells: Set<String>`
    - `isExcluded(_:) -> Bool`, `isCandidate(_:) -> Bool`, `isBoundary(_:) -> Bool`, `projectRoot(containing: String?) -> String?`, `isIgnored(command: String) -> Bool`

- [ ] **Step 1: 실패하는 테스트 작성** — `ClassifierTests.swift`

```swift
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
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ClassifierTests`
Expected: 컴파일 실패 (`cannot find 'RawProcess'`)

- [ ] **Step 3: RawProcess 구현**

```swift
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
```

- [ ] **Step 4: ScanSettings 구현**

```swift
import Foundation

public struct ScanSettings: Equatable, Codable, Sendable {
    public var projectRoots: [String]
    public var staleHours: Double
    public var ignorePatterns: [String]

    /// npm으로 설치한 Claude Code/Codex가 dev 서버로 잡히지 않게 막는다.
    public static let defaultIgnorePatterns = ["@anthropic-ai/claude-code", "claude/versions/", "codex"]

    public init(projectRoots: [String], staleHours: Double = 6,
                ignorePatterns: [String] = ScanSettings.defaultIgnorePatterns) {
        self.projectRoots = projectRoots
        self.staleHours = staleHours
        self.ignorePatterns = ignorePatterns
    }

    public static func defaults(home: String) -> ScanSettings {
        ScanSettings(projectRoots: [home + "/Devguru"])
    }

    /// ~ 확장, 끝 슬래시 제거, 심볼릭 링크 해석, 빈 값·중복 제거, 잘못된 기준 시간 복구
    public func normalized(home: String) -> ScanSettings {
        var roots: [String] = []
        for raw in projectRoots {
            var path = raw.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            if path.hasPrefix("~") { path = home + path.dropFirst() }
            path = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            if !roots.contains(path) { roots.append(path) }
        }
        let patterns = ignorePatterns
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return ScanSettings(projectRoots: roots,
                            staleHours: staleHours > 0 ? staleHours : 6,
                            ignorePatterns: patterns)
    }
}
```

- [ ] **Step 5: DevProcessClassifier 구현**

```swift
import Foundation

/// 프로세스가 dev 서버 후보인지, 제외 대상인지, 세션 묶기의 경계인지 판정한다.
public struct DevProcessClassifier: Sendable {
    public static let runtimes: Set<String> = [
        "node", "bun", "deno", "python", "python3", "Python", "ruby", "php", "java", "go",
        "air", "uvicorn", "gunicorn", "hugo", "caddy",
    ]
    public static let packageManagers: Set<String> = ["npm", "npx", "pnpm", "yarn", "bunx"]
    public static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]

    public let settings: ScanSettings
    public let home: String

    public init(settings: ScanSettings, home: String) {
        self.settings = settings
        self.home = home
    }

    public static func basename(of p: RawProcess) -> String {
        (executable(of: p) as NSString).lastPathComponent
    }

    public static func isDevBinary(_ name: String) -> Bool {
        runtimes.contains(name) || packageManagers.contains(name) || name.hasPrefix("python3.")
    }

    public func isCandidate(_ p: RawProcess) -> Bool {
        guard Self.isDevBinary(Self.basename(of: p)), !isExcluded(p) else { return false }
        return !p.ports.isEmpty || projectRoot(containing: p.cwd) != nil
    }

    public func isExcluded(_ p: RawProcess) -> Bool {
        let exe = Self.executable(of: p)
        if exe.hasPrefix("/System/") || exe.hasPrefix("/usr/libexec/") { return true }
        if !Self.isDevBinary(Self.basename(of: p)) && exe.contains(".app/Contents/") { return true }
        let args = Self.arguments(of: p)
        let excludedArgMarkers = [
            ".app/Contents/", home + "/.npm/_npx/", home + "/Library/", home + "/.vscode/", home + "/.cursor/",
        ]
        if excludedArgMarkers.contains(where: { args.contains($0) }) { return true }
        return isIgnored(command: p.command)
    }

    /// 세션 루트를 찾아 부모를 따라 올라갈 때 멈추는 지점
    public func isBoundary(_ p: RawProcess) -> Bool {
        p.pid <= 1 || !Self.isDevBinary(Self.basename(of: p)) || isExcluded(p)
    }

    public func isIgnored(command: String) -> Bool {
        settings.ignorePatterns.contains { !$0.isEmpty && command.contains($0) }
    }

    public func projectRoot(containing path: String?) -> String? {
        guard let path else { return nil }
        return settings.projectRoots.first { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func executable(of p: RawProcess) -> String {
        p.executablePath ?? p.command.split(separator: " ").first.map(String.init) ?? ""
    }

    /// 명령어에서 실행 파일 부분을 뺀 인자 문자열
    static func arguments(of p: RawProcess) -> Substring {
        if let exe = p.executablePath, p.command.hasPrefix(exe) { return p.command.dropFirst(exe.count) }
        guard let space = p.command.firstIndex(of: " ") else { return "" }
        return p.command[space...]
    }
}
```

- [ ] **Step 6: 통과 확인**

Run: `swift test --filter ClassifierTests`
Expected: 11 tests passed

- [ ] **Step 7: Commit**

```bash
git add Sources/BackgroundCheckCore Tests/BackgroundCheckCoreTests/ClassifierTests.swift
git commit -m "feat(core): process model, settings, dev-process classifier"
```

---

### Task 4: ToolNameResolver

**Files:**
- Create: `Sources/BackgroundCheckCore/ToolNameResolver.swift`
- Test: `Tests/BackgroundCheckCoreTests/ToolNameResolverTests.swift`

**Interfaces:**
- Produces: `ToolNameResolver.resolve(commands: [String], fallback: String) -> String` — commands는 세션 루트가 먼저 오는 멤버 명령어 목록

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
@testable import BackgroundCheckCore

@Suite struct ToolNameResolverTests {
    @Test(arguments: [
        ("node /Users/me/Devguru/site/node_modules/.bin/astro dev", "astro dev"),
        ("node /Users/me/site/node_modules/astro/astro.js preview", "astro preview"),
        ("node /Users/me/site/node_modules/vite/bin/vite.js", "vite"),
        ("node /Users/me/site/node_modules/.bin/next dev --turbo", "next dev"),
        ("python3 -m http.server 8000", "http.server"),
        ("python manage.py runserver", "django runserver"),
        ("/opt/homebrew/bin/hugo server -D", "hugo server"),
        ("node /Users/me/My Projects/site/node_modules/.bin/astro dev", "astro dev"),
    ])
    func resolvesKnownTools(command: String, expected: String) {
        #expect(ToolNameResolver.resolve(commands: [command], fallback: "node") == expected)
    }

    @Test func looksPastGenericRootCommand() {
        let commands = ["npm run dev", "sh -c astro dev", "node /x/node_modules/.bin/astro dev"]
        #expect(ToolNameResolver.resolve(commands: commands, fallback: "node") == "astro dev")
    }

    @Test func fallsBack() {
        #expect(ToolNameResolver.resolve(commands: ["node server.js"], fallback: "node") == "node")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ToolNameResolverTests`
Expected: 컴파일 실패

- [ ] **Step 3: 구현**

```swift
import Foundation

public enum ToolNameResolver {
    /// 확장자를 뗀 파일 이름 → 표시 이름
    static let markers: [String: String] = [
        "astro": "astro", "vite": "vite", "next": "next", "nuxt": "nuxt", "nuxi": "nuxt",
        "remix": "remix", "wrangler": "wrangler", "webpack": "webpack", "webpack-dev-server": "webpack",
        "storybook": "storybook", "parcel": "parcel", "eleventy": "eleventy", "gatsby": "gatsby",
        "svelte-kit": "svelte-kit", "turbo": "turbo", "nodemon": "nodemon", "tsx": "tsx",
        "uvicorn": "uvicorn", "flask": "flask", "manage": "django", "http.server": "http.server",
        "rails": "rails", "hugo": "hugo",
    ]
    static let subcommands: Set<String> = ["dev", "preview", "serve", "server", "start", "runserver", "run", "watch"]
    static let scriptExtensions = [".js", ".mjs", ".cjs", ".ts", ".py"]

    public static func resolve(commands: [String], fallback: String) -> String {
        for command in commands {
            let tokens = command.split(separator: " ").map(String.init)
            for (i, token) in tokens.enumerated() {
                guard let name = markers[strip(token)] else { continue }
                if i + 1 < tokens.count, subcommands.contains(tokens[i + 1]) {
                    return "\(name) \(tokens[i + 1])"
                }
                return name
            }
        }
        return fallback
    }

    static func strip(_ token: String) -> String {
        var name = (token as NSString).lastPathComponent
        if let ext = scriptExtensions.first(where: { name.hasSuffix($0) }) { name.removeLast(ext.count) }
        return name
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter ToolNameResolverTests`
Expected: 10 test cases passed

- [ ] **Step 5: Commit**

```bash
git add Sources/BackgroundCheckCore/ToolNameResolver.swift Tests/BackgroundCheckCoreTests/ToolNameResolverTests.swift
git commit -m "feat(core): tool name resolver"
```

---

### Task 5: ProjectNameResolver

**Files:**
- Create: `Sources/BackgroundCheckCore/ProjectNameResolver.swift`
- Test: `Tests/BackgroundCheckCoreTests/ProjectNameResolverTests.swift`

**Interfaces:**
- Produces: `struct ProjectInfo: Equatable { name: String, path: String? }`, `struct ProjectNameResolver { init(roots: [String], home: String, fileExists: @escaping @Sendable (String) -> Bool = FileManager 기본); func resolve(cwds: [String]) -> ProjectInfo }`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
@testable import BackgroundCheckCore

@Suite struct ProjectNameResolverTests {
    private func resolver(existing: Set<String>) -> ProjectNameResolver {
        ProjectNameResolver(roots: ["/Users/me/Devguru"], home: "/Users/me", fileExists: { existing.contains($0) })
    }

    @Test func walksUpToNearestProjectMarker() {
        let r = resolver(existing: ["/Users/me/Devguru/sites/my-site/package.json"])
        #expect(r.resolve(cwds: ["/Users/me/Devguru/sites/my-site/src"])
                == ProjectInfo(name: "my-site", path: "/Users/me/Devguru/sites/my-site"))
    }

    @Test func prefersCwdInsideRoot() {
        let r = resolver(existing: ["/Users/me/Devguru/api/.git"])
        #expect(r.resolve(cwds: ["/", "/Users/me/elsewhere", "/Users/me/Devguru/api"])
                == ProjectInfo(name: "api", path: "/Users/me/Devguru/api"))
    }

    @Test func fallsBackToCwdFolderName() {
        let r = resolver(existing: [])
        #expect(r.resolve(cwds: ["/Users/me/Devguru/loose"]) == ProjectInfo(name: "loose", path: "/Users/me/Devguru/loose"))
        #expect(r.resolve(cwds: ["/tmp/x"]) == ProjectInfo(name: "x", path: "/tmp/x"))
    }

    @Test func doesNotWalkAboveHomeOutsideRoots() {
        let r = resolver(existing: ["/Users/package.json"])
        #expect(r.resolve(cwds: ["/Users/me/other"]) == ProjectInfo(name: "other", path: "/Users/me/other"))
    }

    @Test func unknownWhenNoCwd() {
        #expect(resolver(existing: []).resolve(cwds: ["/"]) == ProjectInfo(name: "(unknown)", path: nil))
        #expect(resolver(existing: []).resolve(cwds: []) == ProjectInfo(name: "(unknown)", path: nil))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ProjectNameResolverTests`
Expected: 컴파일 실패

- [ ] **Step 3: 구현**

```swift
import Foundation

public struct ProjectInfo: Equatable, Sendable {
    public var name: String
    public var path: String?

    public init(name: String, path: String?) {
        self.name = name
        self.path = path
    }
}

public struct ProjectNameResolver: Sendable {
    public static let markerFiles = ["package.json", "pyproject.toml", ".git"]

    public let roots: [String]
    public let home: String
    public let fileExists: @Sendable (String) -> Bool

    public init(roots: [String], home: String,
                fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.roots = roots
        self.home = home
        self.fileExists = fileExists
    }

    /// cwds: 세션 루트가 먼저 오는 멤버 cwd 목록
    public func resolve(cwds: [String]) -> ProjectInfo {
        let usable = cwds.filter { $0 != "/" }
        guard let cwd = usable.first(where: { root(containing: $0) != nil }) ?? usable.first else {
            return ProjectInfo(name: "(unknown)", path: nil)
        }
        let stop = root(containing: cwd) ?? home
        var dir = cwd
        while true {
            if Self.markerFiles.contains(where: { fileExists(dir + "/" + $0) }) {
                return ProjectInfo(name: (dir as NSString).lastPathComponent, path: dir)
            }
            guard dir != stop, dir != "/", dir.hasPrefix(stop + "/") else { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return ProjectInfo(name: (cwd as NSString).lastPathComponent, path: cwd)
    }

    private func root(containing path: String) -> String? {
        roots.first { path == $0 || path.hasPrefix($0 + "/") }
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter ProjectNameResolverTests`
Expected: 5 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/BackgroundCheckCore/ProjectNameResolver.swift Tests/BackgroundCheckCoreTests/ProjectNameResolverTests.swift
git commit -m "feat(core): project name resolver"
```

---

### Task 6: DevSession, SessionGrouper, SessionMatcher

**Files:**
- Create: `Sources/BackgroundCheckCore/DevSession.swift`
- Create: `Sources/BackgroundCheckCore/SessionGrouper.swift`
- Test: `Tests/BackgroundCheckCoreTests/SessionGrouperTests.swift`

**Interfaces:**
- Consumes: `RawProcess`, `ScanSettings`, `DevProcessClassifier` (Task 3), `ToolNameResolver` (Task 4), `ProjectNameResolver`, `ProjectInfo` (Task 5)
- Produces:
  - `struct DevSession: Identifiable { id: Int32 (= rootPID), rootPID: Int32, memberPIDs: [Int32] (루트 먼저, BFS), command: String, ignoreKey: String, toolName: String, projectName: String, projectPath: String?, ports: [Int], uptime: TimeInterval, isStale: Bool }`
  - `struct SessionGrouper { init(classifier:projectNames:); func sessions(from: [RawProcess]) -> [DevSession] }` (켜진 시간 긴 순)
  - `SessionMatcher.fresh(_ session: DevSession, in current: [DevSession]) -> DevSession?`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter SessionGrouperTests`
Expected: 컴파일 실패

- [ ] **Step 3: DevSession + SessionMatcher 구현**

```swift
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
```

- [ ] **Step 4: SessionGrouper 구현**

```swift
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
            let root = climb(from: p, byPID: byPID).pid
            if !roots.contains(root) { roots.append(root) }
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
```

- [ ] **Step 5: 통과 확인**

Run: `swift test --filter SessionGrouperTests`
Expected: 7 tests passed

- [ ] **Step 6: 전체 테스트**

Run: `swift test`
Expected: 전체 통과

- [ ] **Step 7: Commit**

```bash
git add Sources/BackgroundCheckCore Tests/BackgroundCheckCoreTests/SessionGrouperTests.swift
git commit -m "feat(core): group processes into dev sessions"
```

---

### Task 7: ProcessKiller + LibProc + LiveSignaler

**Files:**
- Create: `Sources/BackgroundCheckCore/ProcessKiller.swift`
- Create: `Sources/BackgroundCheckCore/LibProc.swift`
- Test: `Tests/BackgroundCheckCoreTests/ProcessKillerTests.swift`

**Interfaces:**
- Produces:
  - `protocol Signaler: Sendable { func send(_ signal: Int32, to pid: Int32) -> Int32 /* 0 또는 errno */; func isAlive(_ pid: Int32) -> Bool }`
  - `struct KillResult: Equatable { failures: [Int32: Int32]; survivors: [Int32]; var succeeded: Bool }`
  - `struct ProcessKiller { init(signaler: any Signaler, grace: TimeInterval = 3, pollInterval: TimeInterval = 0.25, sleep: @escaping @Sendable (TimeInterval) -> Void = Thread.sleep); func terminate(pids: [Int32]) -> KillResult }`
  - `enum LibProc { static func path(_ pid: Int32) -> String?; static func cwd(_ pid: Int32) -> String?; static func status(_ pid: Int32) -> UInt32? }`
  - `struct LiveSignaler: Signaler` (좀비는 죽은 것으로 취급)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter ProcessKillerTests`
Expected: 컴파일 실패

- [ ] **Step 3: ProcessKiller 구현**

```swift
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
```

- [ ] **Step 4: LibProc + LiveSignaler 구현**

```swift
import Darwin
import Foundation

public enum LibProc {
    public static func path(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    public static func cwd(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }

    public static func status(_ pid: Int32) -> UInt32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_status
    }
}

public struct LiveSignaler: Signaler {
    public init() {}

    public func send(_ signal: Int32, to pid: Int32) -> Int32 {
        kill(pid, signal) == 0 ? 0 : errno
    }

    /// 좀비(부모가 아직 거두지 않은 종료 프로세스)는 죽은 것으로 본다.
    public func isAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) != 0 && errno == ESRCH { return false }
        if let status = LibProc.status(pid), status == UInt32(SZOMB) { return false }
        return true
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift test --filter ProcessKillerTests`
Expected: 4 tests passed

- [ ] **Step 6: Commit**

```bash
git add Sources/BackgroundCheckCore Tests/BackgroundCheckCoreTests/ProcessKillerTests.swift
git commit -m "feat(core): process tree killer and libproc wrappers"
```

---

### Task 8: LiveSystemProbe + SessionScanner + 통합 테스트

**Files:**
- Create: `Sources/BackgroundCheckCore/SystemProbe.swift`
- Test: `Tests/BackgroundCheckCoreTests/LiveIntegrationTests.swift`

**Interfaces:**
- Consumes: `PsParser`, `LsofParser`, `LibProc`, `RawProcess`, `ScanSettings`, `DevProcessClassifier`, `SessionGrouper`, `ProjectNameResolver`, `ProcessKiller`, `LiveSignaler`
- Produces:
  - `struct CommandRunner { func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String)? }`
  - `enum ProbeError: Error { case psFailed }`
  - `protocol SystemProbe: Sendable { func snapshot() throws -> [RawProcess] }`, `struct LiveSystemProbe: SystemProbe { init(uid: UInt32 = getuid(), runner: CommandRunner = CommandRunner()) }`
  - `struct SessionScanner { init(probe: any SystemProbe, settings: ScanSettings, home: String = NSHomeDirectory()); func scan() throws -> [DevSession] }`

- [ ] **Step 1: 실패하는 통합 테스트 작성**

```swift
import Foundation
import Testing
@testable import BackgroundCheckCore

private let nodePath = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
    .first { FileManager.default.isExecutableFile(atPath: $0) }

@Suite(.serialized) struct LiveIntegrationTests {
    @Test(.enabled(if: nodePath != nil, "node가 설치되어 있어야 함"))
    func detectsAndKillsNodeServerTree() throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("bgc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let dir = raw.resolvingSymlinksInPath()
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
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter LiveIntegrationTests`
Expected: 컴파일 실패 (`cannot find 'SessionScanner'`)

- [ ] **Step 3: 구현** — `SystemProbe.swift`

```swift
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
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter LiveIntegrationTests`
Expected: 2 tests passed

- [ ] **Step 5: Commit**

```bash
git add Sources/BackgroundCheckCore/SystemProbe.swift Tests/BackgroundCheckCoreTests/LiveIntegrationTests.swift
git commit -m "feat(core): live system probe, scanner, integration tests"
```

---

### Task 9: 표시용 포매터

**Files:**
- Create: `Sources/BackgroundCheckCore/Formatting.swift`
- Test: `Tests/BackgroundCheckCoreTests/FormattingTests.swift`

**Interfaces:**
- Produces: `UptimeFormatter.format(_ t: TimeInterval) -> String`, `PathDisplay.abbreviate(_ path: String, home: String) -> String`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
@testable import BackgroundCheckCore

@Suite struct FormattingTests {
    @Test(arguments: [
        (30.0, "<1m"), (12 * 60.0, "12m"), (2 * 3600 + 14 * 60.0, "2h 14m"),
        (27 * 3600.0, "1d 3h"), (3600.0, "1h 0m"),
    ])
    func uptime(seconds: Double, expected: String) {
        #expect(UptimeFormatter.format(seconds) == expected)
    }

    @Test func abbreviatesHome() {
        #expect(PathDisplay.abbreviate("/Users/me/Devguru/site", home: "/Users/me") == "~/Devguru/site")
        #expect(PathDisplay.abbreviate("/Users/me", home: "/Users/me") == "~")
        #expect(PathDisplay.abbreviate("/Users/meow/x", home: "/Users/me") == "/Users/meow/x")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter FormattingTests`
Expected: 컴파일 실패

- [ ] **Step 3: 구현**

```swift
import Foundation

public enum UptimeFormatter {
    public static func format(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        guard minutes >= 1 else { return "<1m" }
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

public enum PathDisplay {
    public static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter FormattingTests`
Expected: 6 test cases passed

- [ ] **Step 5: Commit**

```bash
git add Sources/BackgroundCheckCore/Formatting.swift Tests/BackgroundCheckCoreTests/FormattingTests.swift
git commit -m "feat(core): uptime and path display formatting"
```

---

### Task 10: 앱 상태 (AppModel, SettingsStore) + 실행 타깃

**Files:**
- Modify: `Package.swift` (실행 타깃 추가)
- Create: `Sources/BackgroundCheck/SettingsStore.swift`
- Create: `Sources/BackgroundCheck/AppModel.swift`
- Create: `Sources/BackgroundCheck/BackgroundCheckApp.swift` (임시 최소 본문, Task 11에서 교체)

**Interfaces:**
- Consumes: `ScanSettings`, `SessionScanner`, `LiveSystemProbe`, `SessionMatcher`, `ProcessKiller`, `LiveSignaler`, `DevSession`, `KillResult`
- Produces (`@MainActor @Observable final class AppModel`):
  - `private(set) var sessions: [DevSession]`, `private(set) var scanFailed: Bool`, `private(set) var terminating: Set<Int32>`, `private(set) var terminateErrors: [Int32: String]`
  - `var settings: ScanSettings` (변경 시 저장 + 재스캔), `var isPanelOpen: Bool` (변경 시 스캔 루프 재시작)
  - `var staleCount: Int`, `func scan() async`, `func terminate(_ session: DevSession) async`, `func terminateAll() async`, `func ignore(_ session: DevSession)`

- [ ] **Step 1: Package.swift에 실행 타깃 추가**

`targets` 배열을 다음으로 교체:

```swift
    targets: [
        .target(name: "BackgroundCheckCore"),
        .executableTarget(name: "BackgroundCheck", dependencies: ["BackgroundCheckCore"]),
        .testTarget(name: "BackgroundCheckCoreTests", dependencies: ["BackgroundCheckCore"]),
    ],
```

- [ ] **Step 2: SettingsStore**

```swift
import BackgroundCheckCore
import Foundation

enum SettingsStore {
    private static let key = "scanSettings.v1"

    static func load() -> ScanSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ScanSettings.self, from: data) else {
            return .defaults(home: NSHomeDirectory())
        }
        return settings
    }

    static func save(_ settings: ScanSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
```

- [ ] **Step 3: AppModel**

```swift
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
```

- [ ] **Step 4: 임시 앱 진입점** — `BackgroundCheckApp.swift`

```swift
import SwiftUI

@main
struct BackgroundCheckApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Background Check", systemImage: "circle.inset.filled") {
            Text("세션 \(model.sessions.count)개")
        }
    }
}
```

- [ ] **Step 5: 빌드 확인**

Run: `swift build && swift test`
Expected: 빌드 성공, 전체 테스트 통과

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/BackgroundCheck
git commit -m "feat(app): app model with scan loop and terminate actions"
```

---

### Task 11: 메뉴바 UI

**Files:**
- Modify: `Sources/BackgroundCheck/BackgroundCheckApp.swift` (전체 교체)
- Create: `Sources/BackgroundCheck/MenuBarLabel.swift`
- Create: `Sources/BackgroundCheck/WindowKeyObserver.swift`
- Create: `Sources/BackgroundCheck/MenuPanelView.swift`
- Create: `Sources/BackgroundCheck/SessionRowView.swift`
- Create: `Sources/BackgroundCheck/SettingsView.swift` (임시 최소 본문, Task 12에서 교체)

**Interfaces:**
- Consumes: `AppModel` (Task 10), `UptimeFormatter`, `PathDisplay` (Task 9), `DevSession`
- Produces: `MenuPanelView(model:)`, `SessionRowView(session:isExpanded:isTerminating:error:onToggle:onTerminate:onIgnore:)`, `MenuBarLabel(count:hasStale:)`, `WindowKeyObserver(onChange:)`, `SettingsView(model:)`

- [ ] **Step 1: BackgroundCheckApp.swift 교체**

```swift
import SwiftUI

@main
struct BackgroundCheckApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(model: model)
        } label: {
            MenuBarLabel(count: model.sessions.count, hasStale: model.staleCount > 0)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
```

- [ ] **Step 2: MenuBarLabel**

```swift
import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let count: Int
    let hasStale: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: Self.icon(count: count, hasStale: hasStale))
            if count > 0 { Text("\(count)") }
        }
    }

    /// 0개: 점선 원(흐림), 1개 이상: 채운 원, 오래된 세션이 있으면 주황색
    static func icon(count: Int, hasStale: Bool) -> NSImage {
        let name = count == 0 ? "circle.dashed" : "circle.inset.filled"
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "Background Check") ?? NSImage()
        guard hasStale,
              let colored = base.withSymbolConfiguration(.init(paletteColors: [.systemOrange])) else {
            base.isTemplate = true
            return base
        }
        colored.isTemplate = false
        return colored
    }
}
```

- [ ] **Step 3: WindowKeyObserver** — 패널 창이 key가 되면 열림, 해제되면 닫힘

```swift
import AppKit
import SwiftUI

struct WindowKeyObserver: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView(onChange: onChange) }
    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        private let onChange: @MainActor (Bool) -> Void
        private var tokens: [NSObjectProtocol] = []

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange(true) }
            })
            tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange(false) }
            })
            if window.isKeyWindow { onChange(true) }
        }
    }
}
```

- [ ] **Step 4: SessionRowView**

```swift
import AppKit
import BackgroundCheckCore
import SwiftUI

struct SessionRowView: View {
    let session: DevSession
    let isExpanded: Bool
    let isTerminating: Bool
    let error: String?
    let onToggle: () -> Void
    let onTerminate: () -> Void
    let onIgnore: () -> Void

    private let home = NSHomeDirectory()
    private var accent: Color { session.isStale ? .orange : .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(accent).frame(width: 8, height: 8).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.projectName).fontWeight(.semibold).lineLimit(1)
                        Text(session.toolName).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        if !session.ports.isEmpty {
                            Text(session.ports.map { ":\($0)" }.joined(separator: " "))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(session.projectPath.map { PathDisplay.abbreviate($0, home: home) } ?? "—")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(UptimeFormatter.format(session.uptime))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(session.isStale ? Color.orange : Color.secondary)
                    }
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                if isTerminating {
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                } else {
                    Button(action: onTerminate) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("종료")
                }
            }
            if isExpanded { details }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
            Text("PID " + session.memberPIDs.map(String.init).joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if let port = session.ports.first, let url = URL(string: "http://localhost:\(port)") {
                    Button("브라우저에서 열기") { NSWorkspace.shared.open(url) }
                }
                if let path = session.projectPath {
                    Button("Finder에서 보기") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                }
                Spacer()
                Button("항상 무시", action: onIgnore)
            }
            .controlSize(.small)
        }
        .padding(.leading, 16)
    }
}
```

- [ ] **Step 5: MenuPanelView**

```swift
import AppKit
import BackgroundCheckCore
import SwiftUI

struct MenuPanelView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var expanded: Int32?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.sessions.isEmpty {
                Text("켜진 dev 서버 없음 ✓")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.sessions) { session in
                            SessionRowView(
                                session: session,
                                isExpanded: expanded == session.id,
                                isTerminating: model.terminating.contains(session.id),
                                error: model.terminateErrors[session.id],
                                onToggle: { expanded = expanded == session.id ? nil : session.id },
                                onTerminate: { Task { await model.terminate(session) } },
                                onIgnore: { model.ignore(session) })
                            Divider().padding(.leading, 28)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .background(WindowKeyObserver { model.isPanelOpen = $0 })
    }

    private var header: some View {
        HStack {
            Text("Background Check").font(.headline)
            Spacer()
            if model.scanFailed {
                Text("스캔 실패").font(.caption).foregroundStyle(.red)
            }
            Button { Task { await model.scan() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("새로고침")
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button("모두 종료", action: confirmTerminateAll)
                .disabled(model.sessions.isEmpty)
            Spacer()
            Button("설정…") {
                NSApp.activate()
                openSettings()
            }
            Button("종료") { NSApp.terminate(nil) }
        }
        .padding(12)
    }

    private func confirmTerminateAll() {
        let alert = NSAlert()
        alert.messageText = "dev 서버 \(model.sessions.count)개를 모두 종료할까요?"
        alert.addButton(withTitle: "모두 종료")
        alert.addButton(withTitle: "취소")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await model.terminateAll() }
        }
    }
}
```

- [ ] **Step 6: 임시 SettingsView**

```swift
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    var body: some View { Text("설정").padding() }
}
```

- [ ] **Step 7: 빌드 후 직접 실행해서 확인**

Run: `swift build && (.build/debug/BackgroundCheck &) && sleep 2`
Expected:
- 메뉴바에 아이콘이 뜨고, 켜진 세션이 있으면 개수가 보인다
- 클릭하면 패널이 열리고, 이 머신의 Claude·VS Code·MCP 프로세스는 목록에 없다
- 다른 터미널에서 `cd $(mktemp -d ~/Devguru/bgc-tmp-XXXX) && python3 -m http.server 0` 실행 → 패널을 열면 3초 안에 목록에 뜬다 → ✕ → 사라진다 → `rmdir`로 임시 폴더 삭제
- 메뉴바 아이콘 옆 숫자가 안 보이면 `MenuBarLabel`을 `Text("\(Image(nsImage: ...)) \(count)")` 형태로 바꿔 다시 확인
- 확인 후 `pkill -x BackgroundCheck`

- [ ] **Step 8: Commit**

```bash
git add Sources/BackgroundCheck
git commit -m "feat(app): menu bar panel with session rows"
```

---

### Task 12: 설정 창

**Files:**
- Modify: `Sources/BackgroundCheck/SettingsView.swift` (전체 교체)

**Interfaces:**
- Consumes: `AppModel.settings` (Task 10), `PathDisplay` (Task 9)

- [ ] **Step 1: SettingsView 구현**

```swift
import AppKit
import BackgroundCheckCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("프로젝트 루트") {
                ForEach(model.settings.projectRoots, id: \.self) { root in
                    HStack {
                        if !FileManager.default.fileExists(atPath: (root as NSString).expandingTildeInPath) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("폴더가 없습니다")
                        }
                        Text(PathDisplay.abbreviate(root, home: NSHomeDirectory()))
                        Spacer()
                        Button { model.settings.projectRoots.removeAll { $0 == root } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("폴더 추가…", action: addRoot)
            }

            Section("오래됨 기준") {
                Stepper(value: $model.settings.staleHours, in: 1...72, step: 1) {
                    Text("\(Int(model.settings.staleHours))시간 이상 켜져 있으면 주황색으로 표시")
                }
            }

            Section("무시 목록") {
                if model.settings.ignorePatterns.isEmpty {
                    Text("없음").foregroundStyle(.secondary)
                }
                ForEach(model.settings.ignorePatterns, id: \.self) { pattern in
                    HStack {
                        Text(pattern).font(.caption.monospaced()).lineLimit(2)
                        Spacer()
                        Button { model.settings.ignorePatterns.removeAll { $0 == pattern } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              !model.settings.projectRoots.contains(url.path) else { return }
        model.settings.projectRoots.append(url.path)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let enabled = SMAppService.mainApp.status == .enabled
        guard on != enabled else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "설정 실패: \(error.localizedDescription) (설치된 .app에서만 동작합니다)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
```

- [ ] **Step 2: 빌드 후 확인**

Run: `swift build && (.build/debug/BackgroundCheck &) && sleep 2`
Expected: 패널의 "설정…"을 누르면 설정 창이 앞으로 뜬다. 루트 추가/삭제, 기준 시간 변경, 무시 목록 삭제가 즉시 목록에 반영된다(앱을 재시작해도 유지). 로그인 항목은 `swift build` 바이너리에서는 오류 문구가 나오는 게 정상이고, Task 13에서 설치한 앱으로 확인한다. 확인 후 `pkill -x BackgroundCheck`.

- [ ] **Step 3: Commit**

```bash
git add Sources/BackgroundCheck/SettingsView.swift
git commit -m "feat(app): settings window"
```

---

### Task 13: .app 패키징, 설치, 최종 확인

**Files:**
- Create: `scripts/build-app.sh`
- Create: `scripts/install.sh`
- Modify: `.gitignore` (`build/` 추가)

- [ ] **Step 1: build-app.sh**

```bash
#!/usr/bin/env bash
# release 빌드 후 "Background Check.app" 번들을 build/에 조립하고 ad-hoc 서명한다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product BackgroundCheck

APP="build/Background Check.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BackgroundCheck "$APP/Contents/MacOS/BackgroundCheck"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.memory.backgroundcheck</string>
    <key>CFBundleName</key><string>Background Check</string>
    <key>CFBundleDisplayName</key><string>Background Check</string>
    <key>CFBundleExecutable</key><string>BackgroundCheck</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "$APP"
```

- [ ] **Step 2: install.sh**

```bash
#!/usr/bin/env bash
# 빌드 → 실행 중인 앱 종료 → ~/Applications에 설치 → 실행
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
pkill -x BackgroundCheck || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Background Check.app"
cp -R "build/Background Check.app" "$HOME/Applications/"
open "$HOME/Applications/Background Check.app"
```

- [ ] **Step 3: 실행 권한 + .gitignore**

Run: `chmod +x scripts/*.sh && printf 'build/\n' >> .gitignore`

- [ ] **Step 4: 설치**

Run: `scripts/install.sh`
Expected: 빌드 성공, 메뉴바에 아이콘 표시, Dock 아이콘 없음

- [ ] **Step 5: 전체 테스트**

Run: `swift test`
Expected: 전체 통과

- [ ] **Step 6: 최종 수동 확인 (스펙 성공 기준)**

1. 실제 astro 프로젝트(`~/Devguru` 아래)에서 `npm run dev` → 패널에 `프로젝트명 astro dev :4321` 한 줄로 표시(npm/node/esbuild가 하나로 묶임)
2. ✕ → 패널에서 사라짐 → `lsof -nP -iTCP:4321 -sTCP:LISTEN` 결과 없음, `ps`에 해당 npm/node/esbuild 없음
3. 패널에 Claude/VS Code/Discord helper, MCP 서버, `claude`, 셸이 없음
4. 설정 → 로그인 시 자동 실행 켜기 → 시스템 설정 > 일반 > 로그인 항목에 Background Check 표시
5. 설정에서 오래됨 기준을 1시간으로 바꾸면, 1시간 넘은 세션이 주황색이 되고 메뉴바 아이콘도 주황색으로 바뀜

- [ ] **Step 7: Commit**

```bash
git add scripts .gitignore
git commit -m "build: app bundle packaging and install script"
```
