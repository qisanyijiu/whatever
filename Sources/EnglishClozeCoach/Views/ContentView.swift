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
    @ObservedObject var systemTranslator: SystemTranslationCoordinator
    @State private var isImporting = false
    @State private var page: Page = .practice
    @StateObject private var practiceWorkflow = PracticeWorkflowCoordinator()
    @StateObject private var jobAutomation = TranslationJobAutomationCoordinator()

    private let speechService = SpeechService()

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
            } else if practiceWorkflow.isCelebrating {
                CelebrationView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if page == .dictation, let item = store.selectedItem {
                DictationPracticeView(item: item, speechService: speechService, studyStore: studyStore) {
                    practiceWorkflow.completeDictationItem(item, store: store, studyStore: studyStore)
                }
                    .transition(.opacity)
            } else if let item = store.selectedItem {
                PracticeDetailView(
                    item: item,
                    store: store,
                    studyStore: studyStore,
                    explanation: practiceWorkflow.explanationText,
                    isExplaining: practiceWorkflow.isExplaining
                )
            } else {
                Text("待导入")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay {
            if #available(macOS 15.0, *) {
                SystemTranslationTaskView(coordinator: systemTranslator)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: practiceWorkflow.isCelebrating)
        .animation(.easeInOut(duration: 0.18), value: page)
        .onChange(of: store.answers) {
            if let completedItem = practiceWorkflow.answersChanged(
                isPracticePage: page == .practice,
                store: store,
                studyStore: studyStore
            ) {
                speechService.speak(completedItem.targetEnglish)
            }
        }
        .onChange(of: store.selectedItemID) {
            practiceWorkflow.selectedItemChanged()
        }
        .onChange(of: page) {
            if page == .libraries {
                store.refreshLibrarySummaries(studyData: studyStore.data)
            }
            practiceWorkflow.pageChanged(isPracticePage: page == .practice)
        }
        .onChange(of: translationJobStore.jobs) {
            syncTranslationJobAutomation()
        }
        .onAppear {
            syncTranslationJobAutomation()
        }
        .onDisappear {
            practiceWorkflow.cancel()
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("练习", selection: $page) {
                    Text("练习").tag(Page.practice)
                    Text("听写").tag(Page.dictation)
                    Text("记录").tag(Page.records)
                }
                .pickerStyle(.segmented)
                .disabled(practiceWorkflow.isCelebrating)
                .help("切换练习、听写和记录")
            }

            ToolbarItemGroup {
                Picker("题库", selection: $page) {
                    Text("题库").tag(Page.libraries)
                    Text("任务").tag(Page.jobs)
                }
                .pickerStyle(.segmented)
                .disabled(practiceWorkflow.isCelebrating)
                .help("切换题库和任务")

                Button {
                    isImporting = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .disabled(practiceWorkflow.isCelebrating)
                .help("导入英文内容")
            }

            ToolbarItemGroup {
                Button {
                    if let item = store.selectedItem {
                        speechService.speak(item.targetEnglish)
                    }
                } label: {
                    Label("朗读", systemImage: AppToolbarSymbols.speak)
                }
                .disabled(
                    (page != .practice && page != .dictation)
                        || practiceWorkflow.isCelebrating
                        || store.selectedItem == nil
                )
                .help("朗读当前英文")

                Button {
                    if let item = store.selectedItem {
                        studyStore.recordHintViewed(item: item)
                    }
                    practiceWorkflow.explainSelectedItem(store: store, aiStore: aiStore)
                } label: {
                    if practiceWorkflow.isExplaining {
                        ProgressView()
                            .controlSize(.small)
                        Text("提示中")
                    } else {
                        Label("提示", systemImage: AppToolbarSymbols.hint)
                    }
                }
                .disabled(page != .practice || practiceWorkflow.isCelebrating || store.selectedItem == nil || practiceWorkflow.isExplaining)
                .help("查看当前题提示")
            }

            ToolbarItemGroup {
                Button {
                    store.goBack()
                } label: {
                    Label("后退", systemImage: "chevron.left")
                }
                .disabled(page != .practice || practiceWorkflow.isCelebrating || !store.canGoBack)
                .help("后退到上一题")

                Button {
                    recordSkipIfNeeded()
                    store.advance()
                } label: {
                    Label("前进", systemImage: "chevron.right")
                }
                .disabled(page != .practice || practiceWorkflow.isCelebrating || !store.canAdvance)
                .help("前进到下一题")

                Button {
                    store.resetCurrentAnswers()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(page != .practice || practiceWorkflow.isCelebrating || store.selectedItem == nil)
                .help("刷新当前题")

                Button {
                    sessionStore.logout()
                } label: {
                    Label("退出", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(practiceWorkflow.isCelebrating)
                .help("退出登录")
            }
        }
        .sheet(isPresented: $isImporting) {
            ImportView(
                store: store,
                aiStore: aiStore,
                translationJobStore: translationJobStore,
                systemTranslator: systemTranslator
            ) {
                page = .jobs
            }
        }
    }

    private func syncTranslationJobAutomation() {
        jobAutomation.sync(
            jobStore: translationJobStore,
            practiceStore: store,
            systemTranslator: systemTranslator
        )
    }

    private func recordSkipIfNeeded() {
        guard let item = store.selectedItem,
              !store.isCompleted(item) else {
            return
        }
        studyStore.recordSkip(item: item)
    }
}
