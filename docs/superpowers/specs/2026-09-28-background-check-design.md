# Background Check — 설계 문서

- 작성일: 2026-09-28
- 상태: 사용자 리뷰 대기

## 1. 목적

깜빡하고 켜둔 개발용 백그라운드 프로세스(`astro dev`, vite, next, node 서버 등)가 며칠씩 떠 있는 일을 막는다.
macOS 메뉴바에서 지금 켜진 dev 서버를 한눈에 보고, 클릭 한 번으로 종료한다.

### 성공 기준

- 터미널/Claude Code 등에서 띄운 dev 서버가 패널을 열면 즉시, 닫혀 있어도 15초 안에 목록(배지)에 반영된다.
- Claude·VS Code·Discord helper, npx로 뜬 MCP 서버 등 **앱이 띄운 node 프로세스는 목록에 나오지 않는다.**
- **Claude Code(`claude`), 셸, 에디터 자체는 절대 목록에 나오지 않고 종료 대상에도 포함되지 않는다.**
- ✕ 한 번으로 `npm run dev`가 만든 프로세스 트리 전체(npm → node → esbuild 등)가 정리되고, 포트가 해제된다.
- 메뉴바 아이콘만 봐도 몇 개가 켜져 있는지, 오래된 게 있는지 알 수 있다.

### 범위 밖 (YAGNI)

- 자동 종료, macOS 알림
- 다른 사용자/root 소유 프로세스
- Docker 컨테이너, UDP 포트
- CPU/메모리 사용량 표시

## 2. 형태

네이티브 SwiftUI 메뉴바 앱(`MenuBarExtra`, window 스타일). Dock 아이콘 없음(`LSUIElement`).
SwiftPM으로 빌드하고 스크립트로 `.app` 번들을 만들어 `~/Applications`에 설치한다. 최소 macOS 14.

## 3. 감지 로직

### 3.1 수집 (`SystemProbe`)

한 번의 스캔에서 다음을 모아 `RawProcess` 목록을 만든다.

| 정보 | 출처 |
|---|---|
| pid, ppid, uid, 경과 시간, 전체 명령어 | `ps -axww -o pid=,ppid=,uid=,etime=,command=` |
| 실행 파일 경로 | `proc_pidpath` (libproc) |
| 작업 폴더(cwd) | `proc_pidinfo(PROC_PIDVNODEPATHINFO)` (libproc) |
| LISTEN 중인 TCP 포트 | `lsof -nP -iTCP -sTCP:LISTEN -F pn` |

현재 사용자(uid) 소유 프로세스만 대상.

### 3.2 분류 (`DevProcessClassifier`)

프로세스가 **후보(match)** 가 되려면:

**dev 바이너리**: 실행 파일 basename이 아래 목록 중 하나인 프로세스.

- 런타임: `node, bun, deno, python, python3, python3.*, Python, ruby, php, java, go, air, uvicorn, gunicorn, hugo, caddy`
- 패키지 매니저: `npm, npx, pnpm, yarn, bunx`

에디터(vim 등), git, 셸, Claude Code 같은 다른 바이너리는 cwd가 프로젝트 안이어도 후보가 되지 않는다.

- **포함**: dev 바이너리이면서 다음 중 하나 이상에 해당
  - (a) LISTEN 포트가 1개 이상
  - (b) cwd가 프로젝트 루트 중 하나의 하위 (기본 `~/Devguru`, 설정에서 여러 개)
- **제외** (하나라도 해당하면 포함 조건을 무시)
  - 실행 파일 경로가 `/System/` 또는 `/usr/libexec/`로 시작
  - 실행 파일 basename이 dev 바이너리가 **아니면서** 경로에 `.app/Contents/`가 들어감 (Claude/VS Code/Discord helper, Adobe 등)
    - Xcode의 python3(`/Applications/Xcode.app/.../python3`)은 dev 바이너리라서 이 규칙에 걸리지 않음
  - 명령어에서 실행 파일 뒤 첫 경로 인자(스크립트 경로)에 `.app/Contents/`가 들어가거나, 그 인자가 `~/.npm/_npx/`, `~/Library/`, `~/.vscode/`, `~/.cursor/`로 시작 (npx로 뜬 MCP 서버, 에디터 확장 등)
  - 무시 목록 패턴과 일치 (명령어 부분 문자열 매칭)
    - 기본값: `@anthropic-ai/claude-code`, `claude/versions/`, `codex` (npm으로 설치한 Claude Code/Codex 보호)

### 3.3 세션 묶기 (`SessionGrouper`)

