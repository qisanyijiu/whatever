import SwiftUI

struct StudyDashboardView: View {
    @ObservedObject var studyStore: StudyStore
    @ObservedObject var practiceStore: PracticeStore
    let onStartPractice: () -> Void

    private var progressText: String {
        "\(studyStore.completedCount) / \(practiceStore.allItems.count) 题"
    }

    private var progressValue: Double {
        guard !practiceStore.allItems.isEmpty else {
            return 0
        }
        return Double(studyStore.completedCount) / Double(practiceStore.allItems.count)
    }

    private var dueItems: [PracticeItem] {
        studyStore.dueItems(from: practiceStore.allItems)
    }

    private var mistakeItems: [PracticeItem] {
        studyStore.mistakeItems(from: practiceStore.allItems)
    }

    var body: some View {
        VStack(spacing: 34) {
            VStack(spacing: 12) {
                Text("记录")
                    .font(.system(size: 42, weight: .semibold))

                Text(progressText)
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                ProgressView(value: progressValue)
                    .frame(width: 360)

                VStack(spacing: 6) {
                    HStack {
                        Text("今日目标")
                        Spacer()
                        Text("\(studyStore.todayCompletedCount) / \(studyStore.data.dailyGoal)")
                            .monospacedDigit()
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    ProgressView(value: studyStore.dailyGoalProgress)
                }
                .frame(width: 360)
            }

            HStack(spacing: 36) {
                MetricBlock(title: "今日完成", value: "\(studyStore.todayCompletedCount)")
                MetricBlock(title: "今日复习", value: "\(dueItems.count)")
                MetricBlock(title: "连续学习", value: "\(studyStore.currentStreak) 天")
                MetricBlock(title: "易错题", value: "\(mistakeItems.count)")
            }

            HStack(spacing: 14) {
                Stepper("每日目标 \(studyStore.data.dailyGoal) 题", value: dailyGoalBinding, in: 1...200)
                    .frame(width: 190)

                Toggle("每日提醒", isOn: reminderEnabledBinding)
                    .toggleStyle(.checkbox)

                DatePicker("时间", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!studyStore.data.reminderEnabled)
                    .frame(width: 96)

                Button {
                    practiceStore.startCustomPractice(items: dueItems, title: "今日复习", studyData: studyStore.data)
                    onStartPractice()
                } label: {
                    Label("练今日复习", systemImage: "calendar.badge.clock")
                }
                .disabled(dueItems.isEmpty)

                Button {
                    practiceStore.startCustomPractice(items: mistakeItems, title: "错题复习", studyData: studyStore.data)
                    onStartPractice()
                } label: {
                    Label("练错题", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                }
                .disabled(mistakeItems.isEmpty)
            }

            VStack(spacing: 34) {
                WeeklySection(summaries: studyStore.weeklySummaries, dailyGoal: studyStore.data.dailyGoal)
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

    private var dailyGoalBinding: Binding<Int> {
        Binding(
            get: { studyStore.data.dailyGoal },
            set: { studyStore.updateDailyGoal($0) }
        )
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { studyStore.data.reminderEnabled },
            set: { studyStore.updateDailyReminder(enabled: $0) }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = studyStore.data.reminderHour
                components.minute = studyStore.data.reminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { studyStore.updateReminderTime($0) }
        )
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()

            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 110)
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

private struct WeeklySection: View {
    let summaries: [WeeklyStudySummary]
    let dailyGoal: Int

    private var maxCompletedCount: Int {
        max(dailyGoal, summaries.map(\.completedCount).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "本周", value: "\(summaries.reduce(0) { $0 + $1.completedCount })")

            HStack(alignment: .bottom, spacing: 24) {
                ForEach(summaries) { summary in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(summary.isToday ? Color.accentColor : Color.secondary.opacity(0.26))
                            .frame(
                                width: 28,
                                height: max(8, 92 * Double(summary.completedCount) / Double(maxCompletedCount))
                            )

                        Text(summary.label)
                            .font(.caption)
                            .foregroundStyle(summary.isToday ? .primary : .secondary)

                        Text("\(summary.completedCount)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 136)
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
