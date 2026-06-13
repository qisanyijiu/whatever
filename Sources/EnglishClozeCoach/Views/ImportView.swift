import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @ObservedObject var store: PracticeStore
    @ObservedObject var aiStore: AIProviderStore
    @ObservedObject var translationJobStore: TranslationJobStore
    @ObservedObject var systemTranslator: SystemTranslationCoordinator
    var onJobCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var deckName = "导入题库"
    @State private var sourceLabel = "粘贴文本"
    @State private var tedURL = ""
    @State private var scriptURL = ""
    @State private var message: String?
    @State private var isDownloadingTED = false
    @State private var isDownloadingScript = false
    @State private var isReadingFiles = false
    @State private var isReadingFolder = false
    @State private var isSavingFilesToDatabase = false
    @State private var isSavingFolderToDatabase = false
    @State private var draftItems: [ImportDraftItem] = []
    @State private var isPreviewing = false
    @State private var isTranslating = false
    @State private var translatingItemIDs = Set<ImportDraftItem.ID>()
    @State private var translationFailedItemIDs = Set<ImportDraftItem.ID>()
    @State private var translationCompletedCount = 0
    @State private var translationTotalCount = 0
    @State private var systemTranslationCompletedCount = 0
    @State private var systemTranslationTotalCount = 0
    @State private var systemTranslationFailureCount = 0
    @State private var activeTranslationRunID: UUID?
    @State private var translationTask: Task<Void, Never>?
    @State private var localDatabaseImportTask: Task<Void, Never>?
    @State private var tedDownloadTask: Task<Void, Never>?
    @State private var scriptDownloadTask: Task<Void, Never>?

    private let tedDownloader = TEDTranscriptDownloader()
    private let scriptDownloader = ScriptTextDownloader()
    private let folderImporter = FolderTextImporter()
    private let aiTextService = AITextService()
    private let localDatabaseImportWorkflow = LocalFileDatabaseImportWorkflow()
    private let importBatchByteLimit = 512 * 1024

    private var importableContentTypes: [UTType] {
        [.plainText, .text] + FolderTextImporter.importableFileExtensions
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }
    }

    private var isDownloadingContent: Bool {
        isDownloadingTED
            || isDownloadingScript
            || isReadingFiles
            || isReadingFolder
            || isSavingFilesToDatabase
            || isSavingFolderToDatabase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isPreviewing ? "确认题库" : "导入英文内容")
                .font(.title2)
                .fontWeight(.semibold)

            if isPreviewing {
                previewContent
            } else {
                sourceContent
            }
        }
        .padding(24)
        .frame(width: isPreviewing ? 860 : 760, height: isPreviewing ? 680 : 640)
        .onDisappear {
            translationTask?.cancel()
            localDatabaseImportTask?.cancel()
            tedDownloadTask?.cancel()
            scriptDownloadTask?.cancel()
        }
    }

    private var sourceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("题库名称", text: $deckName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                TextField("TED 演讲链接", text: $tedURL)
                    .textFieldStyle(.roundedBorder)

                Button {
                    downloadTEDAndPreview()
                } label: {
                    if isDownloadingTED {
                        ProgressView()
                            .controlSize(.small)
                        Text("下载中")
                    } else {
                        Label("下载 TED 文稿并创建任务", systemImage: "captions.bubble")
                    }
                }
                .disabled(isDownloadingContent || tedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("字幕/台词链接（.srt / .vtt / .txt）", text: $scriptURL)
                    .textFieldStyle(.roundedBorder)

                Button {
                    downloadScriptAndPreview()
                } label: {
                    if isDownloadingScript {
                        ProgressView()
                            .controlSize(.small)
                        Text("下载中")
                    } else {
                        Label("下载台词并创建任务", systemImage: "text.quote")
                    }
                }
                .disabled(isDownloadingContent || scriptURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
            }

            messageView
            systemTranslationProgressView

            VStack(spacing: 10) {
                HStack {
                    Button {
                        chooseTextFiles()
                    } label: {
                        if isReadingFiles {
                            ProgressView()
                                .controlSize(.small)
                            Text("读取中")
                        } else {
                            Label("选择多个本地文件", systemImage: "doc.on.doc")
                        }
                    }
                    .disabled(isDownloadingContent)

                    Button {
                        chooseFolder()
                    } label: {
                        if isReadingFolder {
                            ProgressView()
                                .controlSize(.small)
                            Text("读取中")
                        } else {
                            Label("选择文件夹", systemImage: "folder")
                        }
                    }
                    .disabled(isDownloadingContent)

                    Button {
                        importTextFilesToDatabase()
                    } label: {
                        if isSavingFilesToDatabase {
                            ProgressView()
                                .controlSize(.small)
                            Text("入库中")
                        } else {
                            Label("本地文件入库", systemImage: "externaldrive.badge.plus")
                        }
                    }
                    .disabled(isDownloadingContent)

                    Button {
                        importFolderToDatabase()
                    } label: {
                        if isSavingFolderToDatabase {
                            ProgressView()
                                .controlSize(.small)
                            Text("入库中")
                        } else {
                            Label("文件夹入库", systemImage: "folder.badge.plus")
                        }
                    }
                    .disabled(isDownloadingContent)

                    Spacer(minLength: 0)
                }

                HStack {
                    Spacer()

                    Button("取消") {
                        dismiss()
                    }

                    Button {
                        generatePreview()
                    } label: {
                        Label("创建任务", systemImage: "tray.and.arrow.down")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("题库名称", text: $deckName)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach($draftItems) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("中文提示", text: $item.sourceChinese)
                                    .textFieldStyle(.roundedBorder)

                                translationStatus(for: item)

                                Button {
                                    draftItems.removeAll { $0.id == item.id }
                                    translationFailedItemIDs.remove(item.id)
                                    translatingItemIDs.remove(item.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("删除这题")
                            }

                            TextField("目标英文", text: $item.targetEnglish)
                                .textFieldStyle(.roundedBorder)

                            TextField("挖空词，用逗号分隔", text: $item.blankText)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 6)

                        Divider()
                    }
                }
            }
            .frame(minHeight: 440)

            translationProgressView
            messageView

            HStack {
                Button("返回") {
                    cancelTranslation()
                    isPreviewing = false
                }

                Button {
                    translateDraftItems()
                } label: {
                    if isTranslating {
                        ProgressView()
                            .controlSize(.small)
                        Text("翻译中")
                    } else {
                        Label(translationFailedItemIDs.isEmpty ? "AI 翻译中文" : "重新翻译全部", systemImage: "sparkles")
                    }
                }
                .disabled(isTranslating || draftItems.isEmpty)
                .help("使用当前选中的 AI 翻译中文提示")

                if !translationFailedItemIDs.isEmpty {
                    Button {
                        retryFailedTranslations()
                    } label: {
                        Label("重试失败", systemImage: "arrow.clockwise")
                    }
                    .disabled(isTranslating)
                    .help("只重试翻译失败的题目")
                }

                Spacer()

                Button("取消") {
                    cancelTranslation()
                    dismiss()
                }

                Button {
                    saveDraft()
                } label: {
                    Label("保存题库", systemImage: "tray.and.arrow.down")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(draftItems.isEmpty || isTranslating)
            }
        }
    }

    @ViewBuilder
    private var translationProgressView: some View {
        if isTranslating, translationTotalCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(
                    value: Double(translationCompletedCount),
                    total: Double(translationTotalCount)
                )
                Text("正在自动翻译 \(translationCompletedCount)/\(translationTotalCount)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if !translationFailedItemIDs.isEmpty {
            HStack(spacing: 10) {
                Text("\(translationFailedItemIDs.count) 条中文提示翻译失败，可重试或手动编辑。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    retryFailedTranslations()
                } label: {
                    Label("重试失败", systemImage: "arrow.clockwise")
                }
                .disabled(isTranslating)
            }
        }
    }

    @ViewBuilder
    private var systemTranslationProgressView: some View {
        if (isSavingFilesToDatabase || isSavingFolderToDatabase), systemTranslationTotalCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(
                    value: Double(systemTranslationCompletedCount),
                    total: Double(systemTranslationTotalCount)
                )
                Text(systemTranslationFailureCount > 0
                    ? "正在使用 macOS 系统翻译 \(systemTranslationCompletedCount)/\(systemTranslationTotalCount)，失败 \(systemTranslationFailureCount)"
                    : "正在使用 macOS 系统翻译 \(systemTranslationCompletedCount)/\(systemTranslationTotalCount)"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var messageView: some View {
        if let message {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func translationStatus(for item: ImportDraftItem) -> some View {
        if translatingItemIDs.contains(item.id) {
            ProgressView()
                .controlSize(.small)
                .help("正在翻译这条中文提示")
        } else if translationFailedItemIDs.contains(item.id) {
            Button {
                retryTranslation(for: item.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .disabled(isTranslating)
            .help("重试这条翻译")
        }
    }

    private func chooseTextFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "选择多个文件"
        panel.message = "可一次选择多个英文文本、字幕或网页文本文件。"
        panel.allowedContentTypes = importableContentTypes

        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            return
        }

        isReadingFiles = true
        message = "正在读取本地文件..."

        let jobID = translationJobStore.importFiles(
            panel.urls,
            name: deckName,
            provider: aiStore.activeProvider
        )
        translationJobStore.selectedJobID = jobID
        isReadingFiles = false
        onJobCreated()
        dismiss()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择文件夹"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isReadingFolder = true
        message = "正在读取文件夹..."

        let jobID = translationJobStore.importFolder(
            url,
            name: deckName,
            provider: aiStore.activeProvider
        )
        translationJobStore.selectedJobID = jobID
        isReadingFolder = false
        onJobCreated()
        dismiss()
    }

    private func importTextFilesToDatabase() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "本地文件入库"
        panel.message = "选择后会直接生成题目并写入 SQLite 数据库。"
        panel.allowedContentTypes = importableContentTypes

        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            return
        }

        isSavingFilesToDatabase = true
        message = "正在写入数据库..."

        let accessTokens = panel.urls.map { url in
            (url: url, didStartAccessing: url.startAccessingSecurityScopedResource())
        }
        defer {
            accessTokens
                .filter(\.didStartAccessing)
                .forEach { $0.url.stopAccessingSecurityScopedResource() }
        }

        do {
            let draft = try LocalFilePracticeDraftImporter(maximumBatchByteCount: importBatchByteLimit)
                .importDraft(fromFiles: panel.urls, name: deckName)
            saveLocalFileDraftToDatabase(draft) {
                isSavingFilesToDatabase = false
            }
        } catch {
            isSavingFilesToDatabase = false
            message = "本地文件入库失败：\(error.localizedDescription)"
        }
    }

    private func importFolderToDatabase() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "文件夹入库"
        panel.message = "选择后会直接生成题目并写入 SQLite 数据库。"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isSavingFolderToDatabase = true
        message = "正在写入数据库..."

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let draft = try LocalFilePracticeDraftImporter(maximumBatchByteCount: importBatchByteLimit)
                .importDraft(fromFolder: url, name: deckName)
            saveLocalFileDraftToDatabase(draft) {
                isSavingFolderToDatabase = false
            }
        } catch {
            isSavingFolderToDatabase = false
            message = "本地文件入库失败：\(error.localizedDescription)"
        }
    }

    private func saveLocalFileDraftToDatabase(_ draft: ImportDraft, finish: @escaping () -> Void) {
        systemTranslationCompletedCount = 0
        systemTranslationFailureCount = 0
        systemTranslationTotalCount = draft.items.count
        message = "正在使用 macOS 系统翻译：0/\(draft.items.count)"

        localDatabaseImportTask?.cancel()
        localDatabaseImportTask = Task { @MainActor in
            defer {
                finish()
                systemTranslationCompletedCount = 0
                systemTranslationTotalCount = 0
                localDatabaseImportTask = nil
            }

            do {
                let result = try await localDatabaseImportWorkflow.translatedDraft(
                    from: draft,
                    systemTranslator: systemTranslator
                ) { completedCount, totalCount, failedCount in
                    systemTranslationCompletedCount = completedCount
                    systemTranslationFailureCount = failedCount
                    message = failedCount > 0
                        ? "正在使用 macOS 系统翻译：\(completedCount)/\(totalCount)，失败 \(failedCount)"
                        : "正在使用 macOS 系统翻译：\(completedCount)/\(totalCount)"
                }
                let count = store.saveImportDraft(result.draft)
                if count > 0 {
                    if result.failedCount > 0 {
                        message = "已入库 \(count) 题，\(result.failedCount) 题系统翻译失败，未写入数据库。"
                    } else {
                        dismiss()
                    }
                } else {
                    message = result.failedCount > 0
                        ? "macOS 系统翻译失败：没有成功翻译的题目。"
                        : store.importError ?? "没有保存题目。"
                }
            } catch {
                message = "macOS 系统翻译失败：\(error.localizedDescription)"
            }
        }
    }

    private func generatePreview() {
        let jobID = translationJobStore.importText(
            text,
            name: deckName,
            source: sourceLabel,
            provider: aiStore.activeProvider
        )
        translationJobStore.selectedJobID = jobID
        onJobCreated()
        dismiss()
    }

    private func saveDraft() {
        guard !isTranslating else {
            message = "正在翻译中文提示，请完成后再保存。"
            return
        }

        let count = store.saveImportDraft(
            ImportDraft(name: deckName, source: sourceLabel, items: draftItems)
        )
        if count > 0 {
            dismiss()
        } else {
            message = store.importError ?? "没有保存题目。"
        }
    }

    private func translateDraftItems(automatic: Bool = false) {
        translateItems(draftItems, automatic: automatic)
    }

    private func retryFailedTranslations() {
        let failedItems = draftItems.filter { translationFailedItemIDs.contains($0.id) }
        translateItems(failedItems, automatic: false)
    }

    private func retryTranslation(for itemID: ImportDraftItem.ID) {
        let items = draftItems.filter { $0.id == itemID }
        translateItems(items, automatic: false)
    }

    private func translateItems(_ items: [ImportDraftItem], automatic: Bool) {
        guard let provider = aiStore.activeProvider, provider.isReady else {
            message = "请先在 AI 页面配置并选择一个可用接口。"
            return
        }

        let itemsToTranslate = items.filter {
            !$0.targetEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !itemsToTranslate.isEmpty else {
            message = "没有可翻译的题目。"
            return
        }

        let runID = UUID()
        activeTranslationRunID = runID
        isTranslating = true
        translationCompletedCount = 0
        translationTotalCount = itemsToTranslate.count
        translatingItemIDs = Set(itemsToTranslate.map(\.id))
        translationFailedItemIDs.subtract(translatingItemIDs)
        message = automatic
            ? "正在使用 \(provider.name) 自动翻译中文提示：0/\(itemsToTranslate.count)"
            : "正在使用 \(provider.name) 翻译中文提示：0/\(itemsToTranslate.count)"

        translationTask?.cancel()
        translationTask = Task {
            var lastError: Error?

            for item in itemsToTranslate {
                do {
                    let translations = try await aiTextService.translateEnglishToChinese(
                        [item.targetEnglish],
                        using: provider
                    )
                    guard let translation = translations.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !translation.isEmpty else {
                        throw AITextServiceError.emptyResponse
                    }
                    await MainActor.run {
                        guard activeTranslationRunID == runID else {
                            return
                        }
                        applyTranslation(translation, to: item.id)
                        translatingItemIDs.remove(item.id)
                        translationCompletedCount += 1
                        message = "正在使用 \(provider.name) 翻译中文提示：\(translationCompletedCount)/\(translationTotalCount)"
                    }
                } catch {
                    lastError = error
                    await MainActor.run {
                        guard activeTranslationRunID == runID else {
                            return
                        }
                        translatingItemIDs.remove(item.id)
                        translationFailedItemIDs.insert(item.id)
                        translationCompletedCount += 1
                        message = "正在使用 \(provider.name) 翻译中文提示：\(translationCompletedCount)/\(translationTotalCount)"
                    }
                }
            }

            await MainActor.run {
                guard activeTranslationRunID == runID else {
                    return
                }
                isTranslating = false
                translatingItemIDs.removeAll()
                activeTranslationRunID = nil

                if translationFailedItemIDs.isEmpty {
                    message = "AI 已翻译 \(translationCompletedCount) 条中文提示，可继续编辑后保存。"
                } else if let lastError {
                    message = "\(translationFailedItemIDs.count) 条翻译失败：\(lastError.localizedDescription)"
                } else {
                    message = "\(translationFailedItemIDs.count) 条翻译失败，可重试或手动编辑。"
                }
            }
        }
    }

    private func applyTranslation(_ translation: String, to itemID: ImportDraftItem.ID) {
        guard let index = draftItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        var updatedItems = draftItems
        updatedItems[index].sourceChinese = translation
        draftItems = updatedItems
    }

    private func cancelTranslation() {
        activeTranslationRunID = nil
        isTranslating = false
        translatingItemIDs.removeAll()
        translationFailedItemIDs.removeAll()
        translationCompletedCount = 0
        translationTotalCount = 0
    }

    private func downloadTEDAndPreview() {
        let urlText = tedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlText.isEmpty else {
            return
        }

        isDownloadingTED = true
        message = "正在下载 TED 文稿..."

        tedDownloadTask?.cancel()
        tedDownloadTask = Task {
            do {
                let transcript = try await tedDownloader.downloadTranscript(from: urlText)
                await MainActor.run {
                    text = transcript
                    sourceLabel = urlText
                    if deckName == "导入题库" {
                        deckName = "TED 文稿"
                    }
                    isDownloadingTED = false
                    generatePreview()
                }
            } catch {
                await MainActor.run {
                    isDownloadingTED = false
                    message = "无法下载 TED 文稿：\(error.localizedDescription)"
                }
            }
        }
    }

    private func downloadScriptAndPreview() {
        let urlText = scriptURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlText.isEmpty else {
            return
        }

        isDownloadingScript = true
        message = "正在下载台词..."

        scriptDownloadTask?.cancel()
        scriptDownloadTask = Task {
            do {
                let scriptText = try await scriptDownloader.downloadText(from: urlText)
                await MainActor.run {
                    text = scriptText
                    sourceLabel = urlText
                    if deckName == "导入题库" {
                        deckName = "台词题库"
                    }
                    isDownloadingScript = false
                    generatePreview()
                }
            } catch {
                await MainActor.run {
                    isDownloadingScript = false
                    message = "无法下载台词：\(error.localizedDescription)"
                }
            }
        }
    }
}
