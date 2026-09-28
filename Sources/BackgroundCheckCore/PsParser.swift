import Foundation

public struct PsRow: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var elapsed: TimeInterval
    public var command: String

    public init(pid: Int32, ppid: Int32, uid: UInt32, elapsed: TimeInterval, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.elapsed = elapsed
        self.command = command
    }
}

public enum PsParser {
    /// `ps -axww -o pid=,ppid=,uid=,etime=,command=` 출력을 파싱한다. 형식이 깨진 줄은 버린다.
    public static func parse(_ output: String) -> [PsRow] {
        output.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> PsRow? {
        let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        var rest = Substring(line)
        var fields: [Substring] = []
        for _ in 0..<4 {
            rest = rest.drop(while: isBlank)
            guard let end = rest.firstIndex(where: isBlank) else { return nil }
            fields.append(rest[..<end])
            rest = rest[end...]
        }
        let command = rest.drop(while: isBlank)
        guard !command.isEmpty,
              let pid = Int32(fields[0]),
              let ppid = Int32(fields[1]),
              let uid = UInt32(fields[2]),
              let elapsed = parseElapsed(String(fields[3])) else { return nil }
        return PsRow(pid: pid, ppid: ppid, uid: uid, elapsed: elapsed, command: String(command))
    }

    /// `[[DD-]HH:]MM:SS` 형식의 etime을 초로 바꾼다.
    public static func parseElapsed(_ s: String) -> TimeInterval? {
        var days = 0
        var clock = Substring(s)
        if let dash = clock.firstIndex(of: "-") {
            guard let d = Int(clock[..<dash]) else { return nil }
            days = d
            clock = clock[clock.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == clock.split(separator: ":").count, (2...3).contains(parts.count) else { return nil }
        let (h, m, sec) = parts.count == 3 ? (parts[0], parts[1], parts[2]) : (0, parts[0], parts[1])
        return TimeInterval(((days * 24 + h) * 60 + m) * 60 + sec)
    }
}
