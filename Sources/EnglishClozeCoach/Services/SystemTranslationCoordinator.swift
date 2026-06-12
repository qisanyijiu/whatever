import Foundation

enum SystemTranslationError: LocalizedError {
    case unavailable
    case missingRequest
    case mismatchedResponseCount

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "当前 macOS 版本不支持系统翻译，请升级到 macOS 15 或更高版本。"
        case .missingRequest:
            return "系统翻译任务已失效。"
        case .mismatchedResponseCount:
            return "系统翻译返回数量不匹配。"
        }
    }
}

struct SystemTranslationRequest: Identifiable, Equatable {
    let id: UUID
    let sourceTexts: [String]
}

@MainActor
final class SystemTranslationCoordinator: ObservableObject {
    @Published private(set) var activeRequest: SystemTranslationRequest?
    @Published private(set) var completedCount = 0
    @Published private(set) var totalCount = 0

    typealias ProgressHandler = @MainActor (_ index: Int, _ translation: String) -> Void
    typealias FailureHandler = @MainActor (_ index: Int, _ sourceText: String, _ error: Error) -> Void

    private struct PendingRequest {
        let request: SystemTranslationRequest
        let continuation: CheckedContinuation<[String], Error>
        let progress: ProgressHandler?
        let failure: FailureHandler?
    }

    private var queue: [PendingRequest] = []

    func translateEnglishToSimplifiedChinese(
        _ sourceTexts: [String],
        progress: ProgressHandler? = nil,
        failure: FailureHandler? = nil
    ) async throws -> [String] {
        let trimmedTexts = sourceTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmedTexts.isEmpty else {
            return []
        }

        guard #available(macOS 15.0, *) else {
            throw SystemTranslationError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.append(PendingRequest(
                request: SystemTranslationRequest(id: UUID(), sourceTexts: trimmedTexts),
                continuation: continuation,
                progress: progress,
                failure: failure
            ))
            startNextIfNeeded()
        }
    }

    func recordProgress(requestID: UUID, index: Int, translation: String) {
        guard let activeRequest,
              activeRequest.id == requestID,
              queue.first?.request.id == requestID else {
            return
        }

        completedCount = min(max(completedCount, index + 1), activeRequest.sourceTexts.count)
        queue.first?.progress?(index, translation.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func recordFailure(requestID: UUID, index: Int, error: Error) {
        guard let activeRequest,
              activeRequest.id == requestID,
              activeRequest.sourceTexts.indices.contains(index),
              queue.first?.request.id == requestID else {
            return
        }

        completedCount = min(max(completedCount, index + 1), activeRequest.sourceTexts.count)
        queue.first?.failure?(index, activeRequest.sourceTexts[index], error)
    }

    func complete(requestID: UUID, translations: [String]) {
        guard let activeRequest, activeRequest.id == requestID else {
            return
        }
        guard translations.count == activeRequest.sourceTexts.count else {
            fail(requestID: requestID, error: SystemTranslationError.mismatchedResponseCount)
            return
        }

        let pending = queue.removeFirst()
        pending.continuation.resume(returning: translations)
        self.activeRequest = nil
        completedCount = 0
        totalCount = 0
        startNextIfNeeded()
    }

    func fail(requestID: UUID, error: Error) {
        guard let activeRequest, activeRequest.id == requestID else {
            return
        }

        let pending = queue.removeFirst()
        pending.continuation.resume(throwing: error)
        self.activeRequest = nil
        completedCount = 0
        totalCount = 0
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard activeRequest == nil, let next = queue.first else {
            return
        }
        activeRequest = next.request
        completedCount = 0
        totalCount = next.request.sourceTexts.count
    }
}
