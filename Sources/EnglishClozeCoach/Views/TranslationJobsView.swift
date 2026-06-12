import SwiftUI

struct TranslationJobsView: View {
    @ObservedObject var jobStore: TranslationJobStore
    @ObservedObject var practiceStore: PracticeStore
    @ObservedObject var aiStore: AIProviderStore
    var onOpenPractice: () -> Void

    @State private var selectedCategory: StatusCategory?

    private enum StatusCategory: String, CaseIterable {
        case inProgress
        case completed
        case waiting
        case failed

        var label: String {
            switch self {
            case .inProgress: return "进行中"
            case .completed: return "已完成"
            case .waiting: return "等待中"
            case .failed: return "失败"
            }
        }

        func contains(_ status: TranslationJobStatus) -> Bool {
            switch self {
            case .inProgress:
                return status == .importing || status == .evaluating || status == .translating
            case .completed:
                return status == .completed
            case .waiting:
                return status == .ready || status == .paused
            case .failed:
                return status == .failed
            }
        }
    }

    private var inProgressJobs: [TranslationJob] {
        jobStore.jobs.filter { StatusCategory.inProgress.contains($0.status) }
    }

    private var completedJobs: [TranslationJob] {
        jobStore.jobs.filter { StatusCategory.completed.contains($0.status) }
    }

    private var waitingJobs: [TranslationJob] {
        jobStore.jobs.filter { StatusCategory.waiting.contains($0.status) }
    }

    private var failedJobs: [TranslationJob] {
        jobStore.jobs.filter { StatusCategory.failed.contains($0.status) }
    }

    private var filteredJobs: [TranslationJob] {
        guard let category = selectedCategory else {
            return jobStore.jobs
        }
        return jobStore.jobs.filter { category.contains($0.status) }
    }

