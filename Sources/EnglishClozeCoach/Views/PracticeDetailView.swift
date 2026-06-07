import Foundation
import SwiftUI

struct PracticeDetailView: View {
    let item: PracticeItem
    @ObservedObject var store: PracticeStore
    let explanation: String?
    let isExplaining: Bool

    var body: some View {
        VStack(spacing: 36) {
            Text(item.sourceChinese)
                .font(.system(size: 40, weight: .semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 10, lineSpacing: 18) {
                ForEach(Array(item.segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case let .text(text):
                        Text(text)
                            .font(.system(size: 34, weight: .medium))
                            .fixedSize()
                    case let .blank(blank):
                        ClozeBlankField(blank: blank, store: store)
                    }
                }
            }
            .frame(maxWidth: 900)

            explanationArea
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: explanation)
        .animation(.easeInOut(duration: 0.18), value: isExplaining)
    }

    @ViewBuilder
    private var explanationArea: some View {
        if isExplaining {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("解释中")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .transition(.opacity)
        } else if let explanation, !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1)

                ScrollView {
                    MarkdownExplanationText(markdown: explanation)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 340)
            }
            .frame(maxWidth: 1040)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

private struct MarkdownExplanationText: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.blocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .heading:
                    Text(inlineMarkdown(block.text))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                case .paragraph:
                    Text(inlineMarkdown(block.text))
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(5)
                        .foregroundStyle(.secondary)
                case .listItem:
                    Text(inlineMarkdown(block.text))
                        .font(.system(size: 17, weight: .regular))
                        .lineSpacing(5)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let cleanedText = text
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (try? AttributedString(
            markdown: cleanedText,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(cleanedText)
    }
}

private struct MarkdownBlock: Hashable {
    enum Kind: Hashable {
        case heading
        case paragraph
        case listItem
    }

    let kind: Kind
    let text: String

    static func blocks(from markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !paragraph.isEmpty {
                blocks.append(MarkdownBlock(kind: .paragraph, text: paragraph))
            }
            paragraphLines.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            if let heading = headingText(from: line) {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .heading, text: heading))
            } else if let listItem = listItemText(from: line) {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .listItem, text: listItem))
            } else {
                paragraphLines.append(line)
            }
        }

        flushParagraph()
        return blocks
    }

    private static func headingText(from line: String) -> String? {
        let markerCount = line.prefix { $0 == "#" }.count
        guard markerCount > 0, markerCount <= 4 else {
            return nil
        }
        return line.dropFirst(markerCount)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func listItemText(from line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let pattern = #"^\d+[.)]\s+"#
        guard let range = line.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
