import Testing
@testable import BackgroundCheckCore

@Suite struct PsParserTests {
    @Test func elapsedFormats() {
        #expect(PsParser.parseElapsed("00:05") == 5)
        #expect(PsParser.parseElapsed("12:34") == 754)
        #expect(PsParser.parseElapsed("01:00:00") == 3600)
        #expect(PsParser.parseElapsed("11-03:02:26") == Double(11 * 86400 + 3 * 3600 + 2 * 60 + 26))
        #expect(PsParser.parseElapsed("abc") == nil)
        #expect(PsParser.parseElapsed("5") == nil)
    }

    @Test func parsesRowsWithSpacesInCommand() {
        let out = """
          543     1   501 11-03:03:06 /System/Library/CoreServices/powerd.bundle/powerd
        19482 18582   501       43:18 claude
        24606     1   501 06-04:27:22 /Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app/Contents/MacOS/Creative Cloud Content Manager.node --flag
        garbage line
        """
        let rows = PsParser.parse(out)
        #expect(rows.count == 3)
        #expect(rows[1] == PsRow(pid: 19482, ppid: 18582, uid: 501, elapsed: 2598, command: "claude"))
        #expect(rows[2].command.hasSuffix("Content Manager.node --flag"))
    }
}
