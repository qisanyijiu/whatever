import Foundation

@MainActor
final class PracticeWorkflowCoordinator: ObservableObject {
    @Published private(set) var celebrationItemID: PracticeItem.ID?
    @Published private(set) var explanationText: String?
    @Published private(set) var isExplaining = false

    private var celebratedItemIDs = Set<PracticeItem.ID>()
    private var celebrationTask: Task<Void, Never>?
    private var recordedMistakeBlankIDs = Set<String>()
    private var attemptMistakesByItemID: [PracticeItem.ID: Set<ClozeBlank.ID>] = [:]
    private var explanationTask: Task<Void, Never>?
    private let aiTextService: AITextService

    init(aiTextService: AITextService = AITextService()) {
        self.aiTextService = aiTextService
    }

    var isCelebrating: Bool {
        celebrationItemID != nil
    }

    @discardableResult
    func answersChanged(
        isPracticePage: Bool,
        store: PracticeStore,
        studyStore: StudyStore
    ) -> PracticeItem? {
        recordMistakesIfNeeded(isPracticePage: isPracticePage, store: store, studyStore: studyStore)
        let completedItem = startCelebrationIfNeeded(
            isPracticePage: isPracticePage,
            store: store,
            studyStore: studyStore
        )
        clearExplanation()
        return completedItem
    }

    func selectedItemChanged() {
        recordedMistakeBlankIDs.removeAll()
        clearExplanation()
    }

    func pageChanged(isPracticePage: Bool) {
        if !isPracticePage {
            clearExplanation()
        }
    }

    func cancel() {
        celebrationTask?.cancel()
        explanationTask?.cancel()
    }

    func explainSelectedItem(store: PracticeStore, aiStore: AIProviderStore) {
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

    func completeDictationItem(
        _ item: PracticeItem,
        store: PracticeStore,
        studyStore: StudyStore
    ) {
        guard store.selectedItemID == item.id else {
            return
        }
        _ = startCompletionCelebration(
            for: item,
            wrongBlankCount: 0,
            store: store,
            studyStore: studyStore
        )
    }

    private func startCelebrationIfNeeded(
        isPracticePage: Bool,
        store: PracticeStore,
        studyStore: StudyStore
    ) -> PracticeItem? {
        guard isPracticePage,
              let item = store.selectedItem else {
            return nil
        }

        guard store.isCompleted(item) else {
            celebratedItemIDs.remove(item.id)
            return nil
        }

        let wrongBlankCount = attemptMistakesByItemID[item.id]?.count ?? 0
        return startCompletionCelebration(
            for: item,
            wrongBlankCount: wrongBlankCount,
            store: store,
            studyStore: studyStore
        )
    }

    private func startCompletionCelebration(
        for item: PracticeItem,
        wrongBlankCount: Int,
        store: PracticeStore,
        studyStore: StudyStore
    ) -> PracticeItem? {
        guard celebrationItemID == nil,
              !celebratedItemIDs.contains(item.id) else {
            return nil
        }

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
        return item
    }

    private func recordMistakesIfNeeded(
        isPracticePage: Bool,
        store: PracticeStore,
        studyStore: StudyStore
    ) {
        guard isPracticePage,
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

    private func clearExplanation() {
        explanationTask?.cancel()
        explanationTask = nil
        explanationText = nil
        isExplaining = false
    }
}
