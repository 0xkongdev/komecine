import Foundation

struct SubtitleCue: Equatable {
    let start: Double
    let end: Double
    let text: String
}

enum WebVTT {
    static func timestamp(_ value: String) -> Double? {
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Double($0) }
        guard (2...3).contains(parts.count) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
    static func mapOffset(_ text: String) -> Double? {
        guard let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("X-TIMESTAMP-MAP=") }),
              let localRange = line.range(of: "LOCAL:"), let mpegRange = line.range(of: "MPEGTS:") else { return nil }
        let local = line[localRange.upperBound...].split(separator: ",")[0]
        let mpeg = line[mpegRange.upperBound...].split(separator: ",")[0]
        guard let a = timestamp(String(local)), let b = Double(mpeg) else { return nil }
        return b / 90_000 - a
    }
    static func parse(_ text: String, segmentStart: Double = 0) -> [SubtitleCue] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let offset = mapOffset(text) ?? segmentStart
        var cues: [SubtitleCue] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard line.contains("-->"), !line.hasPrefix("NOTE") else { index += 1; continue }
            let times = line.components(separatedBy: "-->")
            guard times.count == 2, let start = timestamp(times[0]),
                  let endToken = times[1].split(whereSeparator: { $0.isWhitespace }).first,
                  let end = timestamp(String(endToken)), end > start else { index += 1; continue }
            index += 1
            var body: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                body.append(lines[index]); index += 1
            }
            let clean = body.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { cues.append(SubtitleCue(start: start + offset, end: end + offset, text: clean)) }
        }
        return cues.sorted { $0.start < $1.start }
    }
    static func text(at time: Double, cues: [SubtitleCue]) -> String {
        cues.filter { $0.start <= time && time < $0.end }.map(\.text).joined(separator: "\n")
    }
}
