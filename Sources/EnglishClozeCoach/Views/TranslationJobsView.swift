import SwiftUI

struct TranslationJobsView: View {
    @ObservedObject var jobStore: TranslationJobStore
    @ObservedObject var practiceStore: PracticeStore
    @ObservedObject var aiStore: AIProviderStore
    var onOpenPractice: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            jobList
                .frame(width: 280)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("任务")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .padding(.top, 18)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(jobStore.jobs) { job in
                        Button {
                            jobStore.selectedJobID = job.id
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.name)
                                    .font(.headline)
                                    .lineLimit(1)

                                HStack {
                                    Text(statusTitle(job.status))
                                    Spacer()
                                    Text(job.progressText)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                ProgressView(
                                    value: Double(job.translatedCount),
                                    total: Double(max(job.items.count, 1))
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
            }
        }
    }

    private func jobDetail(_ job: TranslationJob) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    value: Double(job.translatedCount),
                    total: Double(max(job.items.count, 1))
                )
                HStack {
                    Text(statusTitle(job.status))
                    Text("已翻译 \(job.translatedCount)")
                    Text("失败 \(job.failedCount)")
                    Text("总计 \(job.items.count)")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
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
        HStack {
            if job.canPause {
                Button {
                    jobStore.pause(jobID: job.id)
                } label: {
                    Label("暂停", systemImage: "pause")
                }
            }

            if job.canStart {
                Button {
                    jobStore.startTranslation(jobID: job.id, provider: aiStore.activeProvider)
                } label: {
                    Label("开始", systemImage: "play")
                }
            }

            if job.failedCount > 0 {
                Button {
                    jobStore.retryFailed(jobID: job.id, provider: aiStore.activeProvider)
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
            }

            Button {
                saveJob(job)
            } label: {
                Label("导入题库", systemImage: "tray.and.arrow.down")
            }
            .disabled(job.items.isEmpty || job.status == .importing || job.status == .translating)

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
            jobStore.deleteJob(job.id)
            onOpenPractice()
        }
    }

    private func statusTitle(_ status: TranslationJobStatus) -> String {
        switch status {
        case .importing:
            return "导入中"
        case .ready:
            return "待翻译"
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
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
    }

    private func statusColor(_ status: TranslationJobItemStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .translating:
            return .blue
        case .translated:
            return .green
        case .failed:
            return .red
        }
    }
}
