import Foundation

enum TranslationJobStatus: String, Codable, Hashable {
    case importing
    case ready
    case translating
    case paused
    case completed
    case failed
}

enum TranslationJobItemStatus: String, Codable, Hashable {
    case pending
    case translating
    case translated
    case failed
}

struct TranslationJobItem: Identifiable, Codable, Hashable {
    let id: String
    var sourceChinese: String
    var targetEnglish: String
    var blankText: String
    var translatedChinese: String?
    var status: TranslationJobItemStatus
    var errorMessage: String?

    var effectiveChinese: String {
        let translation = translatedChinese?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return translation.isEmpty ? sourceChinese : translation
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

    var translatedCount: Int {
        items.filter { $0.status == .translated }.count
    }

    var failedCount: Int {
        items.filter { $0.status == .failed }.count
    }

    var pendingCount: Int {
        items.filter { $0.status == .pending || $0.status == .translating }.count
    }

    var progressText: String {
        "\(translatedCount)/\(items.count)"
    }

    var canStart: Bool {
        (status == .ready || status == .paused || status == .failed)
            && items.contains { $0.status == .pending }
    }

    var canPause: Bool {
        status == .translating
    }
}
