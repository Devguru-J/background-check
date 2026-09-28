import Foundation

public enum UptimeFormatter {
    public static func format(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        guard minutes >= 1 else { return "<1m" }
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

public enum PathDisplay {
    public static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
