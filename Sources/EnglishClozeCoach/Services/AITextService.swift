import Foundation

struct AITextService {
    private let client: OpenAICompatibleAIClient

    init(client: OpenAICompatibleAIClient = OpenAICompatibleAIClient()) {
        self.client = client
    }

    func translateEnglishToChinese(_ englishSentences: [String], using provider: AIProviderConfig) async throws -> [String] {
        let sentences = englishSentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sentences.isEmpty else {
            return []
        }

        let numberedSentences = sentences.enumerated()
            .map { index, sentence in "\(index + 1). \(sentence)" }
            .joined(separator: "\n")

        let content = try await client.complete(
            provider: provider,
            systemPrompt: """
            You translate English learning material for Chinese native speakers.
            Return only a JSON array of Simplified Chinese strings. Keep the same order and count.
            """,
            userPrompt: """
            Translate these English sentences into natural Simplified Chinese for cloze practice.

            \(numberedSentences)
            """
        )

        let translations = try parseStringArray(from: content)
        guard translations.count == sentences.count else {
            throw AITextServiceError.unexpectedTranslationCount(expected: sentences.count, actual: translations.count)
        }
        return translations
    }

    func explainAnswer(for item: PracticeItem, answers: [String: String], using provider: AIProviderConfig) async throws -> String {
        let answerLines = item.blanks.enumerated().map { index, blank in
            let userAnswer = answers[blank.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "\(index + 1). 空位 \(index + 1)：正确答案 \"\(blank.answer)\"，学生答案 \"\(userAnswer.isEmpty ? "未作答" : userAnswer)\""
        }
        .joined(separator: "\n")

        return try await client.complete(
            provider: provider,
            systemPrompt: """
            You are an English cloze exercise coach for Chinese native speakers.
            Reply in Simplified Chinese. Be concise, practical, and focused on why each blank uses that answer.
            Format the reply as simple Markdown with short headings, short paragraphs, and normal numbered lines.
            Do not use emoji, tables, arrows, decorative symbols, or uncommon punctuation.
            """,
            userPrompt: """
            中文提示：
            \(item.sourceChinese)

            英文原句：
            \(item.targetEnglish)

            学生答案：
            \(answerLines)

            请解释每个空的正确答案、常见误区，以及一个短小记忆提示。
            """
        )
    }

    private func parseStringArray(from content: String) throws -> [String] {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if let startIndex = trimmedContent.firstIndex(of: "["),
           let endIndex = trimmedContent.lastIndex(of: "]"),
           startIndex <= endIndex {
            jsonText = String(trimmedContent[startIndex...endIndex])
        } else {
            jsonText = trimmedContent
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw AITextServiceError.invalidResponse
        }

        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            let lines = trimmedContent
                .split(whereSeparator: \.isNewline)
                .map { line in
                    line.replacingOccurrences(
                        of: #"^\s*[-*\d.)]+\s*"#,
                        with: "",
                        options: .regularExpression
                    )
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' ，,"))
                }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else {
                throw AITextServiceError.invalidResponse
            }
            return lines
        }
    }
}

struct OpenAICompatibleAIClient {
    func complete(provider: AIProviderConfig, systemPrompt: String, userPrompt: String) async throws -> String {
        guard provider.isReady else {
            throw AITextServiceError.providerNotReady
        }

        guard let url = endpointURL(from: provider.baseURL) else {
            throw AITextServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: provider.model,
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt)
                ],
                temperature: 0.2
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AITextServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AITextServiceError.requestFailed(errorMessage)
        }

        let decodedResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decodedResponse.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AITextServiceError.emptyResponse
        }
        return content
    }

    private func endpointURL(from baseURL: String) -> URL? {
        var urlText = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while urlText.hasSuffix("/") {
            urlText.removeLast()
        }
        if !urlText.hasSuffix("/chat/completions") {
            urlText += "/chat/completions"
        }
        return URL(string: urlText)
    }
}

enum AITextServiceError: LocalizedError {
    case providerNotReady
    case invalidBaseURL
    case invalidResponse
    case emptyResponse
    case requestFailed(String)
    case unexpectedTranslationCount(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .providerNotReady:
            return "当前 AI 配置不完整。"
        case .invalidBaseURL:
            return "AI Base URL 无效。"
        case .invalidResponse:
            return "AI 返回格式无法解析。"
        case .emptyResponse:
            return "AI 没有返回内容。"
        case let .requestFailed(message):
            return "AI 请求失败：\(message)"
        case let .unexpectedTranslationCount(expected, actual):
            return "AI 返回的翻译数量不匹配，期望 \(expected) 条，实际 \(actual) 条。"
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatMessage: Codable {
    let role: String
    let content: String?
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
}
