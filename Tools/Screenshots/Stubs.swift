import BackgroundCheckCore
import AppKit
import Observation
import SwiftUI

/// 스크린샷용 가짜 모델: 실제 AppModel과 같은 API, 예시 데이터
@MainActor @Observable
final class AppModel {
    var sessions: [DevSession]
    var scanFailed = false
    var terminating: Set<Int32> = []
    var terminateErrors: [Int32: String] = [:]
    var settings: ScanSettings
    var isPanelOpen = false
    var staleCount: Int { sessions.filter(\.isStale).count }

    init(sessions: [DevSession], settings: ScanSettings) {
        self.sessions = sessions
        self.settings = settings
    }

    func scan() async {}
    func terminate(_ session: DevSession) async {}
    func terminateAll() async {}
    func ignore(_ session: DevSession) {}
}

/// 스크린샷에서는 NSVisualEffectView가 그려지지 않으므로 메뉴 배경색으로 대신한다
struct MenuMaterialBackground: View {
    var body: some View { Color(red: 0.16, green: 0.16, blue: 0.17).opacity(0.96) }
}

struct WindowKeyObserver: View {
    let onChange: @MainActor (Bool) -> Void
    var body: some View { Color.clear }
}
