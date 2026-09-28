import Foundation

public enum LsofParser {
    /// `lsof -nP -iTCP -sTCP:LISTEN -F pn` 출력을 pid별 LISTEN 포트(중복 제거, 오름차순)로 바꾼다.
    public static func parse(_ output: String) -> [Int32: [Int]] {
        var result: [Int32: Set<Int>] = [:]
        var current: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                current = Int32(value)
            case "n":
                guard let pid = current,
                      let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                result[pid, default: []].insert(port)
            default:
                continue
            }
        }
        return result.mapValues { $0.sorted() }
    }
}
