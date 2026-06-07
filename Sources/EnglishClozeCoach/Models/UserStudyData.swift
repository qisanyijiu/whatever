import Foundation

struct UserStudyData: Hashable, Codable {
    let userID: String
    var completedItemIDs: Set<PracticeItem.ID>
    var history: [PracticeHistoryEntry]
    var mistakes: [MistakeRecord]
    var reviewStates: [PracticeReviewState]
    var dailyGoal: Int
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var updatedAt: Date

    static func empty(userID: String) -> UserStudyData {
        UserStudyData(
            userID: userID,
            completedItemIDs: [],
            history: [],
            mistakes: [],
            reviewStates: [],
            dailyGoal: 10,
            reminderEnabled: false,
            reminderHour: 20,
            reminderMinute: 0,
            updatedAt: Date()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case userID
        case completedItemIDs
        case history
        case mistakes
        case reviewStates
        case dailyGoal
        case reminderEnabled
        case reminderHour
        case reminderMinute
        case updatedAt
    }

    init(
        userID: String,
        completedItemIDs: Set<PracticeItem.ID>,
        history: [PracticeHistoryEntry],
        mistakes: [MistakeRecord],
        reviewStates: [PracticeReviewState],
        dailyGoal: Int,
        reminderEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        updatedAt: Date
    ) {
        self.userID = userID
        self.completedItemIDs = completedItemIDs
        self.history = history
        self.mistakes = mistakes
        self.reviewStates = reviewStates
        self.dailyGoal = dailyGoal
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = try container.decode(String.self, forKey: .userID)
        self.completedItemIDs = try container.decodeIfPresent(Set<PracticeItem.ID>.self, forKey: .completedItemIDs) ?? []
        self.history = try container.decodeIfPresent([PracticeHistoryEntry].self, forKey: .history) ?? []
        self.mistakes = try container.decodeIfPresent([MistakeRecord].self, forKey: .mistakes) ?? []
        self.reviewStates = try container.decodeIfPresent([PracticeReviewState].self, forKey: .reviewStates) ?? []
        self.dailyGoal = try container.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 10
        self.reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        self.reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 20
        self.reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
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

struct PracticeReviewState: Identifiable, Hashable, Codable {
    let id: String
    let itemID: PracticeItem.ID
    var ease: Double
    var intervalDays: Int
    var dueAt: Date
    var lastReviewedAt: Date?
    var consecutiveCorrect: Int
    var lapseCount: Int
}
