import Testing
@testable import BackgroundCheckCore

@Suite struct LsofParserTests {
    @Test func parsesPortsPerPid() {
        let out = "p949\nf10\nn*:62686\nf15\nn*:62686\np1782\nf6\nn127.0.0.1:14440\nf7\nn[::1]:3000\nf8\nn*:*\n"
        #expect(LsofParser.parse(out) == [949: [62686], 1782: [3000, 14440]])
    }

    @Test func emptyOutput() {
        #expect(LsofParser.parse("").isEmpty)
    }
}
