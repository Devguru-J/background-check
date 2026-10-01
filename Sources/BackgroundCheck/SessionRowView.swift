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

    @State private var isHovering = false
    private let home = NSHomeDirectory()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Circle()
                    .fill(session.isStale ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(session.projectName).fontWeight(.medium).lineLimit(1)
                        ForEach(session.ports.prefix(2), id: \.self) { PortBadge(port: $0) }
                    }
                    subtitle
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 8)
                trailing.frame(width: 18)
            }
            if isExpanded { details }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovering || isExpanded ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onToggle)
    }

    private var subtitle: some View {
        HStack(spacing: 0) {
            Text(session.toolName)
            Text(" · ")
            Text(UptimeFormatter.format(session.uptime))
                .foregroundStyle(session.isStale ? Color.orange : Color.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder private var trailing: some View {
        if isTerminating {
            ProgressView().controlSize(.small)
        } else if isHovering {
            Button(action: onTerminate) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("종료")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.projectPath.map { PathDisplay.abbreviate($0, home: home) } ?? "경로 알 수 없음")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(session.command)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                if let port = session.ports.first, let url = URL(string: "http://localhost:\(port)") {
                    Button("브라우저에서 열기") { NSWorkspace.shared.open(url) }
                }
                if let path = session.projectPath {
                    Button("Finder에서 보기") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
                }
                Spacer()
                Button("항상 무시", action: onIgnore)
            }
            .buttonStyle(InlineActionButtonStyle())
            .padding(.top, 3)
        }
        .padding(.leading, 16)
    }
}
