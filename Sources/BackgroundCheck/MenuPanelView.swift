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
