import Foundation

struct TEDTranscriptDownloader {
    enum DownloadError: LocalizedError {
        case invalidURL
        case unsupportedURL
        case requestFailed(Int)
        case transcriptNotFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "链接格式无效。"
            case .unsupportedURL:
                return "请输入 ted.com 的演讲链接。"
            case let .requestFailed(statusCode):
                return "TED 返回了 HTTP \(statusCode)。"
            case .transcriptNotFound:
                return "没有在页面中找到英文文稿。"
            }
        }
    }

    func downloadTranscript(from urlText: String) async throws -> String {
        guard let sourceURL = normalizedURL(from: urlText) else {
            throw DownloadError.invalidURL
        }
        guard let slug = talkSlug(from: sourceURL) else {
            throw DownloadError.unsupportedURL
        }

        let candidateURLs = transcriptCandidateURLs(for: slug, sourceURL: sourceURL)
        for url in candidateURLs {
            guard let payload = try? await fetchText(from: url),
                  let transcript = extractTranscript(from: payload) else {
                continue
            }
            return transcript
        }

        throw DownloadError.transcriptNotFound
    }

    private func normalizedURL(from urlText: String) -> URL? {
        if let url = URL(string: urlText), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(urlText)")
    }

    private func talkSlug(from url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(),
              host == "ted.com" || host.hasSuffix(".ted.com") else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard let talksIndex = components.firstIndex(of: "talks"),
              components.indices.contains(talksIndex + 1) else {
            return nil
        }

        return components[talksIndex + 1]
    }

    private func transcriptCandidateURLs(for slug: String, sourceURL: URL) -> [URL] {
        [
            URL(string: "https://www.ted.com/talks/\(slug)/transcript.json?language=en"),
            URL(string: "https://www.ted.com/talks/\(slug)/transcript?language=en"),
            sourceURL
        ].compactMap(\.self)
    }

    private func fetchText(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw DownloadError.requestFailed(httpResponse.statusCode)
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func extractTranscript(from payload: String) -> String? {
        if let data = payload.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let transcript = transcriptText(from: json) {
            return transcript
        }

        if let nextData = scriptJSON(id: "__NEXT_DATA__", in: payload),
           let json = try? JSONSerialization.jsonObject(with: nextData),
           let transcript = transcriptText(from: json) {
            return transcript
        }

        let strippedText = payload
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let decodedText = decodeHTMLEntities(strippedText)
        return cleanedTranscript(decodedText)
    }

    private func scriptJSON(id: String, in html: String) -> Data? {
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        let pattern = #"<script[^>]+id=["']\#(escapedID)["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[range]).data(using: .utf8)
    }

    private func transcriptText(from json: Any) -> String? {
        let candidates = transcriptCandidates(from: json)
            .map { decodeHTMLEntities($0) }
            .compactMap(cleanedTranscript)

        return candidates.max { $0.count < $1.count }
    }

    private func transcriptCandidates(from value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            if let paragraphs = dictionary["paragraphs"] as? [[String: Any]] {
                let cuesText = paragraphs.flatMap { paragraph in
                    paragraph["cues"] as? [[String: Any]] ?? []
                }
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
                if !cuesText.isEmpty {
                    return [cuesText]
                }
            }

            if let cues = dictionary["cues"] as? [[String: Any]] {
                let cuesText = cues
                    .compactMap { $0["text"] as? String }
                    .joined(separator: " ")
                if !cuesText.isEmpty {
                    return [cuesText]
                }
            }

            return dictionary.values.flatMap(transcriptCandidates)
        }

        if let array = value as? [Any] {
            return array.flatMap(transcriptCandidates)
        }

        return []
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let decoded = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ).string else {
            return text
        }
        return decoded
    }

    private func cleanedTranscript(_ text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\([^\)]*(Applause|Laughter|Music)[^\)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > 80,
              normalized.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }
}
