import Foundation

final class PracticeStore: ObservableObject {
    enum AnswerState {
        case idle
        case correct
        case incorrect
    }

    @Published private(set) var decks: [PracticeDeck]
    @Published private(set) var items: [PracticeItem]
    @Published var selectedDeckID: PracticeDeck.ID?
    @Published var selectedItemID: PracticeItem.ID?
    @Published var answers: [String: String] = [:]
    @Published private(set) var importError: String?
    @Published private(set) var librarySummaries: [PracticeLibrarySummary] = []
    @Published private(set) var currentPracticeTitle = "练习"

    private let library: PracticeLibrary
    private let importer: QuestionImporter
    private let answerMatcher: AnswerMatcher
    private let explanationService = AnswerExplanationService()

    init(
        library: PracticeLibrary = PracticeLibrary(),
        importer: QuestionImporter = QuestionImporter(),
        answerMatcher: AnswerMatcher = AnswerMatcher()
    ) {
        self.library = library
        self.importer = importer
        self.answerMatcher = answerMatcher
        let loadedDecks = library.loadDecks()
        self.decks = loadedDecks
        self.selectedDeckID = loadedDecks.first?.id
        self.items = loadedDecks.first?.items ?? []
        self.selectedItemID = loadedDecks.first?.items.first?.id
        refreshLibrarySummaries()
    }

    var allItems: [PracticeItem] {
        var seen = Set<PracticeItem.ID>()
        return decks.flatMap(\.items).filter { item in
            guard !seen.contains(item.id) else {
                return false
            }
            seen.insert(item.id)
            return true
        }
    }

