import Foundation

struct SystemTranslatedDraft {
    let draft: ImportDraft
    let failedCount: Int
}

@MainActor
struct LocalFileDatabaseImportWorkflow {
    typealias ProgressHandler = @MainActor (_ completedCount: Int, _ totalCount: Int, _ failedCount: Int) -> Void

    func translatedDraft(
        from draft: ImportDraft,
        systemTranslator: SystemTranslationCoordinator,
        progress: @escaping ProgressHandler
    ) async throws -> SystemTranslatedDraft {
        let sourceTexts = draft.items.map(\.targetEnglish)
        var failedIndexes = Set<Int>()
        let translations = try await systemTranslator.translateEnglishToSimplifiedChinese(
            sourceTexts,
            progress: { index, _ in
                progress(min(index + 1, sourceTexts.count), sourceTexts.count, failedIndexes.count)
            },
            failure: { index, _, _ in
                failedIndexes.insert(index)
                progress(min(index + 1, sourceTexts.count), sourceTexts.count, failedIndexes.count)
            }
        )
        var translatedDraft = draft
        var translatedItems: [ImportDraftItem] = []

        for index in translatedDraft.items.indices where translations.indices.contains(index) {
            let translation = translations[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if !translation.isEmpty {
                translatedDraft.items[index].sourceChinese = translation
                translatedItems.append(translatedDraft.items[index])
            } else {
                failedIndexes.insert(index)
            }
        }
        translatedDraft.items = translatedItems

        return SystemTranslatedDraft(draft: translatedDraft, failedCount: failedIndexes.count)
    }
}
