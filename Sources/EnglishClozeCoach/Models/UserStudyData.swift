import Foundation

struct UserStudyData: Hashable, Codable {
    let userID: String
    var completedItemIDs: Set<PracticeItem.ID>
    var history: [PracticeHistoryEntry]
    var mistakes: [MistakeRecord]
    var updatedAt: Date

    static func empty(userID: String) -> UserStudyData {
        UserStudyData(
            userID: userID,
            completedItemIDs: [],
            history: [],
            mistakes: [],
            updatedAt: Date()
        )
    }
}

struct PracticeHistoryEntry: Identifiable, Hashable, Codable {
    let id: String
    let itemID: PracticeItem.ID
    let sourceChinese: String
    let targetEnglish: String
    let completedAt: Date
    let wrongBlankCount: Int
}

struct MistakeRecord: Identifiable, Hashable, Codable {
    let id: String
    let itemID: PracticeItem.ID
    let blankID: ClozeBlank.ID
    let sourceChinese: String
    let targetEnglish: String
    let answer: String
    var lastWrongAnswer: String
    var mistakeCount: Int
    var lastMistakeAt: Date
}
