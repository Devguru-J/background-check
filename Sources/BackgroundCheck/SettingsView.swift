import AppKit
import BackgroundCheckCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private static let staleOptions: [Double] = [1, 3, 6, 12, 24, 48]
    private let home = NSHomeDirectory()

    var body: some View {
        Form {
            Section {
                ForEach(model.settings.projectRoots, id: \.self) { root in
                    RemovableRow(onRemove: { model.settings.projectRoots.removeAll { $0 == root } }) {
                        Label {
                            Text(PathDisplay.abbreviate(root, home: home))
                        } icon: {
                            Image(systemName: rootExists(root) ? "folder" : "exclamationmark.triangle.fill")
                                .foregroundStyle(rootExists(root) ? Color.accentColor : Color.orange)
                        }
                        .help(rootExists(root) ? root : "폴더가 없습니다")
                    }
                }
                Button(action: addRoot) {
                    Label("폴더 추가…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
            } header: {
                Text("프로젝트 폴더")
            } footer: {
                SectionFooter("이 폴더 안에서 실행된 node · python · bun 같은 프로세스는 포트를 열지 않아도 목록에 나와요. 포트를 연 개발 서버는 어느 폴더에 있든 나옵니다.")
            }

            Section {
                Picker("주황색으로 표시", selection: $model.settings.staleHours) {
                    ForEach(Self.staleOptions, id: \.self) { hours in
                        Text("\(Int(hours))시간 이상").tag(hours)
                    }
                    if !Self.staleOptions.contains(model.settings.staleHours) {
                        Text("\(Int(model.settings.staleHours))시간 이상").tag(model.settings.staleHours)
                    }
                }
            } header: {
                Text("오래 켜진 서버")
            } footer: {
                SectionFooter("기준을 넘긴 서버가 있으면 메뉴바 아이콘도 주황색으로 바뀌어요.")
            }

            Section {
                if model.settings.ignorePatterns.isEmpty {
                    Text("무시한 항목이 없어요").foregroundStyle(.secondary)
                }
                ForEach(model.settings.ignorePatterns, id: \.self) { pattern in
                    RemovableRow(onRemove: { model.settings.ignorePatterns.removeAll { $0 == pattern } }) {
                        Text(pattern)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(pattern)
                    }
                }
            } header: {
                Text("무시 목록")
            } footer: {
                SectionFooter("패널에서 항목을 펼치고 '항상 무시'를 누르면 여기에 추가돼요. 명령어에 이 문자열이 들어간 프로세스는 숨겨집니다.")
            }

            Section {
                Toggle("로그인 시 자동으로 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("일반")
            } footer: {
                SectionFooter("Claude Code, 셸, 앱 헬퍼, MCP 서버는 설정과 상관없이 목록에 나오지 않고 종료되지도 않아요.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func rootExists(_ root: String) -> Bool {
        FileManager.default.fileExists(atPath: (root as NSString).expandingTildeInPath)
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "추가"
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
            loginError = "설정하지 못했어요: \(error.localizedDescription) (~/Applications에 설치된 앱에서만 동작해요)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// 마우스를 올리면 오른쪽에 삭제 버튼이 나타나는 행
private struct RemovableRow<Content: View>: View {
    let onRemove: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovering = false

    var body: some View {
        HStack {
            content
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .help("삭제")
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct SectionFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
