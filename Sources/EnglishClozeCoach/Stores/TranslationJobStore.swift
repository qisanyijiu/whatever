import Foundation

private struct ItemUpdate: Sendable {
    let itemID: TranslationJobItem.ID
    let status: TranslationJobItemStatus
    let translatedChinese: String?
    let errorMessage: String?
}

private actor ProcessingBuffer {
    private var updates: [TranslationJob.ID: [String: ItemUpdate]] = [:]

    func record(jobID: TranslationJob.ID, update: ItemUpdate) {
        updates[jobID, default: [:]][update.itemID] = update
    }

    func drain(jobID: TranslationJob.ID) -> [ItemUpdate] {
        let result = updates[jobID]?.values.map { $0 } ?? []
        updates[jobID] = nil
        return result
    }

    func discard(jobID: TranslationJob.ID) {
        updates[jobID] = nil
    }
}

@MainActor
final class TranslationJobStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var jobs: [TranslationJob]
    @Published var selectedJobID: TranslationJob.ID?
    @Published private(set) var errorMessage: String?

    private let library: TranslationJobLibrary
    private let importer: QuestionImporter
    private let folderImporter: FolderTextImporter
    private let aiTextService: AITextService
    private let importBatchByteLimit: Int
    private var importTasks: [TranslationJob.ID: Task<Void, Never>] = [:]
    private var translationTasks: [TranslationJob.ID: Task<Void, Never>] = [:]
    private var syncTimer: Timer?
    private var backgroundSaveTask: Task<Void, Never>?
    private let buffer = ProcessingBuffer()

    init(
        library: TranslationJobLibrary = TranslationJobLibrary(),
        importer: QuestionImporter = QuestionImporter(),
        folderImporter: FolderTextImporter = FolderTextImporter(),
        aiTextService: AITextService = AITextService(),
        importBatchByteLimit: Int = 512 * 1024
    ) {
        self.library = library
        self.importer = importer
        self.folderImporter = folderImporter
        self.aiTextService = aiTextService
        self.importBatchByteLimit = importBatchByteLimit
        self.jobs = Self.restoredJobs(from: library.loadJobs())
        self.selectedJobID = jobs.first?.id
        saveJobsInBackground()
        startSyncTimerIfNeeded()
    }

    isolated deinit {
        syncTimer?.invalidate()
        backgroundSaveTask?.cancel()
        importTasks.values.forEach { $0.cancel() }
        translationTasks.values.forEach { $0.cancel() }
    }

    var selectedJob: TranslationJob? {
        guard let selectedJobID else {
            return jobs.first
        }
        return jobs.first { $0.id == selectedJobID } ?? jobs.first
    }

    // MARK: - Import

    @discardableResult
    func importFiles(
        _ urls: [URL],
        name: String,
        provider: AIProviderConfig?
    ) -> TranslationJob.ID {
        let job = createJob(name: name, source: "本地文件", providerID: provider?.id)
        let byteLimit = importBatchByteLimit
        let jobID = job.id
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let folderImporter = FolderTextImporter()
            let importer = QuestionImporter()
            let accessTokens = urls.map { url in
                (url: url, didStartAccessing: url.startAccessingSecurityScopedResource())
            }
            defer {
                accessTokens
                    .filter(\.didStartAccessing)
                    .forEach { $0.url.stopAccessingSecurityScopedResource() }
            }

            await self?.runImport(
                jobID: jobID,
                provider: provider,
                folderImporter: folderImporter,
                importer: importer
            ) {
                try folderImporter.importTextBatches(
                    fromFiles: urls,
                    maximumBatchByteCount: byteLimit,
                    handleBatch: $0
                )
            }
        }
        importTasks[jobID] = task
        return jobID
    }

    @discardableResult
    func importFolder(
        _ url: URL,
        name: String,
        provider: AIProviderConfig?
    ) -> TranslationJob.ID {
        let job = createJob(name: name, source: url.lastPathComponent.isEmpty ? "文件夹" : url.lastPathComponent, providerID: provider?.id)
        let byteLimit = importBatchByteLimit
        let jobID = job.id
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let folderImporter = FolderTextImporter()
            let importer = QuestionImporter()
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            await self?.runImport(
                jobID: jobID,
                provider: provider,
                folderImporter: folderImporter,
                importer: importer
            ) {
                try folderImporter.importTextBatches(
                    from: url,
                    maximumBatchByteCount: byteLimit,
                    handleBatch: $0
                )
            }
        }
        importTasks[jobID] = task
        return jobID
    }

    @discardableResult
    func importText(
        _ text: String,
        name: String,
        source: String,
        provider: AIProviderConfig?
    ) -> TranslationJob.ID {
        let job = createJob(name: name, source: source, providerID: provider?.id)
        let jobID = job.id
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let importer = QuestionImporter()
            let items = importer.importDraft(from: text, name: name, source: source)?.items ?? []
            await self?.finishImport(
                jobID: jobID,
                summaryName: name,
                summarySource: source,
                fileCount: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1,
                items: items,
                provider: provider
            )
        }
        importTasks[jobID] = task
        return jobID
    }

    // MARK: - Job control

    func startTranslation(jobID: TranslationJob.ID, provider: AIProviderConfig?) {
        guard translationTasks[jobID] == nil else { return }
        guard hasPendingItems(jobID: jobID) else { return }
        guard let provider, provider.isReady else {
            updateJob(jobID) { job in
                job.status = .failed
                job.errorMessage = "请先在 AI 页面配置并选择一个可用接口。"
            }
            return
        }

        updateJob(jobID) { job in
            job.providerID = provider.id
            job.status = .evaluating
            job.errorMessage = nil
            job.processingStartedAt = Date()
            job.itemsCompletedAtStart = job.processedCount
            for index in job.items.indices {
                if job.items[index].status == .translating {
                    job.items[index].status = .pending
                }
                if job.items[index].status == .evaluating {
                    job.items[index].status = .pendingEvaluation
                }
            }
        }
        saveJobsInBackground()
        startSyncTimerIfNeeded()

        let aiTextService = self.aiTextService
        let buffer = self.buffer
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runJobPipeline(
                jobID: jobID,
                provider: provider,
                aiTextService: aiTextService,
                buffer: buffer
            )
        }
        translationTasks[jobID] = task
    }

    func pause(jobID: TranslationJob.ID) {
        guard jobs.first(where: { $0.id == jobID })?.canPause == true else { return }
        importTasks[jobID]?.cancel()
        importTasks[jobID] = nil
        translationTasks[jobID]?.cancel()
        translationTasks[jobID] = nil
        Task { @MainActor [weak self, buffer] in
            guard let self else { return }
            let updates = await buffer.drain(jobID: jobID)
            if !updates.isEmpty {
                self.applyUpdates(jobID: jobID, updates: updates)
            }
            self.updateJob(jobID) { job in
                job.status = .paused
                job.processingStartedAt = nil
                for index in job.items.indices {
                    if job.items[index].status == .translating {
                        job.items[index].status = .pending
                    }
                    if job.items[index].status == .evaluating {
                        job.items[index].status = .pendingEvaluation
                    }
                }
            }
            self.stopSyncTimerIfIdle()
            self.saveJobsInBackground()
        }
    }

    func retryFailed(jobID: TranslationJob.ID, provider: AIProviderConfig?) {
        updateJob(jobID) { job in
            for index in job.items.indices {
                if job.items[index].status == .failed {
                    job.items[index].status = .pending
                    job.items[index].errorMessage = nil
                    job.items[index].retryCount = 0
                }
                if job.items[index].status == .evaluationFailed {
                    job.items[index].status = .pendingEvaluation
                    job.items[index].errorMessage = nil
                    job.items[index].retryCount = 0
                }
            }
            job.status = .ready
            job.errorMessage = nil
        }
        startTranslation(jobID: jobID, provider: provider)
    }

    func confirmDiscard(jobID: TranslationJob.ID) {
        updateJob(jobID) { job in
            job.items.removeAll { $0.status == .discarded }
        }
    }

    func markImportedToLibrary(jobID: TranslationJob.ID) {
        updateJob(jobID) { job in
            job.importedToLibraryAt = Date()
        }
        saveJobs()
    }

    func deleteJob(_ jobID: TranslationJob.ID) {
        importTasks[jobID]?.cancel()
        translationTasks[jobID]?.cancel()
        importTasks[jobID] = nil
        translationTasks[jobID] = nil
        Task { [buffer] in
            await buffer.discard(jobID: jobID)
        }
        jobs.removeAll { $0.id == jobID }
        selectedJobID = jobs.first?.id
        stopSyncTimerIfIdle()
        saveJobs()
    }

    func importDraft(for jobID: TranslationJob.ID) -> ImportDraft? {
        guard let job = jobs.first(where: { $0.id == jobID }), !job.items.isEmpty else {
            return nil
        }
        let validItems = job.items.filter { $0.status == .translated || $0.status == .pending || $0.status == .translating }
        guard !validItems.isEmpty else { return nil }
        return ImportDraft(
            id: job.id,
            name: job.name,
            source: job.source,
            items: validItems.map { item in
                ImportDraftItem(
                    id: item.id,
                    sourceChinese: item.effectiveChinese,
                    targetEnglish: item.targetEnglish,
                    blankText: item.blankText
                )
            }
        )
    }

    // MARK: - Sync timer

    private var hasProcessingJobs: Bool {
        jobs.contains { $0.status == .evaluating || $0.status == .translating }
    }

    private func startSyncTimerIfNeeded() {
        guard hasProcessingJobs, syncTimer == nil else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.flushAllBuffers()
            }
        }
    }

    private func stopSyncTimerIfIdle() {
        guard !hasProcessingJobs else { return }
        syncTimer?.invalidate()
        syncTimer = nil
        flushTick = 0
    }

    private var flushTick = 0

    private func flushAllBuffers() async {
        guard hasProcessingJobs else {
            stopSyncTimerIfIdle()
            return
        }

        flushTick += 1
        var didFlushUpdates = false
        for job in jobs where job.status == .evaluating || job.status == .translating {
            let updates = await buffer.drain(jobID: job.id)
            guard !updates.isEmpty else { continue }
            applyUpdates(jobID: job.id, updates: updates)
            didFlushUpdates = true
        }

        if didFlushUpdates && flushTick % 10 == 0 {
            saveJobsInBackground()
        }
    }

    private func applyUpdates(jobID: TranslationJob.ID, updates: [ItemUpdate]) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let itemIndicesByID = Dictionary(uniqueKeysWithValues: jobs[index].items.indices.map { itemIndex in
            (jobs[index].items[itemIndex].id, itemIndex)
        })
        var didUpdate = false

        for update in updates {
            guard let itemIndex = itemIndicesByID[update.itemID] else { continue }
            jobs[index].items[itemIndex].status = update.status
            if let chinese = update.translatedChinese {
                jobs[index].items[itemIndex].translatedChinese = chinese
            }
            if let error = update.errorMessage {
                jobs[index].items[itemIndex].errorMessage = error
            } else if update.status != .failed && update.status != .evaluationFailed {
                jobs[index].items[itemIndex].errorMessage = nil
            }
            if update.status == .translated || update.status == .discarded {
                jobs[index].items[itemIndex].retryCount = 0
            }
            didUpdate = true
        }
        guard didUpdate else { return }
        jobs[index].updatedAt = Date()
    }

    // MARK: - Persistence

    private func saveJobs() {
        let snapshot = jobs
        let lib = library
        do {
            try lib.save(snapshot)
            errorMessage = nil
        } catch {
            errorMessage = "保存翻译任务失败：\(error.localizedDescription)"
        }
    }

    private func saveJobsInBackground() {
        backgroundSaveTask?.cancel()
        let snapshot = jobs
        let lib = library
        backgroundSaveTask = Task.detached(priority: .background) {
            guard !Task.isCancelled else { return }
            do {
                try lib.save(snapshot)
            } catch {
                await MainActor.run {
                    // errorMessage silently updated; caller's responsibility to surface
                }
            }
        }
    }

    // MARK: - Constants and restore

    private nonisolated static let maxRetryCount = 5
    private nonisolated static let maxConcurrency = 12

    private static func restoredJobs(from jobs: [TranslationJob]) -> [TranslationJob] {
        jobs.map { job in
            var restoredJob = job
            if restoredJob.status == .importing || restoredJob.status == .translating || restoredJob.status == .evaluating {
                restoredJob.status = .paused
            }
            for index in restoredJob.items.indices {
                let status = restoredJob.items[index].status
                if status == .translating || status == .evaluating {
                    restoredJob.items[index].status = status == .evaluating ? .pendingEvaluation : .pending
                }
            }
            return restoredJob
        }
    }

    // MARK: - Job creation

    private func createJob(name: String, source: String, providerID: AIProviderConfig.ID?) -> TranslationJob {
        let now = Date()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let job = TranslationJob(
            id: "translation-job-\(UUID().uuidString)",
            name: trimmedName.isEmpty ? "导入题库" : trimmedName,
            source: source,
            providerID: providerID,
            status: .importing,
            createdAt: now,
            updatedAt: now,
            importedFileCount: 0,
            items: [],
            errorMessage: nil,
            processingStartedAt: nil,
            itemsCompletedAtStart: 0
        )
        jobs.insert(job, at: 0)
        selectedJobID = job.id
        saveJobs()
        return job
    }

    // MARK: - Import pipeline (background)

    nonisolated private func runImport(
        jobID: TranslationJob.ID,
        provider: AIProviderConfig?,
        folderImporter: FolderTextImporter,
        importer: QuestionImporter,
        importBatches: (@escaping (FolderImportBatch) throws -> Void) throws -> FolderImportSummary
    ) async {
        do {
            var importedItems: [ImportDraftItem] = []
            let summary = try importBatches { batch in
                if Task.isCancelled { throw CancellationError() }
                if let draft = importer.importDraft(from: batch.text, name: "", source: "") {
                    importedItems.append(contentsOf: draft.items)
                }
            }
            await finishImport(
                jobID: jobID,
                summaryName: summary.folderName,
                summarySource: summary.sourceLabel,
                fileCount: summary.fileCount,
                items: importedItems,
                provider: provider
            )
        } catch is CancellationError {
            await markPaused(jobID: jobID)
        } catch {
            await markImportFailed(jobID: jobID, message: error.localizedDescription)
        }
    }

    private func finishImport(
        jobID: TranslationJob.ID,
        summaryName: String,
        summarySource: String,
        fileCount: Int,
        items: [ImportDraftItem],
        provider: AIProviderConfig?
    ) async {
        guard !Task.isCancelled else {
            await markPaused(jobID: jobID)
            return
        }
        updateJob(jobID) { job in
            if !summaryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               job.name == "导入题库" {
                job.name = summaryName
            }
            job.source = summarySource
            job.importedFileCount = fileCount
            job.items = items.map { draftItem in
                TranslationJobItem(
                    id: draftItem.id,
                    sourceChinese: draftItem.sourceChinese,
                    targetEnglish: draftItem.targetEnglish,
                    blankText: draftItem.blankText,
                    translatedChinese: nil,
                    status: .pendingEvaluation,
                    errorMessage: nil,
                    retryCount: 0
                )
            }
            job.status = job.items.isEmpty ? .failed : .ready
            job.errorMessage = job.items.isEmpty ? "没有生成题目。" : nil
        }
        importTasks[jobID] = nil
        if !items.isEmpty {
            startTranslation(jobID: jobID, provider: provider)
        }
    }

    // MARK: - Processing pipeline (background)

    nonisolated private func runJobPipeline(
        jobID: TranslationJob.ID,
        provider: AIProviderConfig,
        aiTextService: AITextService,
        buffer: ProcessingBuffer
    ) async {
        while true {
            if Task.isCancelled {
                await markPaused(jobID: jobID)
                await MainActor.run { [weak self] in
                    self?.translationTasks[jobID] = nil
                }
                return
            }

            let snapshot = await pendingItemsSnapshot(jobID: jobID)
            if snapshot.isEmpty {
                await finishJob(jobID: jobID, buffer: buffer)
                await MainActor.run { [weak self] in
                    self?.translationTasks[jobID] = nil
                }
                return
            }

            await processItemsOnBackground(
                jobID: jobID,
                items: snapshot,
                provider: provider,
                aiTextService: aiTextService,
                buffer: buffer
            )

            await flushBufferToMainActor(jobID: jobID, buffer: buffer)
        }
    }

    private func flushBufferToMainActor(jobID: TranslationJob.ID, buffer: ProcessingBuffer) async {
        let updates = await buffer.drain(jobID: jobID)
        guard !updates.isEmpty else { return }
        await MainActor.run { [weak self] in
            self?.applyUpdates(jobID: jobID, updates: updates)
        }
    }

    private func pendingItemsSnapshot(jobID: TranslationJob.ID) async -> [TranslationJobItem] {
        await MainActor.run { [weak self] in
            self?.jobs
                .first { $0.id == jobID }?
                .items
                .filter { $0.status == .pendingEvaluation || $0.status == .pending } ?? []
        }
    }

    nonisolated private func processItemsOnBackground(
        jobID: TranslationJob.ID,
        items: [TranslationJobItem],
        provider: AIProviderConfig,
        aiTextService: AITextService,
        buffer: ProcessingBuffer
    ) async {
        let gate = ConcurrencyGate(max: Self.maxConcurrency)
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                if Task.isCancelled { return }
                await gate.enter()
                if Task.isCancelled {
                    await gate.leave()
                    return
                }
                group.addTask {
                    await self.processItemOffMain(
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

    nonisolated private func processItemOffMain(
        jobID: TranslationJob.ID,
        item: TranslationJobItem,
        provider: AIProviderConfig,
        aiTextService: AITextService,
        buffer: ProcessingBuffer
    ) async {
        guard !Task.isCancelled else { return }
        var currentStatus = item.status

        if currentStatus == .pendingEvaluation {
            await buffer.record(jobID: jobID, update: ItemUpdate(
                itemID: item.id, status: .evaluating,
                translatedChinese: nil, errorMessage: nil
            ))

            do {
                let results = try await retry(maxRetries: Self.maxRetryCount) {
                    try await aiTextService.evaluateSentenceValue([item.targetEnglish], using: provider)
                }
                guard let isValuable = results.first else {
                    throw AITextServiceError.emptyResponse
                }
                guard !Task.isCancelled else { return }
                if isValuable {
                    currentStatus = .pending
                    await buffer.record(jobID: jobID, update: ItemUpdate(
                        itemID: item.id, status: .pending,
                        translatedChinese: nil, errorMessage: nil
                    ))
                } else {
                    await buffer.record(jobID: jobID, update: ItemUpdate(
                        itemID: item.id, status: .discarded,
                        translatedChinese: nil, errorMessage: nil
                    ))
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
                await buffer.record(jobID: jobID, update: ItemUpdate(
                    itemID: item.id, status: .evaluationFailed,
                    translatedChinese: nil, errorMessage: error.localizedDescription
                ))
                return
            }
        }

        if currentStatus != .pending { return }
        if Task.isCancelled { return }

        await buffer.record(jobID: jobID, update: ItemUpdate(
            itemID: item.id, status: .translating,
            translatedChinese: nil, errorMessage: nil
        ))

        do {
            let translations = try await retry(maxRetries: Self.maxRetryCount) {
                try await aiTextService.translateEnglishToChinese([item.targetEnglish], using: provider)
            }
            let translation = translations.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if translation.isEmpty { throw AITextServiceError.emptyResponse }
            guard !Task.isCancelled else { return }
            await buffer.record(jobID: jobID, update: ItemUpdate(
                itemID: item.id, status: .translated,
                translatedChinese: translation, errorMessage: nil
            ))
        } catch {
            guard !Task.isCancelled else { return }
            await buffer.record(jobID: jobID, update: ItemUpdate(
                itemID: item.id, status: .failed,
                translatedChinese: nil, errorMessage: error.localizedDescription
            ))
        }
    }

    nonisolated private func retry<T>(maxRetries: Int, operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
                }
            }
        }
        throw lastError ?? AITextServiceError.invalidResponse
    }

    // MARK: - Completion (runs on MainActor)

    private func finishJob(jobID: TranslationJob.ID, buffer: ProcessingBuffer) async {
        let pendingUpdates = await buffer.drain(jobID: jobID)
        if !pendingUpdates.isEmpty {
            applyUpdates(jobID: jobID, updates: pendingUpdates)
        }
        updateJob(jobID) { job in
            job.processingStartedAt = nil
            let nonDiscarded = job.items.filter { $0.status != .discarded }
            if nonDiscarded.isEmpty {
                job.status = .failed
                job.errorMessage = "没有可用的题目。"
            } else if nonDiscarded.allSatisfy({ $0.status == .translated }) {
                job.status = .completed
                job.errorMessage = nil
            } else if nonDiscarded.contains(where: { $0.status == .failed || $0.status == .evaluationFailed }) {
                job.status = .failed
            } else {
                job.status = .ready
            }
        }
        stopSyncTimerIfIdle()
        saveJobsInBackground()
    }

    private func markPaused(jobID: TranslationJob.ID) async {
        let pendingUpdates = await buffer.drain(jobID: jobID)
        if !pendingUpdates.isEmpty {
            applyUpdates(jobID: jobID, updates: pendingUpdates)
        }
        updateJob(jobID) { job in
            job.status = .paused
            job.processingStartedAt = nil
            for index in job.items.indices {
                if job.items[index].status == .translating {
                    job.items[index].status = .pending
                }
                if job.items[index].status == .evaluating {
                    job.items[index].status = .pendingEvaluation
                }
            }
        }
        stopSyncTimerIfIdle()
        saveJobsInBackground()
    }

    private func markImportFailed(jobID: TranslationJob.ID, message: String) {
        updateJob(jobID) { job in
            job.status = .failed
            job.errorMessage = message
        }
        importTasks[jobID] = nil
        saveJobsInBackground()
    }

    // MARK: - Helpers

    private func hasPendingItems(jobID: TranslationJob.ID) -> Bool {
        jobs
            .first { $0.id == jobID }?
            .items
            .contains { $0.status == .pendingEvaluation || $0.status == .pending } == true
    }

    private func updateJob(_ jobID: TranslationJob.ID, mutate: (inout TranslationJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        mutate(&jobs[index])
        jobs[index].updatedAt = Date()
    }
}

private func updateItem(
    _ itemID: TranslationJobItem.ID,
    in job: inout TranslationJob,
    mutate: (inout TranslationJobItem) -> Void
) {
    guard let index = job.items.firstIndex(where: { $0.id == itemID }) else { return }
    mutate(&job.items[index])
}

private actor ConcurrencyGate {
    private let max: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(max: Int) { self.max = max }

    func enter() async {
        if running < max { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        running -= 1
        if let next = waiters.first {
            waiters.removeFirst()
            running += 1
            next.resume()
        }
    }
}
