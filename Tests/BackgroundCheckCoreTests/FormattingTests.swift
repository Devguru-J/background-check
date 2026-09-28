import Testing
@testable import BackgroundCheckCore

@Suite struct FormattingTests {
    static let uptimeCases: [(Double, String)] = [
        (30, "<1m"), (720, "12m"), (8040, "2h 14m"), (97200, "1d 3h"), (3600, "1h 0m"),
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
