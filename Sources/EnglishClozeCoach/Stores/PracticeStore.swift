import Foundation

final class PracticeStore: ObservableObject {
    enum AnswerState {
        case idle
        case correct
        case incorrect
    }

    @Published private(set) var items: [PracticeItem]
    @Published var selectedItemID: PracticeItem.ID?
    @Published var answers: [String: String] = [:]
    @Published private(set) var importError: String?

    private let library: PracticeLibrary
    private let importer: QuestionImporter

    init(
        library: PracticeLibrary = PracticeLibrary(),
        importer: QuestionImporter = QuestionImporter()
    ) {
        self.library = library
        self.importer = importer
        let loadedItems = library.loadItems()
        self.items = loadedItems
        self.selectedItemID = loadedItems.first?.id
    }

    var selectedItem: PracticeItem? {
        guard let selectedItemID else {
            return items.first
        }
        return items.first { $0.id == selectedItemID } ?? items.first
    }

    var selectedIndex: Int {
        guard let selectedItemID else {
            return 0
        }
        return items.firstIndex { $0.id == selectedItemID } ?? 0
    }

    var canGoBack: Bool {
        selectedIndex > 0
    }

    var canAdvance: Bool {
        selectedIndex < items.count - 1
    }

    @discardableResult
    func importText(_ text: String) -> Int {
        let importedItems = importer.importItems(from: text)
        guard !importedItems.isEmpty else {
            importError = "没有找到可生成题目的英文句子。"
            return 0
        }

        items.append(contentsOf: importedItems)
        selectedItemID = importedItems.first?.id
        saveItems()
        importError = nil
        return importedItems.count
    }

    func answerState(for blank: ClozeBlank) -> AnswerState {
        let answer = normalized(answerText(for: blank))
        guard !answer.isEmpty else {
            return .idle
        }
        return answer == normalized(blank.answer) ? .correct : .incorrect
    }

    func answerText(for blank: ClozeBlank) -> String {
        answers[blank.id] ?? ""
    }

    func setAnswer(_ value: String, for blank: ClozeBlank) {
        var updatedAnswers = answers
        updatedAnswers[blank.id] = value
        answers = updatedAnswers
    }

    func resetCurrentAnswers() {
        guard let selectedItem else {
            return
        }
        var updatedAnswers = answers
        for blank in selectedItem.blanks {
            updatedAnswers[blank.id] = ""
        }
        answers = updatedAnswers
    }

    func advance() {
        guard !items.isEmpty else {
            return
        }
        let nextIndex = min(selectedIndex + 1, items.count - 1)
        selectedItemID = items[nextIndex].id
    }

    func goBack() {
        guard !items.isEmpty else {
            return
        }
        let previousIndex = max(selectedIndex - 1, 0)
        selectedItemID = items[previousIndex].id
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func saveItems() {
        do {
            try library.save(items)
        } catch {
            importError = "题目已导入，但保存失败：\(error.localizedDescription)"
        }
    }
}
