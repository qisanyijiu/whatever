import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @ObservedObject var store: PracticeStore
    @ObservedObject var aiStore: AIProviderStore
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
    @State private var draftItems: [ImportDraftItem] = []
    @State private var isPreviewing = false
    @State private var isTranslating = false
    @State private var translatingItemIDs = Set<ImportDraftItem.ID>()
    @State private var translationFailedItemIDs = Set<ImportDraftItem.ID>()
    @State private var translationCompletedCount = 0
    @State private var translationTotalCount = 0
    @State private var activeTranslationRunID: UUID?

    private let tedDownloader = TEDTranscriptDownloader()
    private let scriptDownloader = ScriptTextDownloader()
    private let folderImporter = FolderTextImporter()
    private let aiTextService = AITextService()
    private let importBatchByteLimit = 512 * 1024

    private var isDownloadingContent: Bool {
        isDownloadingTED || isDownloadingScript || isReadingFiles || isReadingFolder
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
        .frame(width: isPreviewing ? 860 : 680, height: isPreviewing ? 680 : 580)
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
                        Label("下载 TED 文稿并预览", systemImage: "captions.bubble")
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
                        Label("下载台词并预览", systemImage: "text.quote")
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

                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button {
                    generatePreview()
                } label: {
                    Label("生成预览", systemImage: "wand.and.stars")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        let localTypes = ["srt", "vtt", "md", "markdown", "html", "htm", "text"]
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = [.plainText, .text] + localTypes

        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            return
        }

        isReadingFiles = true
        message = "正在读取本地文件..."

        let accessTokens = panel.urls.map { url in
            (url: url, didStartAccessing: url.startAccessingSecurityScopedResource())
        }
        defer {
            accessTokens
                .filter(\.didStartAccessing)
                .forEach { $0.url.stopAccessingSecurityScopedResource() }
        }

        importTextBatches(
            source: .files(panel.urls),
            loadingFailurePrefix: "无法导入本地文件"
        )
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

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        importTextBatches(
            source: .folder(url),
            loadingFailurePrefix: "无法导入文件夹"
        )
    }

    private enum BatchImportSource {
        case files([URL])
        case folder(URL)
    }

    private func importTextBatches(source: BatchImportSource, loadingFailurePrefix: String) {
        cancelTranslation()

        do {
            let result = try generateDraftItems(from: source)
            guard !result.items.isEmpty else {
                isReadingFiles = false
                isReadingFolder = false
                message = "没有生成题目。"
                return
            }

            text = ""
            sourceLabel = result.summary.sourceLabel
            if deckName == "导入题库" || deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deckName = result.summary.folderName
            }
            isReadingFiles = false
            isReadingFolder = false
            finishGeneratedPreview(
                items: result.items,
                messagePrefix: "已从 \(result.summary.fileCount) 个英文文件生成 \(result.items.count) 道题。"
            )
        } catch {
            isReadingFiles = false
            isReadingFolder = false
            message = "\(loadingFailurePrefix)：\(error.localizedDescription)"
        }
    }

    private func generateDraftItems(
        from source: BatchImportSource
    ) throws -> (summary: FolderImportSummary, items: [ImportDraftItem]) {
        var items: [ImportDraftItem] = []
        let handleBatch: (FolderImportBatch) throws -> Void = { batch in
            if let draft = store.prepareImportDraft(
                text: batch.text,
                name: deckName,
                source: sourceLabel
            ) {
                items.append(contentsOf: draft.items)
            }
        }

        let summary: FolderImportSummary
        switch source {
        case let .files(urls):
            summary = try folderImporter.importTextBatches(
                fromFiles: urls,
                maximumBatchByteCount: importBatchByteLimit,
                handleBatch: handleBatch
            )
        case let .folder(url):
            summary = try folderImporter.importTextBatches(
                from: url,
                maximumBatchByteCount: importBatchByteLimit,
                handleBatch: handleBatch
            )
        }
        return (summary, items)
    }

    private func generatePreview() {
        cancelTranslation()

        guard let draft = store.prepareImportDraft(
            text: text,
            name: deckName,
            source: sourceLabel
        ) else {
            message = store.importError ?? "没有生成题目。"
            return
        }

        deckName = draft.name
        sourceLabel = draft.source
        finishGeneratedPreview(
            items: draft.items,
            messagePrefix: "已生成 \(draft.items.count) 道题。"
        )
    }

    private func finishGeneratedPreview(items: [ImportDraftItem], messagePrefix: String) {
        draftItems = items
        isPreviewing = true
        if aiStore.activeProvider?.isReady == true {
            message = "\(messagePrefix)正在自动翻译中文提示。"
            translateDraftItems(automatic: true)
        } else {
            message = "\(messagePrefix)中文提示可手动编辑，或先到 AI 页配置接口。"
        }
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

        Task {
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

        Task {
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

        Task {
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
