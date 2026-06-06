import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @ObservedObject var store: PracticeStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var tedURL = ""
    @State private var scriptURL = ""
    @State private var message: String?
    @State private var isDownloadingTED = false
    @State private var isDownloadingScript = false

    private let tedDownloader = TEDTranscriptDownloader()
    private let scriptDownloader = ScriptTextDownloader()

    private var isDownloadingContent: Bool {
        isDownloadingTED || isDownloadingScript
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入英文内容")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                TextField("TED 演讲链接", text: $tedURL)
                    .textFieldStyle(.roundedBorder)

                Button {
                    downloadTEDAndGenerate()
                } label: {
                    if isDownloadingTED {
                        ProgressView()
                            .controlSize(.small)
                        Text("下载中")
                    } else {
                        Label("下载 TED 文稿并生成题目", systemImage: "captions.bubble")
                    }
                }
                .disabled(isDownloadingContent || tedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("字幕/台词链接（.srt / .vtt / .txt）", text: $scriptURL)
                    .textFieldStyle(.roundedBorder)

                Button {
                    downloadScriptAndGenerate()
                } label: {
                    if isDownloadingScript {
                        ProgressView()
                            .controlSize(.small)
                        Text("下载中")
                    } else {
                        Label("下载台词并生成题目", systemImage: "text.quote")
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

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    chooseTextFile()
                } label: {
                    Label("选择 .txt/.srt/.vtt", systemImage: "doc")
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button {
                    generateItems()
                } label: {
                    Label("生成题目", systemImage: "wand.and.stars")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 680, height: 580)
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
            message = nil
        } catch {
            message = "无法读取文件：\(error.localizedDescription)"
        }
    }

    private func generateItems() {
        let count = store.importText(text)
        if count > 0 {
            dismiss()
        } else {
            message = store.importError ?? "没有生成题目。"
        }
    }

    private func downloadTEDAndGenerate() {
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
                    let count = store.importText(transcript)
                    isDownloadingTED = false
                    if count > 0 {
                        dismiss()
                    } else {
                        message = store.importError ?? "TED 文稿已下载，但没有生成题目。"
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloadingTED = false
                    message = "无法下载 TED 文稿：\(error.localizedDescription)"
                }
            }
        }
    }

    private func downloadScriptAndGenerate() {
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
                    let count = store.importText(scriptText)
                    isDownloadingScript = false
                    if count > 0 {
                        dismiss()
                    } else {
                        message = store.importError ?? "台词已下载，但没有生成题目。"
                    }
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
