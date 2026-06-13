import Foundation

enum TranslationJobStatus: String, Codable, Hashable {
    case importing
    case ready
    case evaluating
    case translating
    case paused
    case completed
    case failed
}

enum TranslationJobItemStatus: String, Codable, Hashable {
    case pendingEvaluation
    case evaluating
    case pending
    case translating
    case translated
    case discarded
    case evaluationFailed
    case failed
}

enum TranslationJobSourceKind: Hashable {
    case localFile
    case pastedText
    case remoteURL
    case other

    static func inferred(source: String, importedFileCount: Int) -> TranslationJobSourceKind {
        if source == "本地文件" || source.contains("本地文件") || source.contains("文件夹") {
            return .localFile
        }
        let lowercasedSource = source.lowercased()
        if source == "粘贴文本" {
            return .pastedText
        }
        if lowercasedSource.hasPrefix("http://") || lowercasedSource.hasPrefix("https://") {
            return .remoteURL
        }
        if importedFileCount > 0 {
            return .localFile
        }
        return .other
    }
}

struct TranslationJobItem: Identifiable, Codable, Hashable {
    let id: String
    var sourceChinese: String
    var targetEnglish: String
    var blankText: String
    var translatedChinese: String?
    var status: TranslationJobItemStatus
    var errorMessage: String?
    var retryCount: Int

    var effectiveChinese: String {
        let translation = translatedChinese?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return translation.isEmpty ? sourceChinese : translation
    }

    var canImportToLibrary: Bool {
        status != .discarded && !targetEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var needsSystemTranslation: Bool {
        canImportToLibrary
            && translatedChinese == nil
            && (status == .pendingEvaluation || status == .pending)
    }
}

struct TranslationJobProgressSummary: Hashable {
    var totalCount: Int
    var translatedCount: Int
    var failedCount: Int
    var discardedCount: Int
    var activeCount: Int
    var waitingCount: Int
    var pendingCount: Int

    var processedCount: Int {
        translatedCount + failedCount + discardedCount
    }

    var progressText: String {
        "\(translatedCount)/\(totalCount)"
    }
}

struct TranslationJob: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var source: String
    var providerID: AIProviderConfig.ID?
    var status: TranslationJobStatus
    var createdAt: Date
    var updatedAt: Date
    var importedFileCount: Int
    var items: [TranslationJobItem]
    var errorMessage: String?
    var processingStartedAt: Date?
    var itemsCompletedAtStart: Int
    var importedToLibraryAt: Date? = nil

    var progressSummary: TranslationJobProgressSummary {
        var summary = TranslationJobProgressSummary(
            totalCount: items.count,
            translatedCount: 0,
            failedCount: 0,
            discardedCount: 0,
            activeCount: 0,
            waitingCount: 0,
            pendingCount: 0
        )

        for item in items {
            switch item.status {
            case .translated:
                summary.translatedCount += 1
            case .failed, .evaluationFailed:
                summary.failedCount += 1
            case .discarded:
                summary.discardedCount += 1
            case .evaluating, .translating:
                summary.activeCount += 1
                summary.pendingCount += 1
            case .pendingEvaluation, .pending:
                summary.waitingCount += 1
                summary.pendingCount += 1
            }
        }

        return summary
    }

    var importableLibraryItemCount: Int {
        if isLocalFileSource {
            return items.filter { $0.canImportToLibrary && $0.status == .translated }.count
        }
        return items.filter(\.canImportToLibrary).count
    }

    var canImportToLibrary: Bool {
        importedToLibraryAt == nil
            && importableLibraryItemCount > 0
            && status != .importing
            && status != .translating
            && status != .evaluating
    }

    var sourceKind: TranslationJobSourceKind {
        TranslationJobSourceKind.inferred(source: source, importedFileCount: importedFileCount)
    }

    var isLocalFileSource: Bool {
        sourceKind == .localFile
    }

    var needsSystemTranslation: Bool {
        isLocalFileSource
            && (status == .ready || status == .paused)
            && items.contains { $0.needsSystemTranslation }
    }

    var translatedCount: Int {
        progressSummary.translatedCount
    }

    var failedCount: Int {
        progressSummary.failedCount
    }

    var discardedCount: Int {
        progressSummary.discardedCount
    }

    var pendingCount: Int {
        progressSummary.pendingCount
    }

    var progressText: String {
        progressSummary.progressText
    }

    var canStart: Bool {
        (status == .ready || status == .paused || status == .failed)
            && items.contains { $0.status == .pendingEvaluation || $0.status == .pending }
    }

    var canPause: Bool {
        status == .translating || status == .evaluating
    }

    var processedCount: Int {
        progressSummary.processedCount
    }

    var estimatedSecondsRemaining: Int? {
        estimatedSecondsRemaining(processedCount: processedCount)
    }

    func estimatedSecondsRemaining(processedCount: Int, now: Date = Date()) -> Int? {
        guard let startedAt = processingStartedAt,
              processedCount > itemsCompletedAtStart else {
            return nil
        }
        let elapsed = max(now.timeIntervalSince(startedAt), 1)
        let completed = processedCount - itemsCompletedAtStart
        let rate = Double(completed) / elapsed
        let remaining = max(items.count - processedCount, 0)
        guard remaining > 0 else {
            return nil
        }
        return Int(Double(remaining) / rate)
    }
}
