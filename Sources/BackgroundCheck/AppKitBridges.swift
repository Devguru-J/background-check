import AppKit
import SwiftUI

/// 시스템 메뉴와 같은 배경. 기본 창 배경은 투명도가 높아 뒤 창 색이 비친다.
struct MenuMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 패널 창이 key가 되면 열림, key를 잃으면 닫힘으로 알린다.
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

/// MenuBarExtra 창은 처음 잡힌 높이를 유지해서, 내용이 줄면 내용이 창 가운데 떠 있고 위아래로 빈 창 배경이 보인다.
/// 잰 내용 높이에 맞춰 창 높이를 직접 맞춘다. 윗변(메뉴 막대 쪽)은 고정한다.
struct WindowHeightFitter: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let height = height
        // 첫 레이아웃 때는 아직 창에 붙기 전이라 다음 런루프에서 맞춘다
        DispatchQueue.main.async {
            guard height > 0, let window = nsView.window else { return }
            let current = window.frame
            let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: current.width, height: height)))
            guard abs(target.height - current.height) > 0.5 else { return }
            window.setFrame(NSRect(x: current.minX, y: current.maxY - target.height, width: current.width, height: target.height), display: true)
        }
    }
}
