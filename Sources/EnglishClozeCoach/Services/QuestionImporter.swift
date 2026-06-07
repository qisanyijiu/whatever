import Foundation

struct QuestionImporter {
    var translationService: TranslationService = PlaceholderTranslationService()
    var clozeGenerator: ClozeGenerator = ClozeGenerator()

    func importDraft(from text: String, name: String, source: String) -> ImportDraft? {
        let items = splitSentences(text).compactMap { sentence -> ImportDraftItem? in
            let id = "imported-\(UUID().uuidString)"
            let segments = clozeGenerator.segments(from: sentence, itemID: id)
            let blanks = segments.compactMap { segment in
                if case let .blank(blank) = segment {
                    return blank.answer
                }
                return nil
            }

            guard !blanks.isEmpty else {
                return nil
            }

            return ImportDraftItem(
                id: id,
                sourceChinese: translationService.translate(english: sentence),
                targetEnglish: sentence,
                blankText: blanks.joined(separator: ", ")
            )
        }

        guard !items.isEmpty else {
            return nil
        }
        return ImportDraft(name: name, source: source, items: items)
    }

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

    func practiceItems(from draft: ImportDraft) -> [PracticeItem] {
        draft.items.compactMap { draftItem in
            let targetEnglish = draftItem.targetEnglish
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetEnglish.isEmpty else {
                return nil
            }

            let segments = clozeGenerator.segments(
                from: targetEnglish,
                itemID: draftItem.id,
                blankAnswers: draftItem.blankAnswers
            )
            guard segments.contains(where: { segment in
                if case .blank = segment {
                    return true
                }
                return false
            }) else {
                return nil
            }

            return PracticeItem(
                id: draftItem.id,
                sourceChinese: draftItem.sourceChinese,
                targetEnglish: targetEnglish,
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
