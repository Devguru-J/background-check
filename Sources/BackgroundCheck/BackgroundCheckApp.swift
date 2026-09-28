import SwiftUI

@main
struct BackgroundCheckApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Background Check", systemImage: "circle.inset.filled") {
            Text("세션 \(model.sessions.count)개")
        }
    }
}
