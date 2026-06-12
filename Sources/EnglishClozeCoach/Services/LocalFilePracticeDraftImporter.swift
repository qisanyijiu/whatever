import Foundation

struct LocalFilePracticeDraftImporter {
    var folderImporter: FolderTextImporter
    var questionImporter: QuestionImporter
    var maximumBatchByteCount: Int

    init(
        folderImporter: FolderTextImporter = FolderTextImporter(),
        questionImporter: QuestionImporter = QuestionImporter(),
        maximumBatchByteCount: Int = 512 * 1024
    ) {
        self.folderImporter = folderImporter
        self.questionImporter = questionImporter
        self.maximumBatchByteCount = maximumBatchByteCount
    }

    func importDraft(fromFiles fileURLs: [URL], name: String) throws -> ImportDraft {
        try importDraft(name: name) { handleBatch in
            try folderImporter.importTextBatches(
                fromFiles: fileURLs,
                maximumBatchByteCount: maximumBatchByteCount,
                handleBatch: handleBatch
            )
        }
    }

    func importDraft(fromFolder folderURL: URL, name: String) throws -> ImportDraft {
        try importDraft(name: name) { handleBatch in
            try folderImporter.importTextBatches(
                from: folderURL,
                maximumBatchByteCount: maximumBatchByteCount,
                handleBatch: handleBatch
            )
        }
    }

    private func importDraft(
        name: String,
        importBatches: (@escaping (FolderImportBatch) throws -> Void) throws -> FolderImportSummary
    ) throws -> ImportDraft {
        var items: [ImportDraftItem] = []
        let summary = try importBatches { batch in
            if let draft = questionImporter.importDraft(from: batch.text, name: "", source: "") {
                items.append(contentsOf: draft.items)
            }
        }

        guard !items.isEmpty else {
            throw FolderTextImporter.ImportError.noSupportedEnglishFiles
        }

        return ImportDraft(
            name: resolvedName(requestedName: name, fallbackName: summary.folderName),
            source: summary.sourceLabel,
            items: items
        )
    }

    private func resolvedName(requestedName: String, fallbackName: String) -> String {
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "导入题库" else {
            return fallbackName
        }
        return trimmed
    }
}
