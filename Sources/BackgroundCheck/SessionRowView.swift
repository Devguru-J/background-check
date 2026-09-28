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
