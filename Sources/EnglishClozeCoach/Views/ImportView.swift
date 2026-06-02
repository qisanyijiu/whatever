import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @ObservedObject var store: PracticeStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入英文内容")
                .font(.title2)
                .fontWeight(.semibold)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 260)
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
                    Label("选择 .txt", systemImage: "doc")
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
        .frame(width: 660, height: 440)
    }

    private func chooseTextFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.plainText, .text]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            text = try String(contentsOf: url, encoding: .utf8)
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
}
