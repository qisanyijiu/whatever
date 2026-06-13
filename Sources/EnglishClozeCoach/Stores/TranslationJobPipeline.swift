import Foundation

struct TranslationJobItemUpdate: Sendable {
    let itemID: TranslationJobItem.ID
    let status: TranslationJobItemStatus
    let translatedChinese: String?
    let errorMessage: String?
}

actor TranslationJobProcessingBuffer {
    private var updates: [TranslationJob.ID: [String: TranslationJobItemUpdate]] = [:]

    func record(jobID: TranslationJob.ID, update: TranslationJobItemUpdate) {
        updates[jobID, default: [:]][update.itemID] = update
    }

    func drain(jobID: TranslationJob.ID) -> [TranslationJobItemUpdate] {
        let result = updates[jobID]?.values.map { $0 } ?? []
        updates[jobID] = nil
        return result
    }

    func discard(jobID: TranslationJob.ID) {
        updates[jobID] = nil
    }
}

struct TranslationJobPipeline: Sendable {
    var maxRetryCount = 5
    var maxConcurrency = 12

    func process(
        jobID: TranslationJob.ID,
        items: [TranslationJobItem],
        provider: AIProviderConfig,
        aiTextService: AITextService,
        buffer: TranslationJobProcessingBuffer
    ) async {
        let gate = ConcurrencyGate(max: maxConcurrency)
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                if Task.isCancelled { return }
                await gate.enter()
                if Task.isCancelled {
                    await gate.leave()
                    return
                }
                group.addTask {
                    await processItem(
                        jobID: jobID,
                        item: item,
                        provider: provider,
                        aiTextService: aiTextService,
                        buffer: buffer
                    )
                    await gate.leave()
                }
            }
        }
    }

    private func processItem(
        jobID: TranslationJob.ID,
        item: TranslationJobItem,
        provider: AIProviderConfig,
        aiTextService: AITextService,
        buffer: TranslationJobProcessingBuffer
    ) async {
        guard !Task.isCancelled else { return }
        var currentStatus = item.status

        if currentStatus == .pendingEvaluation {
            await buffer.record(jobID: jobID, update: TranslationJobItemUpdate(
                itemID: item.id, status: .evaluating,
                translatedChinese: nil, errorMessage: nil
            ))

            do {
                let results = try await retry {
                    try await aiTextService.evaluateSentenceValue([item.targetEnglish], using: provider)
                }
                guard let isValuable = results.first else {
                    throw AITextServiceError.emptyResponse
                }
                guard !Task.isCancelled else { return }
                if isValuable {
                    currentStatus = .pending
                    await buffer.record(jobID: jobID, update: TranslationJobItemUpdate(
                        itemID: item.id, status: .pending,
                        translatedChinese: nil, errorMessage: nil
                    ))
                } else {
                    await buffer.record(jobID: jobID, update: TranslationJobItemUpdate(
                        itemID: item.id, status: .discarded,
                        translatedChinese: nil, errorMessage: nil
                    ))
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
                await buffer.record(jobID: jobID, update: TranslationJobItemUpdate(
                    itemID: item.id, status: .evaluationFailed,
                    translatedChinese: nil, errorMessage: error.localizedDescription
                ))
                return
            }
        }

        if currentStatus != .pending { return }
        if Task.isCancelled { return }

        await buffer.record(jobID: jobID, update: TranslationJobItemUpdate(
            itemID: item.id, status: .translating,
            translatedChinese: nil, errorMessage: nil
        ))

        do {
            let translations = try await retry {
                try await aiTextService.translateEnglishToChinese([item.targetEnglish], using: provider)
            }
            let translation = translations.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if translation.isEmpty { throw AITextServiceError.emptyResponse }
            guard !Task.isCancelled else { return }
            await buffer.record(jobID: jobID, update: TranslationJobItemUpdate(
                itemID: item.id, status: .translated,
                translatedChinese: translation, errorMessage: nil
            ))
        } catch {
            guard !Task.isCancelled else { return }
            await buffer.record(jobID: jobID, update: TranslationJobItemUpdate(
                itemID: item.id, status: .failed,
                translatedChinese: nil, errorMessage: error.localizedDescription
            ))
        }
    }

    private func retry<T>(operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxRetryCount {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxRetryCount - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
                }
            }
        }
        throw lastError ?? AITextServiceError.invalidResponse
    }
}

private actor ConcurrencyGate {
    private let max: Int
    private var running = 0
    private var waiters: [(UUID, CheckedContinuation<Void, Never>)] = []

    init(max: Int) { self.max = max }

    func enter() async {
        if running < max { running += 1; return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.0 == id }) {
            waiters[index].1.resume()
            waiters.remove(at: index)
        }
    }

    func leave() {
        running -= 1
        if let next = waiters.first {
            waiters.removeFirst()
            running += 1
            next.1.resume()
        }
    }
}
