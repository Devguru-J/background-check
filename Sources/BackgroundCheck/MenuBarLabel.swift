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
