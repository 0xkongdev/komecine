import Foundation

struct HLSMetadata {
    var qualities: [VideoQuality] = []
    var subtitles: [HLSTextTrack] = []

    static func attributes(_ line: String) -> [String: String] {
        let input = String(line.drop(while: { $0 != ":" }).dropFirst())
        let pattern = #"([A-Z0-9-]+)=(?:"([^"]*)"|([^,]*))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = input as NSString
        var values: [String: String] = [:]
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            let range = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            values[ns.substring(with: match.range(at: 1))] = ns.substring(with: range)
        }
        return values
    }

    static func resolve(_ value: String, base: URL) -> URL? {
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    static func parse(_ text: String, baseURL: URL) -> HLSMetadata {
        var result = HLSMetadata()
        var pending: [String: String]?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-MEDIA:") {
                let values = attributes(line)
                if values["TYPE"] == "SUBTITLES", let uri = values["URI"], let url = resolve(uri, base: baseURL) {
                    result.subtitles.append(HLSTextTrack(name: values["NAME"] ?? values["LANGUAGE"] ?? "Phụ đề", language: values["LANGUAGE"] ?? "", url: url))
                }
            } else if line.hasPrefix("#EXT-X-STREAM-INF:") { pending = attributes(line) }
            else if !line.isEmpty, !line.hasPrefix("#"), let values = pending {
                defer { pending = nil }
                let size = (values["RESOLUTION"] ?? "").split(separator: "x").compactMap { Int($0) }
                guard size.count == 2, size[0] > 0, size[1] > 0, let url = resolve(line, base: baseURL) else { continue }
                let quality = VideoQuality(height: size[1], width: size[0], bandwidth: Double(values["BANDWIDTH"] ?? "") ?? 0, url: url)
                if !result.qualities.contains(where: { $0.height == quality.height }) { result.qualities.append(quality) }
            }
        }
        result.qualities.sort { $0.height > $1.height }
        return result
    }

    static func load(_ url: URL) async throws -> HLSMetadata {
        let (text, resolved) = try await resource(url)
        return parse(text, baseURL: resolved)
    }

    static func resource(_ url: URL) async throws -> (String, URL) {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue("application/vnd.apple.mpegurl,text/vtt,text/plain,*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 8_000_000,
              let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return (text, response.url ?? url)
    }
}
