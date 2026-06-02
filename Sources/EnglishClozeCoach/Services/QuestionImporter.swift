import Foundation

struct QuestionImporter {
    var translationService: TranslationService = PlaceholderTranslationService()
    var clozeGenerator: ClozeGenerator = ClozeGenerator()

    func importItems(from text: String) -> [PracticeItem] {
        splitSentences(text).compactMap { sentence in
            let id = "imported-\(UUID().uuidString)"
            let segments = clozeGenerator.segments(from: sentence, itemID: id)
            guard segments.contains(where: { segment in
                if case .blank = segment {
                    return true
                }
                return false
            }) else {
                return nil
            }

            return PracticeItem(
                id: id,
                sourceChinese: translationService.translate(english: sentence),
                targetEnglish: sentence,
                segments: segments
            )
        }
    }

    private func splitSentences(_ text: String) -> [String] {
        let nsText = text as NSString
        let regex = try? NSRegularExpression(pattern: #"[^.!?\n]+[.!?]?"#)
        let matches = regex?.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        ) ?? []

        return matches
            .map { match in
                nsText.substring(with: match.range)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { sentence in
                sentence.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
            }
    }
}
