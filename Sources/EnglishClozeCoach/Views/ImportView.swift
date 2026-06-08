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
    @State private var isReadingFolder = false
    @State private var draftItems: [ImportDraftItem] = []
    @State private var isPreviewing = false
    @State private var isTranslating = false

    private let tedDownloader = TEDTranscriptDownloader()
    private let scriptDownloader = ScriptTextDownloader()
    private let folderImporter = FolderTextImporter()
    private let aiTextService = AITextService()

    private var isDownloadingContent: Bool {
        isDownloadingTED || isDownloadingScript || isReadingFolder
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
                    chooseTextFile()
                } label: {
                    Label("选择 .txt/.srt/.vtt", systemImage: "doc")
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
                VStack(spacing: 18) {
                    ForEach($draftItems) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("中文提示", text: $item.sourceChinese)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    draftItems.removeAll { $0.id == item.id }
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

            messageView

            HStack {
                Button("返回") {
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
                        Label("AI 翻译中文", systemImage: "sparkles")
                    }
                }
                .disabled(isTranslating || draftItems.isEmpty)
                .help("使用当前选中的 AI 翻译中文提示")

                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button {
                    saveDraft()
                } label: {
                    Label("保存题库", systemImage: "tray.and.arrow.down")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(draftItems.isEmpty)
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

    private func chooseTextFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let subtitleTypes = ["srt", "vtt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = [.plainText, .text] + subtitleTypes

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let fileText = try String(contentsOf: url, encoding: .utf8)
            text = scriptDownloader.preparedText(from: fileText, sourceHint: url.pathExtension) ?? fileText
            sourceLabel = url.lastPathComponent
            if deckName == "导入题库" {
                deckName = url.deletingPathExtension().lastPathComponent
            }
            message = nil
        } catch {
            message = "无法读取文件：\(error.localizedDescription)"
        }
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

        do {
            let result = try folderImporter.importText(from: url)
            text = result.text
            sourceLabel = result.sourceLabel
            if deckName == "导入题库" || deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                deckName = result.folderName
            }
            isReadingFolder = false
            generatePreview()
        } catch {
            isReadingFolder = false
            message = "无法导入文件夹：\(error.localizedDescription)"
        }
    }

    private func generatePreview() {
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
        draftItems = draft.items
        isPreviewing = true
        let aiHint = aiStore.activeProvider?.isReady == true ? "可用当前 AI 翻译中文提示。" : "中文提示可手动编辑，或先到 AI 页配置接口。"
        message = "已生成 \(draft.items.count) 道题，可先编辑再保存。\(aiHint)"
    }

    private func saveDraft() {
        let count = store.saveImportDraft(
            ImportDraft(name: deckName, source: sourceLabel, items: draftItems)
        )
        if count > 0 {
            dismiss()
        } else {
            message = store.importError ?? "没有保存题目。"
        }
    }

    private func translateDraftItems() {
        guard let provider = aiStore.activeProvider, provider.isReady else {
            message = "请先在 AI 页面配置并选择一个可用接口。"
            return
        }

        let englishSentences = draftItems.map(\.targetEnglish)
        guard !englishSentences.isEmpty else {
            message = "没有可翻译的题目。"
            return
        }

        isTranslating = true
        message = "正在使用 \(provider.name) 翻译中文提示..."

        Task {
            do {
                let translations = try await aiTextService.translateEnglishToChinese(englishSentences, using: provider)
                await MainActor.run {
                    for index in draftItems.indices where index < translations.count {
                        draftItems[index].sourceChinese = translations[index]
                    }
                    isTranslating = false
                    message = "AI 已翻译 \(translations.count) 条中文提示，可继续编辑后保存。"
                }
            } catch {
                await MainActor.run {
                    isTranslating = false
                    message = "AI 翻译失败：\(error.localizedDescription)"
                }
            }
        }
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
