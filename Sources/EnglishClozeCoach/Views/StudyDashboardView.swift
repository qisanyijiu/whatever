import SwiftUI

struct StudyDashboardView: View {
    @ObservedObject var studyStore: StudyStore
    let totalItemCount: Int

    private var progressText: String {
        "\(studyStore.completedCount) / \(totalItemCount) 题"
    }

    private var progressValue: Double {
        guard totalItemCount > 0 else {
            return 0
        }
        return Double(studyStore.completedCount) / Double(totalItemCount)
    }

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Text("记录")
                    .font(.system(size: 42, weight: .semibold))

                Text(progressText)
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                ProgressView(value: progressValue)
                    .frame(width: 360)
            }

            VStack(spacing: 34) {
                HistorySection(entries: studyStore.recentHistory)
                MistakeSection(records: studyStore.frequentMistakes)
            }
            .frame(maxWidth: 760)

            if let saveError = studyStore.saveError {
                Text(saveError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct HistorySection: View {
    let entries: [PracticeHistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "历史", value: "\(entries.count)")

            if entries.isEmpty {
                EmptyStateText("暂无完成记录")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HistoryRow(entry: entry)

                        if index < entries.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct MistakeSection: View {
    let records: [MistakeRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "易错", value: "\(records.count)")

            if records.isEmpty {
                EmptyStateText("暂无易错题")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        MistakeRow(record: record)

                        if index < records.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: PracticeHistoryEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.sourceChinese)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)

                Text(entry.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.wrongBlankCount == 0 ? "无错" : "\(entry.wrongBlankCount) 错")
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(entry.wrongBlankCount == 0 ? .green : .red)
        }
        .padding(.vertical, 12)
    }
}

private struct MistakeRow: View {
    let record: MistakeRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.sourceChinese)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)

                Text("\(record.lastWrongAnswer) -> \(record.answer)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(record.mistakeCount) 次")
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.red)
        }
        .padding(.vertical, 12)
    }
}

private struct SectionHeader: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .semibold))

            Spacer()

            Text(value)
                .font(.system(size: 17, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyStateText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