`npm run dev` 한 번이 여러 프로세스를 만드므로, 트리 단위로 묶어 **세션** 하나로 보여준다.

1. 각 후보에서 부모를 따라 올라간다. 부모가 **경계**면 멈춘다.
   - 경계: pid 1(launchd), 다른 uid, dev 바이너리가 아닌 프로세스(셸, `claude`, 터미널 앱, tmux 등), 제외 조건에 걸린 프로세스
2. 멈춘 지점 바로 아래 프로세스가 세션 루트. 같은 루트를 가진 후보는 하나로 합친다.
3. 루트의 모든 자손이 세션 멤버.
4. 세션 표시 정보
   - 프로젝트 이름: 멤버 cwd 중 프로젝트 루트 하위인 것에서 `package.json`/`pyproject.toml`/`.git`이 있는 가장 가까운 폴더 이름. 없으면 cwd의 마지막 폴더 이름.
   - 도구 이름(`ToolNameResolver`): 멤버 명령어에서 알려진 도구 표식을 찾음
     - `astro, vite, next, nuxt, remix, wrangler, webpack, storybook, parcel, eleventy, gatsby, svelte-kit, turbo, nodemon, tsx, uvicorn, flask, manage.py runserver, http.server, rails, hugo`
     - 뒤따르는 서브커맨드(`dev`, `preview`, `serve`, `start`)가 있으면 붙임 → `astro dev`
     - 못 찾으면 루트 실행 파일 basename
   - 포트: 멤버 전체의 LISTEN 포트, 오름차순
   - 켜진 시간: 루트의 경과 시간
   - 오래됨: 켜진 시간 ≥ 기준(기본 6시간)

예: Claude Code 백그라운드 작업 `claude → zsh → npm → node(astro)`는 zsh가 경계이므로 루트는 `npm`. 부모가 죽어 고아가 된 astro(ppid 1)는 자기 자신이 루트.

### 3.4 종료 (`ProcessKiller`)

1. 세션 멤버 전체(자손 → 루트 순) 에 SIGTERM
2. 0.25초 간격으로 확인, 3초 후 남은 멤버에 SIGKILL
3. ESRCH(이미 없음)는 성공으로 취급. EPERM 등은 해당 행에 오류 표시.
4. 끝나면 즉시 재스캔

### 3.5 스캔 주기

- 패널 닫힘: 15초 (배지 갱신용, 부담 최소화)
- 패널 열림: 열 때 즉시 1회 + 3초마다
- 스캔은 백그라운드 큐에서 실행. 이전 스캔이 안 끝났으면 건너뜀.

## 4. UI

### 4.1 메뉴바 아이콘

- 세션 0개: 흐린 아이콘, 숫자 없음
- 1개 이상: 아이콘 + 개수 (`◉ 3`)
- 오래된 세션이 있으면 아이콘 주황색

### 4.2 패널

```
┌ Background Check ─────────────── ⟳ ┐
│ ● my-site        astro dev   :4321 │
│   ~/Devguru/sites/my-site   2h 14m ✕│
│ ● api-server     node        :3000 │
│   ~/Devguru/…/api-server    1d 3h  ✕│  ← 오래됨: 주황색
├────────────────────────────────────┤
│ [모두 종료]                         │
│ 설정…                     종료(Quit)│
└────────────────────────────────────┘
```

- 정렬: 켜진 시간이 긴 순
- 비어 있으면 "켜진 dev 서버 없음 ✓"
- 행 클릭 → 펼침: 전체 명령어, 멤버 pid 목록, 버튼
  - `브라우저에서 열기` (포트 있을 때, 첫 포트로 `http://localhost:PORT`)
  - `Finder에서 보기`
  - `항상 무시` (루트 명령어를 무시 목록에 추가)
- ✕: 확인 없이 바로 종료, 종료 중에는 스피너
- 모두 종료: 확인 대화상자 1회

### 4.3 설정 창

- 프로젝트 루트 폴더 목록 (추가/삭제, 기본 `~/Devguru`)
- 오래됨 기준 시간 (시간 단위, 기본 6)
- 무시 목록 (보기/삭제)
- 로그인 시 자동 실행 (`SMAppService.mainApp`)

설정은 `UserDefaults`에 저장.

## 5. 코드 구조