    private var statCards: [(label: String, icon: String, count: Int, color: Color)] {
        var inProgress = 0
        var completed = 0
        var waiting = 0
        var failed = 0

        for job in jobStore.jobs {
            let summary = job.progressSummary
            inProgress += summary.activeCount
            completed += summary.translatedCount
            waiting += summary.waitingCount
            failed += summary.failedCount
        }

        return [
            ("进行中", "arrow.triangle.2.circlepath", inProgress, .blue),
            ("已完成", "checkmark.circle", completed, .green),
            ("等待中", "clock", waiting, .orange),
            ("失败", "xmark.circle", failed, .red)
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            jobList
                .frame(width: 300)
                .background(.quaternary.opacity(0.2))

            Divider()

            if let job = jobStore.selectedJob {
                jobDetail(job)
            } else {
                ContentUnavailableView("暂无任务", systemImage: "tray")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("任务")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

            statsDashboard
                .padding(.horizontal, 10)

            filterChips
                .padding(.horizontal, 10)
                .padding(.top, 10)

            Divider()
                .padding(.top, 10)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredJobs) { job in
                        let summary = job.progressSummary
                        Button {
                            jobStore.selectedJobID = job.id
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.name)
                                    .font(.headline)
                                    .lineLimit(1)

                                HStack {
                                    Text(statusTitle(job.status))
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(statusColor(job.status).opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Spacer()
                                    Text(summary.progressText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                ProgressView(
                                    value: Double(summary.processedCount),
                                    total: Double(max(summary.totalCount, 1))
                                )
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(job.id == jobStore.selectedJobID ? Color.accentColor.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private var statsDashboard: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(Array(statCards.enumerated()), id: \.element.label) { _, card in
                VStack(spacing: 2) {
                    Text("\(card.count)")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(card.color)

                    HStack(spacing: 3) {
                        Image(systemName: card.icon)
                            .font(.system(size: 9))
                        Text(card.label)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(card.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "全部", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(StatusCategory.allCases, id: \.rawValue) { category in
                    FilterChip(label: category.label, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    private func jobDetail(_ job: TranslationJob) -> some View {
        let summary = job.progressSummary

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(job.source)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                actionBar(job)
            }

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(
                    value: Double(summary.processedCount),
                    total: Double(max(summary.totalCount, 1))
                )
                HStack {
                    Text(statusTitle(job.status))
                    Text("已处理 \(summary.processedCount)")
                    Text("失败 \(summary.failedCount)")
                    if summary.discardedCount > 0 {
                        Text("待丢弃 \(summary.discardedCount)")
                    }
                    Text("总计 \(summary.totalCount)")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                if let startedAt = job.processingStartedAt {
                    EstimatedRemainingView(
                        startedAt: startedAt,
                        processedCount: summary.processedCount,
                        itemsCompletedAtStart: job.itemsCompletedAtStart,
                        totalCount: summary.totalCount
                    )
                }
            }

            if let errorMessage = job.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(job.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                statusDot(item.status)
                                Text(item.targetEnglish)
                                    .font(.body)
                                    .lineLimit(2)
                                Spacer()
                            }

                            Text(item.effectiveChinese)
                                .font(.callout)
                                .foregroundStyle(item.translatedChinese == nil ? .secondary : .primary)

                            if let errorMessage = item.errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 8)

                        Divider()
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionBar(_ job: TranslationJob) -> some View {
        let summary = job.progressSummary

        return HStack {
            if job.canPause && !job.isLocalFileSource {
                Button {
                    jobStore.pause(jobID: job.id)
                } label: {
                    Label("暂停", systemImage: "pause")
                }
            }

            if job.canStart && !job.isLocalFileSource {
                Button {
                    jobStore.startTranslation(jobID: job.id, provider: aiStore.activeProvider)
                } label: {
                    Label("开始", systemImage: "play")
                }
            }

            if summary.failedCount > 0 && !job.isLocalFileSource {
                Button {
                    jobStore.retryFailed(jobID: job.id, provider: aiStore.activeProvider)
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
            }

            if summary.failedCount > 0 && job.isLocalFileSource {
                Button {
                    jobStore.retrySystemTranslation(jobID: job.id)
                } label: {
                    Label("重试系统翻译", systemImage: "arrow.clockwise")
                }
            }

            if summary.discardedCount > 0 {
                Button {
                    jobStore.confirmDiscard(jobID: job.id)
                } label: {
                    Label("确认丢弃", systemImage: "trash.slash")
                }
            }

            Button {
                saveJob(job)
            } label: {
                if job.importedToLibraryAt == nil {
                    Label(job.isLocalFileSource ? "转入数据库" : "导入题库", systemImage: "tray.and.arrow.down")
                } else {
                    Label("已入库", systemImage: "checkmark.circle")
                }
            }
            .disabled(!job.canImportToLibrary)
            .help(job.isLocalFileSource ? "将本地文件生成的题目写入 SQLite 数据库" : "将任务题目写入题库")

            Button {
                jobStore.deleteJob(job.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func saveJob(_ job: TranslationJob) {
        guard let draft = jobStore.importDraft(for: job.id) else {
            return
        }

        let savedCount = practiceStore.saveImportDraft(draft)
        if savedCount > 0 {
            jobStore.markImportedToLibrary(jobID: job.id)
            onOpenPractice()
        }
    }

    private func statusTitle(_ status: TranslationJobStatus) -> String {
        switch status {
        case .importing:
            return "导入中"
        case .ready:
            return "待处理"
        case .evaluating:
            return "评估中"
        case .translating:
            return "翻译中"
        case .paused:
            return "已暂停"
        case .completed:
            return "已完成"
        case .failed:
            return "有失败"
        }
    }

    private func statusDot(_ status: TranslationJobItemStatus) -> some View {
        Circle()
            .fill(itemStatusColor(status))
            .frame(width: 8, height: 8)
    }

    private func itemStatusColor(_ status: TranslationJobItemStatus) -> Color {
        switch status {
        case .pendingEvaluation, .pending:
            return .secondary
        case .evaluating:
            return .orange
        case .translating:
            return .blue
        case .translated:
            return .green
        case .discarded:
            return .brown
        case .evaluationFailed:
            return .orange.opacity(0.8)
        case .failed:
            return .red
        }
    }

    private func statusColor(_ status: TranslationJobStatus) -> Color {
        switch status {
        case .importing:
            return .purple
        case .ready:
            return .secondary
        case .evaluating:
            return .orange
        case .translating:
            return .blue
        case .paused:
            return .secondary
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct EstimatedRemainingView: View {
    let startedAt: Date
    let processedCount: Int
    let itemsCompletedAtStart: Int
    let totalCount: Int

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            if let eta = estimatedSecondsRemaining(now: context.date) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("预计剩余 \(formatETA(eta))")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.blue)
            }
        }
    }

    private func estimatedSecondsRemaining(now: Date) -> Int? {
        guard processedCount > itemsCompletedAtStart else {
            return nil
        }
        let elapsed = max(now.timeIntervalSince(startedAt), 1)
        let completed = processedCount - itemsCompletedAtStart
        let rate = Double(completed) / elapsed
        let remaining = max(totalCount - processedCount, 0)
        guard remaining > 0 else {
            return nil
        }
        return Int(Double(remaining) / rate)
    }

    private func formatETA(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes < 60 {
            return secs > 0 ? "\(minutes) 分 \(secs) 秒" : "\(minutes) 分钟"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins > 0 ? "\(hours) 时 \(mins) 分" : "\(hours) 小时"
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
