import Testing
@testable import BackgroundCheckCore

@Suite struct FormattingTests {
    static let uptimeCases: [(Double, String)] = [
        (30, "방금"), (720, "12분"), (8040, "2시간 14분"), (97200, "1일 3시간"), (3600, "1시간"), (86400, "1일"),
    ]

    @Test(arguments: uptimeCases)
    func uptime(seconds: Double, expected: String) {
        #expect(UptimeFormatter.format(seconds) == expected)
    }

    @Test func abbreviatesHome() {
        #expect(PathDisplay.abbreviate("/Users/me/Devguru/site", home: "/Users/me") == "~/Devguru/site")
        #expect(PathDisplay.abbreviate("/Users/me", home: "/Users/me") == "~")
        #expect(PathDisplay.abbreviate("/Users/meow/x", home: "/Users/me") == "/Users/meow/x")
    }
}
