import BackgroundCheckCore
import Foundation

enum SettingsStore {
    private static let key = "scanSettings.v1"

    static func load() -> ScanSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ScanSettings.self, from: data) else {
            return .defaults(home: NSHomeDirectory())
        }
        return settings
    }

    static func save(_ settings: ScanSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
