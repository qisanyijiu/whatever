import Foundation

struct ScriptTextDownloader {
    enum DownloadError: LocalizedError {
        case invalidURL
        case unsupportedScheme
        case requestFailed(Int)
        case readableTextNotFound

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "链接格式无效。"
            case .unsupportedScheme:
                return "请输入 http 或 https 链接。"
            case let .requestFailed(statusCode):
                return "服务器返回了 HTTP \(statusCode)。"
            case .readableTextNotFound:
                return "没有在链接内容中找到可用英文。"
            }
        }
    }

    func downloadText(from urlText: String) async throws -> String {
        guard let url = normalizedURL(from: urlText) else {
            throw DownloadError.invalidURL
        }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw DownloadError.unsupportedScheme
        }

        let payload = try await fetchText(from: url)
        guard let text = preparedText(from: payload, sourceHint: url.pathExtension) else {
            throw DownloadError.readableTextNotFound
        }
        return text
    }

    func preparedText(from payload: String, sourceHint: String? = nil) -> String? {
        let hint = sourceHint?.lowercased() ?? ""
        let text: String

        if hint == "srt" || looksLikeSRT(payload) {
            text = subtitleText(from: payload)
        } else if hint == "vtt" || looksLikeVTT(payload) {
            text = subtitleText(from: payload)
        } else if looksLikeHTML(payload) {
            text = htmlText(from: payload)
        } else {
            text = payload
        }

        return cleanedText(text)
    }

    private func normalizedURL(from urlText: String) -> URL? {
        if let url = URL(string: urlText), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(urlText)")
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

    private func subtitleText(from payload: String) -> String {
        payload
            .components(separatedBy: .newlines)
            .compactMap(subtitleLineText)
            .joined(separator: " ")
    }

    private func subtitleLineText(_ line: String) -> String? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed == "WEBVTT" ||
            trimmed.hasPrefix("NOTE") ||
            trimmed.hasPrefix("STYLE") ||
            trimmed.hasPrefix("REGION") ||
            trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil ||
            trimmed.contains("-->") {
            return nil
        }

        trimmed = trimmed
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*-\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(
                of: #"^[A-Za-z][A-Za-z0-9 .'\-]{1,38}:\s+"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }

    private func htmlText(from payload: String) -> String {
        let strippedText = payload
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeHTMLEntities(strippedText)
    }

    private func looksLikeSRT(_ payload: String) -> Bool {
        payload.range(
            of: #"\d{1,2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{1,2}:\d{2}:\d{2},\d{3}"#,
            options: .regularExpression
        ) != nil
    }

    private func looksLikeVTT(_ payload: String) -> Bool {
        payload.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") ||
            payload.range(
                of: #"\d{1,2}:\d{2}:\d{2}\.\d{3}\s+-->\s+\d{1,2}:\d{2}:\d{2}\.\d{3}"#,
                options: .regularExpression
            ) != nil
    }

    private func looksLikeHTML(_ payload: String) -> Bool {
        payload.range(of: #"<html[\s>]"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            payload.range(of: #"<body[\s>]"#, options: [.regularExpression, .caseInsensitive]) != nil
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

    private func cleanedText(_ text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\u{FEFF}", with: " ")
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: #"\([^\)]*(Applause|Laughter|Music|Laughs|Cheering|Inaudible)[^\)]*\)"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > 40,
              normalized.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }
}
