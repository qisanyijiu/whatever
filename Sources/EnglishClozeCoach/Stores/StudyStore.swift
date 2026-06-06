import Foundation

final class StudyStore: ObservableObject {
    @Published private(set) var data = UserStudyData.empty(userID: "")
    @Published private(set) var saveError: String?

    private let library: StudyDataLibrary
    private var currentUserID: String?

    init(library: StudyDataLibrary = StudyDataLibrary()) {
        self.library = library
    }

    var completedCount: Int {
        data.completedItemIDs.count
    }

    var recentHistory: [PracticeHistoryEntry] {
        Array(data.history.prefix(8))
    }

    var frequentMistakes: [MistakeRecord] {
        Array(
            data.mistakes
                .sorted { left, right in
                    if left.mistakeCount == right.mistakeCount {
                        return left.lastMistakeAt > right.lastMistakeAt
                    }
                    return left.mistakeCount > right.mistakeCount
                }
                .prefix(8)
        )
    }

    func load(for user: UserAccount) {
        currentUserID = user.id
        do {
            data = try library.load(userID: user.id)
            saveError = nil
        } catch {
            data = .empty(userID: user.id)
            saveError = "无法读取学习记录：\(error.localizedDescription)"
        }
    }

    func clear() {
        currentUserID = nil
        data = .empty(userID: "")
        saveError = nil
    }

    func recordMistake(item: PracticeItem, blank: ClozeBlank, wrongAnswer: String) {
        guard currentUserID != nil else {
            return
        }

        let trimmedWrongAnswer = wrongAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWrongAnswer.isEmpty else {
            return
        }

        let id = "\(item.id)-\(blank.id)"
        if let index = data.mistakes.firstIndex(where: { $0.id == id }) {
            data.mistakes[index].lastWrongAnswer = trimmedWrongAnswer
            data.mistakes[index].mistakeCount += 1
            data.mistakes[index].lastMistakeAt = Date()
        } else {
            data.mistakes.append(
                MistakeRecord(
                    id: id,
                    itemID: item.id,
                    blankID: blank.id,
                    sourceChinese: item.sourceChinese,
                    targetEnglish: item.targetEnglish,
                    answer: blank.answer,
                    lastWrongAnswer: trimmedWrongAnswer,
                    mistakeCount: 1,
                    lastMistakeAt: Date()
                )
            )
        }

        save()
    }

    func recordCompletion(item: PracticeItem, wrongBlankCount: Int) {
        guard currentUserID != nil else {
            return
        }

        data.completedItemIDs.insert(item.id)
        data.history.insert(
            PracticeHistoryEntry(
                id: UUID().uuidString,
                itemID: item.id,
                sourceChinese: item.sourceChinese,
                targetEnglish: item.targetEnglish,
                completedAt: Date(),
                wrongBlankCount: wrongBlankCount
            ),
            at: 0
        )

        if data.history.count > 100 {
            data.history = Array(data.history.prefix(100))
        }

        save()
    }

    private func save() {
        data.updatedAt = Date()
        do {
            try library.save(data)
            saveError = nil
        } catch {
            saveError = "保存学习记录失败：\(error.localizedDescription)"
        }
    }
}
