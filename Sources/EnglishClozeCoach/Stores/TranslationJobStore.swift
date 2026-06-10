import Foundation

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
        saveJobs()
    }

    var selectedJob: TranslationJob? {
        guard let selectedJobID else {
            return jobs.first
        }
        return jobs.first { $0.id == selectedJobID } ?? jobs.first
    }

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

    func startTranslation(jobID: TranslationJob.ID, provider: AIProviderConfig?) {
        guard translationTasks[jobID] == nil else {
            return
        }
        guard hasPendingTranslationItems(jobID: jobID) else {
            return
        }
        guard let provider, provider.isReady else {
            updateJob(jobID) { job in
                job.status = .failed
                job.errorMessage = "请先在 AI 页面配置并选择一个可用接口。"
            }
            return
        }

        updateJob(jobID) { job in
            job.providerID = provider.id
            job.status = .translating
            job.errorMessage = nil
            for index in job.items.indices where job.items[index].status == .translating {
                job.items[index].status = .pending
            }
        }

        let aiTextService = self.aiTextService
        let task = Task.detached(priority: .utility) { [weak self] in
            if let self {
                await self.runTranslation(jobID: jobID, provider: provider, aiTextService: aiTextService)
            }
        }
        translationTasks[jobID] = task
    }

    func pause(jobID: TranslationJob.ID) {
        guard jobs.first(where: { $0.id == jobID })?.canPause == true else {
            return
        }
        importTasks[jobID]?.cancel()
        importTasks[jobID] = nil
        translationTasks[jobID]?.cancel()
        translationTasks[jobID] = nil
        updateJob(jobID) { job in
            job.status = .paused
            for index in job.items.indices where job.items[index].status == .translating {
                job.items[index].status = .pending
            }
        }
    }

    func retryFailed(jobID: TranslationJob.ID, provider: AIProviderConfig?) {
        updateJob(jobID) { job in
            for index in job.items.indices where job.items[index].status == .failed {
                job.items[index].status = .pending
                job.items[index].errorMessage = nil
            }
            job.status = .ready
            job.errorMessage = nil
        }
        startTranslation(jobID: jobID, provider: provider)
    }

    func deleteJob(_ jobID: TranslationJob.ID) {
        importTasks[jobID]?.cancel()
        translationTasks[jobID]?.cancel()
        importTasks[jobID] = nil
        translationTasks[jobID] = nil
        jobs.removeAll { $0.id == jobID }
        selectedJobID = jobs.first?.id
        saveJobs()
    }

    func importDraft(for jobID: TranslationJob.ID) -> ImportDraft? {
        guard let job = jobs.first(where: { $0.id == jobID }), !job.items.isEmpty else {
            return nil
        }
        return ImportDraft(
            id: job.id,
            name: job.name,
            source: job.source,
            items: job.items.map { item in
                ImportDraftItem(
                    id: item.id,
                    sourceChinese: item.effectiveChinese,
                    targetEnglish: item.targetEnglish,
                    blankText: item.blankText
                )
            }
        )
    }

    private static func restoredJobs(from jobs: [TranslationJob]) -> [TranslationJob] {
        jobs.map { job in
            var restoredJob = job
            if restoredJob.status == .importing || restoredJob.status == .translating {
                restoredJob.status = .paused
            }
            for index in restoredJob.items.indices where restoredJob.items[index].status == .translating {
                restoredJob.items[index].status = .pending
            }
            return restoredJob
        }
    }

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
            errorMessage: nil
        )
        jobs.insert(job, at: 0)
        selectedJobID = job.id
        saveJobs()
        return job
    }

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
                if Task.isCancelled {
                    throw CancellationError()
                }
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
    ) {
        guard !Task.isCancelled else {
            markPaused(jobID: jobID)
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
                    status: .pending,
                    errorMessage: nil
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

    private func runTranslation(
        jobID: TranslationJob.ID,
        provider: AIProviderConfig,
        aiTextService: AITextService
    ) async {
        while true {
            guard let item = nextTranslatableItem(jobID: jobID) else {
                finishTranslation(jobID: jobID)
                translationTasks[jobID] = nil
                return
            }
            if Task.isCancelled {
                markPaused(jobID: jobID)
                translationTasks[jobID] = nil
                return
            }

            markItemTranslating(jobID: jobID, itemID: item.id)
            do {
                let translations = try await aiTextService.translateEnglishToChinese(
                    [item.targetEnglish],
                    using: provider
                )
                let translation = translations.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if translation.isEmpty {
                    throw AITextServiceError.emptyResponse
                }
                markItemTranslated(jobID: jobID, itemID: item.id, translation: translation)
            } catch {
                markItemFailed(jobID: jobID, itemID: item.id, message: error.localizedDescription)
            }
        }
    }

    private func nextTranslatableItem(jobID: TranslationJob.ID) -> TranslationJobItem? {
        jobs
            .first { $0.id == jobID }?
            .items
            .first { $0.status == .pending }
    }

    private func hasPendingTranslationItems(jobID: TranslationJob.ID) -> Bool {
        jobs
            .first { $0.id == jobID }?
            .items
            .contains { $0.status == .pending } == true
    }

    private func markPaused(jobID: TranslationJob.ID) {
        updateJob(jobID) { job in
            job.status = .paused
            for index in job.items.indices where job.items[index].status == .translating {
                job.items[index].status = .pending
            }
        }
    }

    private func markImportFailed(jobID: TranslationJob.ID, message: String) {
        updateJob(jobID) { job in
            job.status = .failed
            job.errorMessage = message
        }
        importTasks[jobID] = nil
    }

    private func markItemTranslating(jobID: TranslationJob.ID, itemID: TranslationJobItem.ID) {
        updateJob(jobID) { job in
            job.status = .translating
            updateItem(itemID, in: &job) { item in
                item.status = .translating
                item.errorMessage = nil
            }
        }
    }

    private func markItemTranslated(jobID: TranslationJob.ID, itemID: TranslationJobItem.ID, translation: String) {
        updateJob(jobID) { job in
            updateItem(itemID, in: &job) { item in
                item.translatedChinese = translation
                item.status = .translated
                item.errorMessage = nil
            }
        }
    }

    private func markItemFailed(jobID: TranslationJob.ID, itemID: TranslationJobItem.ID, message: String) {
        updateJob(jobID) { job in
            updateItem(itemID, in: &job) { item in
                item.status = .failed
                item.errorMessage = message
            }
        }
    }

    private func finishTranslation(jobID: TranslationJob.ID) {
        updateJob(jobID) { job in
            if job.items.isEmpty {
                job.status = .failed
                job.errorMessage = "没有生成题目。"
            } else if job.items.allSatisfy({ $0.status == .translated }) {
                job.status = .completed
                job.errorMessage = nil
            } else if job.items.contains(where: { $0.status == .failed }) {
                job.status = .failed
            } else {
                job.status = .ready
            }
        }
    }

    private func updateJob(_ jobID: TranslationJob.ID, mutate: (inout TranslationJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }
        mutate(&jobs[index])
        jobs[index].updatedAt = Date()
        saveJobs()
    }

    private func saveJobs() {
        do {
            try library.save(jobs)
            errorMessage = nil
        } catch {
            errorMessage = "保存翻译任务失败：\(error.localizedDescription)"
        }
    }
}

private func updateItem(
    _ itemID: TranslationJobItem.ID,
    in job: inout TranslationJob,
    mutate: (inout TranslationJobItem) -> Void
) {
    guard let index = job.items.firstIndex(where: { $0.id == itemID }) else {
        return
    }
    mutate(&job.items[index])
}