```
background_check/
├── Package.swift
├── Sources/
│   ├── BackgroundCheckCore/        # 순수 로직, UI 의존 없음
│   │   ├── RawProcess.swift        # 수집 결과 모델
│   │   ├── DevSession.swift        # 세션 모델
│   │   ├── Settings.swift          # 설정 값 (roots, staleHours, ignore)
│   │   ├── SystemProbe.swift       # protocol + LiveSystemProbe (ps/lsof/libproc)
│   │   ├── PsParser.swift          # ps 출력·etime 파싱
│   │   ├── LsofParser.swift        # lsof -F 출력 파싱
│   │   ├── DevProcessClassifier.swift
│   │   ├── SessionGrouper.swift
│   │   ├── ToolNameResolver.swift
│   │   ├── ProjectNameResolver.swift
│   │   └── ProcessKiller.swift     # protocol Signaler로 kill 추상화
│   └── BackgroundCheck/            # 앱
│       ├── BackgroundCheckApp.swift  # MenuBarExtra + Settings scene
│       ├── AppModel.swift            # @Observable, 스캔 타이머, 종료 액션
│       ├── MenuPanelView.swift
│       ├── SessionRowView.swift
│       └── SettingsView.swift
├── Tests/BackgroundCheckCoreTests/
│   ├── Fixtures/                   # 실제 머신에서 뜬 ps/lsof 출력 샘플
│   └── *.swift
└── scripts/
    ├── build-app.sh                # release 빌드 → .app 조립 → ad-hoc 서명
    └── install.sh                  # ~/Applications로 복사 후 실행
```

각 단위의 경계:

- `SystemProbe`는 `[RawProcess]`만 돌려준다. 분류·묶기는 모른다.
- `DevProcessClassifier`, `SessionGrouper`, 이름 해석기는 `[RawProcess]` + `Settings` → `[DevSession]`인 순수 함수. 파일 존재 확인(프로젝트 이름)은 주입 가능한 클로저로 받는다.
- `ProcessKiller`는 `Signaler` 프로토콜(`kill`, `isAlive`)에 의존해 테스트에서 가짜로 대체한다.
- 앱 타깃은 Core를 호출하고 결과를 그리기만 한다.

## 6. 오류 처리

| 상황 | 처리 |
|---|---|
| `lsof` 실패/타임아웃(2초) | 포트 없이 진행. (b) 조건으로 잡히는 세션은 계속 표시 |
| `ps` 실패 | 이전 목록 유지, 패널 상단에 "스캔 실패" 한 줄 표시 |
| cwd 읽기 EPERM | cwd = nil로 취급 |
| 스캔 도중 프로세스 종료 | 해당 항목 버림 |
| 종료 EPERM | 행에 "권한 없음" 표시, 나머지 멤버는 계속 처리 |
| 프로젝트 루트 폴더가 없음 | 무시 (설정 화면에 경고 아이콘) |

## 7. 테스트

- **단위 테스트 (Swift Testing, Core)**
  - `PsParser`: etime 형식(`MM:SS`, `HH:MM:SS`, `D-HH:MM:SS`), 공백 포함 명령어
  - `LsofParser`: `-F pn` 출력 → pid별 포트, IPv4/IPv6 중복 제거
  - `DevProcessClassifier`: 픽스처 기반. Claude/VS Code helper, `~/.npm/_npx` MCP 서버, Adobe node, cwd가 `~/Devguru`인 `claude`·`vim`은 제외. astro/vite, Xcode python3의 `http.server`는 포함
  - `SessionGrouper`: `claude → zsh → npm → node → esbuild` 트리가 npm 루트 1개 세션으로(claude·zsh는 멤버 아님), 고아 astro가 단독 세션으로, 경계 규칙
    - esbuild처럼 dev 바이너리가 아닌 자손도 루트의 자손이면 멤버로 포함
  - `ToolNameResolver`, `ProjectNameResolver`: 대표 명령어별 기대값
  - `ProcessKiller`: 가짜 Signaler로 SIGTERM→SIGKILL 순서, ESRCH 성공 처리
- **통합 테스트 (Core, 실제 시스템)**
  - 임시 폴더를 프로젝트 루트로 설정, 그 안에서 `node`로 자식 프로세스를 가진 HTTP 서버를 띄움 → `LiveSystemProbe` + 분류로 세션 1개, 올바른 포트 확인 → `ProcessKiller`로 종료 → 모든 pid 사라짐·포트 해제 확인
- **수동 확인**
  - `scripts/install.sh`로 설치 후 실제 astro 프로젝트에서 `npm run dev` → 목록 표시 → ✕ → 포트 해제 확인
  - 이 머신에 떠 있는 Claude/VS Code/MCP 프로세스가 목록에 없는지 확인
