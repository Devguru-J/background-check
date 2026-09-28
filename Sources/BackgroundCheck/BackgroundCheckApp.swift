import SwiftUI

@main
struct BackgroundCheckApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView(model: model)
        } label: {
            MenuBarLabel(count: model.sessions.count, hasStale: model.staleCount > 0)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
