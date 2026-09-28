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