    var selectedDeck: PracticeDeck? {
        guard let selectedDeckID else {
            return decks.first
        }
        return decks.first { $0.id == selectedDeckID } ?? decks.first
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

    func selectDeck(_ deckID: PracticeDeck.ID) {
        guard let deck = decks.first(where: { $0.id == deckID }) else {
            return
        }

        selectedDeckID = deck.id
        currentPracticeTitle = deck.name
        items = deck.items
        selectedItemID = deck.items.first?.id
        clearAnswers()
        refreshLibrarySummaries()
    }

    func startCustomPractice(items newItems: [PracticeItem], title: String) {
        items = newItems
        currentPracticeTitle = title
        selectedItemID = newItems.first?.id
        clearAnswers()
    }

    func returnToSelectedDeck() {
        if let selectedDeckID {
            selectDeck(selectedDeckID)
        }
    }

    func prepareImportDraft(text: String, name: String, source: String) -> ImportDraft? {
        importer.importDraft(from: text, name: name, source: source)
    }

    @discardableResult
    func saveImportDraft(_ draft: ImportDraft, selectAfterSave: Bool = true) -> Int {
        let importedItems = importer.practiceItems(from: draft)
        guard !importedItems.isEmpty else {
            importError = "没有生成题目。"
            return 0
        }

        let deck = PracticeDeck(
            id: "deck-\(UUID().uuidString)",
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "导入题库"
                : draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            source: draft.source,
            createdAt: Date(),
            updatedAt: Date(),
            items: importedItems
        )
        decks.append(deck)
        saveDecks()
        if selectAfterSave {
            selectDeck(deck.id)
        } else {
            refreshLibrarySummaries()
        }
        importError = nil
        return importedItems.count
    }

    func encryptedArchiveData(password: String) throws -> Data {
        try library.exportEncryptedArchive(decks: decks, password: password)
    }

    @discardableResult
    func importEncryptedArchiveData(_ data: Data, password: String) throws -> Int {
        let importedDecks = try library.importEncryptedArchive(data, password: password)
        return appendImportedDecks(importedDecks)
    }

    @discardableResult
    func importText(_ text: String) -> Int {
        guard let draft = prepareImportDraft(text: text, name: "导入题库", source: "粘贴文本") else {
            importError = "没有找到可生成题目的英文句子。"
            return 0
        }
        return saveImportDraft(draft)
    }

    func renameDeck(_ deckID: PracticeDeck.ID, name: String) {
        guard let index = decks.firstIndex(where: { $0.id == deckID }) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        decks[index].name = trimmedName
        decks[index].updatedAt = Date()
        saveDecks()
        if selectedDeckID == deckID {
            currentPracticeTitle = trimmedName
        }
        refreshLibrarySummaries()
    }

    func deleteDeck(_ deckID: PracticeDeck.ID) {
        guard decks.count > 1 else {
            importError = "至少保留一个题库。"
            return
        }

        decks.removeAll { $0.id == deckID }
        saveDecks()
        if selectedDeckID == deckID {
            selectDeck(decks[0].id)
        } else {
            refreshLibrarySummaries()
        }
    }

    func deleteItem(_ itemID: PracticeItem.ID, in deckID: PracticeDeck.ID) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }) else {
            return
        }

        decks[deckIndex].items.removeAll { $0.id == itemID }
        decks[deckIndex].updatedAt = Date()
        saveDecks()
        if selectedDeckID == deckID {
            selectDeck(deckID)
        } else {
            refreshLibrarySummaries()
        }
    }

    func updateItem(
        _ itemID: PracticeItem.ID,
        in deckID: PracticeDeck.ID,
        sourceChinese: String,
        targetEnglish: String,
        blankText: String
    ) {
        guard let deckIndex = decks.firstIndex(where: { $0.id == deckID }),
              let itemIndex = decks[deckIndex].items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        let blanks = blankText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let segments = ClozeGenerator().segments(
            from: targetEnglish,
            itemID: itemID,
            blankAnswers: blanks
        )

        decks[deckIndex].items[itemIndex] = PracticeItem(
            id: itemID,
            sourceChinese: sourceChinese,
            targetEnglish: targetEnglish,
            segments: segments
        )
        decks[deckIndex].updatedAt = Date()
        saveDecks()

        if selectedDeckID == deckID {
            selectDeck(deckID)
        } else {
            refreshLibrarySummaries()
        }
    }

    func answerState(for blank: ClozeBlank) -> AnswerState {
        let answer = answerText(for: blank).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else {
            return .idle
        }
        return answerMatcher.matches(answer, answer: blank.answer) ? .correct : .incorrect
    }

    func isCompleted(_ item: PracticeItem) -> Bool {
        !item.blanks.isEmpty && item.blanks.allSatisfy { blank in
            answerState(for: blank) == .correct
        }
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

    func clearAnswers() {
        answers = [:]
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

    func explanationForSelectedItem() -> String? {
        guard let selectedItem else {
            return nil
        }
        return explanationService.explanation(for: selectedItem, answers: answers)
    }

    func refreshLibrarySummaries(studyData: UserStudyData? = nil) {
        let completedIDs = studyData?.completedItemIDs ?? []
        let mistakeItemIDs = Set(studyData?.mistakes.map(\.itemID) ?? [])
        librarySummaries = decks.map { deck in
            let itemIDs = Set(deck.items.map(\.id))
            return PracticeLibrarySummary(
                id: deck.id,
                name: deck.name,
                itemCount: deck.items.count,
                completedCount: itemIDs.intersection(completedIDs).count,
                mistakeCount: itemIDs.intersection(mistakeItemIDs).count,
                detail: deck.source,
                isActive: deck.id == selectedDeckID
            )
        }
    }

    private func saveDecks() {
        refreshLibrarySummaries()
        do {
            try library.save(decks)
        } catch {
            importError = "保存题库失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func appendImportedDecks(_ importedDecks: [PracticeDeck]) -> Int {
        var existingDeckIDs = Set(decks.map(\.id))
        var existingDeckNames = Set(decks.map(\.name))
        var existingItemIDs = Set(decks.flatMap { $0.items.map(\.id) })
        var importedCount = 0
        var normalizedDecks: [PracticeDeck] = []

        for deck in importedDecks where !deck.items.isEmpty {
            let deckID = existingDeckIDs.contains(deck.id) ? "deck-\(UUID().uuidString)" : deck.id
            existingDeckIDs.insert(deckID)

            let normalizedItems = deck.items.map { item in
                let itemID = existingItemIDs.contains(item.id) ? "imported-\(UUID().uuidString)" : item.id
                existingItemIDs.insert(itemID)
                guard itemID != item.id else {
                    return item
                }
                return PracticeItem(
                    id: itemID,
                    sourceChinese: item.sourceChinese,
                    targetEnglish: item.targetEnglish,
                    segments: remappedBlankIDs(in: item.segments, itemID: itemID)
                )
            }

            let deckName = uniqueDeckName(deck.name, existingNames: existingDeckNames)
            existingDeckNames.insert(deckName)
            importedCount += normalizedItems.count
            normalizedDecks.append(PracticeDeck(
                id: deckID,
                name: deckName,
                source: deck.source,
                createdAt: Date(),
                updatedAt: Date(),
                items: normalizedItems
            ))
        }

        guard importedCount > 0 else {
            importError = "加密题库中没有可导入的题目。"
            return 0
        }

        decks.append(contentsOf: normalizedDecks)
        saveDecks()
        if let firstImportedDeckID = normalizedDecks.first?.id {
            selectDeck(firstImportedDeckID)
        }
        importError = nil
        return importedCount
    }

    private func uniqueDeckName(_ name: String, existingNames: Set<String>) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "导入题库" : trimmed
        guard existingNames.contains(baseName) else {
            return baseName
        }

        var index = 2
        while existingNames.contains("\(baseName) \(index)") {
            index += 1
        }
        return "\(baseName) \(index)"
    }

    private func remappedBlankIDs(in segments: [ClozeSegment], itemID: PracticeItem.ID) -> [ClozeSegment] {
        var blankIndex = 0
        return segments.map { segment in
            guard case let .blank(blank) = segment else {
                return segment
            }
            blankIndex += 1
            return .blank(ClozeBlank(id: "\(itemID)-blank-\(blankIndex)", answer: blank.answer))
        }
    }
}
