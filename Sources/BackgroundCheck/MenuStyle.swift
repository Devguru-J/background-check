import SwiftUI

/// 메뉴 항목처럼 마우스를 올리면 둥근 하이라이트가 생기는 버튼
struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuItemBody(configuration: configuration)
    }

    private struct MenuItemBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovering && isEnabled ? (configuration.isPressed ? 0.15 : 0.08) : 0)))
                .onHover { isHovering = $0 }
        }
    }
}

struct MenuItemLabel: View {
    let title: String
    var shortcut: String?

    init(_ title: String, shortcut: String? = nil) {
        self.title = title
        self.shortcut = shortcut
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let shortcut {
                Text(shortcut).foregroundStyle(.tertiary)
            }
        }
    }
}

/// 펼친 행 안의 작은 텍스트 버튼
struct InlineActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct PortBadge: View {
    let port: Int

    var body: some View {
        Text(verbatim: ":\(port)")
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}
