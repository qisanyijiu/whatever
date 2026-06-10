import SwiftUI

struct ContentView: View {
    private enum Page: Hashable {
        case practice
        case libraries
        case records
        case ai
        case jobs
        case dictation
    }

    @ObservedObject var store: PracticeStore
    @ObservedObject var sessionStore: UserSessionStore
    @ObservedObject var studyStore: StudyStore
    @ObservedObject var aiStore: AIProviderStore
    @ObservedObject var translationJobStore: TranslationJobStore
    @State private var isImporting = false
    @State private var page: Page = .practice
    @State private var celebrationItemID: PracticeItem.ID?
    @State private var celebratedItemIDs = Set<PracticeItem.ID>()
    @State private var celebrationTask: Task<Void, Never>?
    @State private var recordedMistakeBlankIDs = Set<String>()
    @State private var attemptMistakesByItemID: [PracticeItem.ID: Set<ClozeBlank.ID>] = [:]
    @State private var explanationText: String?
    @State private var isExplaining = false
    @State private var explanationTask: Task<Void, Never>?

    private let speechService = SpeechService()
    private let aiTextService = AITextService()

    private var isCelebrating: Bool {
        celebrationItemID != nil
    }

    var body: some View {
        ZStack {
            if page == .libraries {
                LibraryOverviewView(store: store, studyStore: studyStore)
                    .transition(.opacity)
            } else if page == .records {
                StudyDashboardView(studyStore: studyStore, practiceStore: store) {
                    page = .practice
                }
                    .transition(.opacity)
            } else if page == .ai {
                AISettingsView(aiStore: aiStore)
                    .transition(.opacity)
            } else if page == .jobs {
                TranslationJobsView(
                    jobStore: translationJobStore,
                    practiceStore: store,
                    aiStore: aiStore
                ) {
                    page = .practice
                }
                    .transition(.opacity)
            } else if page == .dictation, let item = store.selectedItem {
                DictationPracticeView(item: item, speechService: speechService)
                    .transition(.opacity)
            } else if isCelebrating {
                CelebrationView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let item = store.selectedItem {
                PracticeDetailView(
                    item: item,
                    store: store,
                    explanation: explanationText,
                    isExplaining: isExplaining
                )
            } else {
                Text("待导入")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .animation(.easeInOut(duration: 0.24), value: isCelebrating)
        .animation(.easeInOut(duration: 0.18), value: page)
        .onChange(of: store.answers) {
            recordMistakesIfNeeded()
            startCelebrationIfNeeded()
            clearExplanation()
        }
        .onChange(of: store.selectedItemID) {
            recordedMistakeBlankIDs.removeAll()
            clearExplanation()
        }
        .onChange(of: page) {
            if page == .libraries {
                store.refreshLibrarySummaries(studyData: studyStore.data)
            }
            if page != .practice {
                clearExplanation()
            }
        }
        .onDisappear {
            celebrationTask?.cancel()
            explanationTask?.cancel()
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("页面", selection: $page) {
                    Text("练习").tag(Page.practice)
                    Text("题库").tag(Page.libraries)
                    Text("记录").tag(Page.records)
                    Text("AI").tag(Page.ai)
                    Text("任务").tag(Page.jobs)
                }
                .pickerStyle(.segmented)
                .disabled(isCelebrating)
                .help("切换页面")

                Button {
                    page = .dictation
                } label: {
                    Label("听写", systemImage: "waveform")
                }
                .disabled(isCelebrating || store.selectedItem == nil)
                .help("当前题听写/跟读")

                Button {
                    isImporting = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .disabled(isCelebrating)
                .help("导入英文内容")

                Button {
                    store.returnToSelectedDeck()
                    page = .practice
                } label: {
                    Label("当前题库", systemImage: "rectangle.stack")
                }
                .disabled(isCelebrating)
                .help("返回当前题库练习")

                Button {
                    if let item = store.selectedItem {
                        speechService.speak(item.targetEnglish)
                    }
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2")
                }
                .disabled(page != .practice || isCelebrating || store.selectedItem == nil)
                .help("朗读当前英文")

                Button {
                    explainSelectedItem()
                } label: {
                    if isExplaining {
                        ProgressView()
                            .controlSize(.small)
                        Text("解释中")
                    } else {
                        Label("解释", systemImage: "lightbulb")
                    }
                }
                .disabled(page != .practice || isCelebrating || store.selectedItem == nil || isExplaining)
                .help("查看当前题解释")

                Button {
                    store.goBack()
                } label: {
                    Label("上一题", systemImage: "chevron.left")
                }
                .disabled(page != .practice || isCelebrating || !store.canGoBack)
                .help("上一题")

                Button {
                    store.advance()
                } label: {
                    Label("下一题", systemImage: "chevron.right")
                }
                .disabled(page != .practice || isCelebrating || !store.canAdvance)
                .help("下一题")

                Button {
                    store.resetCurrentAnswers()
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                }
                .disabled(page != .practice || isCelebrating || store.selectedItem == nil)
                .help("重置当前题")

                Button {
                    sessionStore.logout()
                } label: {
                    Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(isCelebrating)
                .help("退出登录")
            }
        }
        .sheet(isPresented: $isImporting) {
            ImportView(
                store: store,
                aiStore: aiStore,
                translationJobStore: translationJobStore
            ) {
                page = .jobs
            }
        }
    }

    private func startCelebrationIfNeeded() {
        guard page == .practice,
              let item = store.selectedItem else {
            return
        }

        guard store.isCompleted(item) else {
            celebratedItemIDs.remove(item.id)
            return
        }

        guard celebrationItemID == nil,
              !celebratedItemIDs.contains(item.id) else {
            return
        }

        let wrongBlankCount = attemptMistakesByItemID[item.id]?.count ?? 0
        studyStore.recordCompletion(item: item, wrongBlankCount: wrongBlankCount)
        store.refreshLibrarySummaries(studyData: studyStore.data)
        attemptMistakesByItemID[item.id] = []
        celebratedItemIDs.insert(item.id)
        celebrationItemID = item.id
        celebrationTask?.cancel()
        celebrationTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard celebrationItemID == item.id else {
                    return
                }

                celebrationItemID = nil
                if store.selectedItemID == item.id {
                    store.advance()
                }
            }
        }
    }

    private func recordMistakesIfNeeded() {
        guard page == .practice,
              let item = store.selectedItem else {
            return
        }

        for blank in item.blanks where store.answerState(for: blank) == .incorrect {
            let wrongAnswer = store.answerText(for: blank)
            guard shouldRecordMistake(wrongAnswer: wrongAnswer, expectedAnswer: blank.answer) else {
                continue
            }

            let key = "\(item.id)-\(blank.id)"
            guard !recordedMistakeBlankIDs.contains(key) else {
                continue
            }

            recordedMistakeBlankIDs.insert(key)
            attemptMistakesByItemID[item.id, default: []].insert(blank.id)
            studyStore.recordMistake(item: item, blank: blank, wrongAnswer: wrongAnswer)
            store.refreshLibrarySummaries(studyData: studyStore.data)
        }
    }

    private func shouldRecordMistake(wrongAnswer: String, expectedAnswer: String) -> Bool {
        let normalizedWrongAnswer = wrongAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExpectedAnswer = expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalizedWrongAnswer.isEmpty && normalizedWrongAnswer.count >= normalizedExpectedAnswer.count
    }

    private func explainSelectedItem() {
        guard let item = store.selectedItem else {
            return
        }

        let answers = store.answers
        guard let provider = aiStore.activeProvider, provider.isReady else {
            explanationText = store.explanationForSelectedItem()
            return
        }

        explanationTask?.cancel()
        isExplaining = true
        explanationText = nil
        explanationTask = Task {
            do {
                let explanation = try await aiTextService.explainAnswer(for: item, answers: answers, using: provider)
                await MainActor.run {
                    guard store.selectedItemID == item.id else {
                        return
                    }
                    explanationText = explanation
                    isExplaining = false
                    explanationTask = nil
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else {
                        return
                    }
                    guard store.selectedItemID == item.id else {
                        return
                    }
                    let fallback = store.explanationForSelectedItem() ?? "暂无解释。"
                    explanationText = "### AI 解释失败\n\(error.localizedDescription)\n\n\(fallback)"
                    isExplaining = false
                    explanationTask = nil
                }
            }
        }
    }

    private func clearExplanation() {
        explanationTask?.cancel()
        explanationTask = nil
        explanationText = nil
        isExplaining = false
    }
}
