import AppKit
import SwiftUI

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
