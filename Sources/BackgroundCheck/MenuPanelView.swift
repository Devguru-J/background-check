import AppKit
import BackgroundCheckCore
import SwiftUI

struct MenuPanelView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var expanded: Int32?
    /// ScrollView는 기본 높이가 없어 MenuBarExtra 창에서 0으로 접히므로, 목록 높이를 재서 직접 지정한다
    @State private var listHeight: CGFloat = 0
    @State private var panelHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            if model.sessions.isEmpty { emptyState } else { list }
            Divider()
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
            footer
                .padding(.horizontal, 5)
                .padding(.bottom, 6)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(PanelHeightKey.self) { panelHeight = $0 }
        .background(WindowHeightFitter(height: panelHeight))
        .background(MenuMaterialBackground())
        .background(WindowKeyObserver { model.isPanelOpen = $0 })
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("개발 서버")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if !model.sessions.isEmpty {
                Text(verbatim: "\(model.sessions.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if model.scanFailed {
                Text("스캔 실패").font(.caption).foregroundStyle(.red)
            }
            Button { Task { await model.scan() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("새로고침")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.green)
            Text("켜진 개발 서버가 없어요")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(model.sessions) { session in
                    SessionRowView(
                        session: session,
                        isExpanded: expanded == session.id,
                        isTerminating: model.terminating.contains(session.id),
                        error: model.terminateErrors[session.id],
                        onToggle: { expanded = expanded == session.id ? nil : session.id },
                        onTerminate: { Task { await model.terminate(session) } },
                        onIgnore: { model.ignore(session) })
                }
            }
            .padding(.horizontal, 5)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
            })
        }
        .frame(height: min(max(listHeight, 1), 420))
        .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button(action: confirmTerminateAll) { MenuItemLabel("모두 종료") }
                .disabled(model.sessions.isEmpty)
            Button {
                NSApp.activate()
                openSettings()
            } label: {
                MenuItemLabel("설정…", shortcut: "⌘,")
            }
            .keyboardShortcut(",")
            Button { NSApp.terminate(nil) } label: {
                MenuItemLabel("Background Check 종료", shortcut: "⌘Q")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(MenuItemButtonStyle())
    }

    private func confirmTerminateAll() {
        let alert = NSAlert()
        alert.messageText = "개발 서버 \(model.sessions.count)개를 모두 종료할까요?"
        alert.addButton(withTitle: "모두 종료")
        alert.addButton(withTitle: "취소")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await model.terminateAll() }
        }
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
