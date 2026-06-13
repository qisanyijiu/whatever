import Foundation

@MainActor
final class StudyStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var data = UserStudyData.empty(userID: "")
    @Published private(set) var saveError: String?

    private let library: StudyDataLibrary
    private let reminderService: StudyReminderService
    private let calendar: Calendar
    private var currentUserID: String?

    init(
        library: StudyDataLibrary = StudyDataLibrary(),
        reminderService: StudyReminderService = StudyReminderService(),
        calendar: Calendar = .current
    ) {
        self.library = library
        self.reminderService = reminderService
        self.calendar = calendar
    }

    var completedCount: Int {
        data.completedItemIDs.count
    }

    var todayCompletedCount: Int {
        data.history.filter { calendar.isDateInToday($0.completedAt) }.count
    }

    var dailyGoalProgress: Double {
        guard data.dailyGoal > 0 else {
            return 0
        }
        return min(1, Double(todayCompletedCount) / Double(data.dailyGoal))
    }

    var currentStreak: Int {
        let completedDays = Set(data.history.map { calendar.startOfDay(for: $0.completedAt) })
        guard !completedDays.isEmpty else {
            return 0
        }

        var day = calendar.startOfDay(for: Date())
        if !completedDays.contains(day),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }

        var streak = 0
        while completedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    var weeklySummaries: [WeeklyStudySummary] {
        let groupedCounts = Dictionary(grouping: data.history) { entry in
            calendar.startOfDay(for: entry.completedAt)
        }
        .mapValues(\.count)

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: offset - 6,
                to: calendar.startOfDay(for: Date())
            ) else { return nil }

            return WeeklyStudySummary(
                id: ISO8601DateFormatter().string(from: date),
                label: calendar.isDateInToday(date) ? "今" : date.formatted(.dateTime.weekday(.narrow)),
                completedCount: groupedCounts[date] ?? 0,
                isToday: calendar.isDateInToday(date)
            )
        }
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
            reminderService.syncDailyReminder(
                enabled: data.reminderEnabled,
                hour: data.reminderHour,
                minute: data.reminderMinute
            )
            saveError = nil
        } catch {
            data = .empty(userID: user.id)
            saveError = "无法读取学习记录：\(error.localizedDescription)"
        }
    }

    func clear() {
        currentUserID = nil
        reminderService.syncDailyReminder(enabled: false, hour: 20, minute: 0)
        data = .empty(userID: "")
        saveError = nil
    }

    func updateDailyGoal(_ value: Int) {
        data.dailyGoal = max(1, min(200, value))
        save()
    }

    func updateDailyReminder(enabled: Bool) {
        data.reminderEnabled = enabled
        save()
        reminderService.syncDailyReminder(
            enabled: data.reminderEnabled,
            hour: data.reminderHour,
            minute: data.reminderMinute
        )
    }

    func updateReminderTime(_ date: Date) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return }
        data.reminderHour = hour
        data.reminderMinute = minute
        save()
        reminderService.syncDailyReminder(
            enabled: data.reminderEnabled,
            hour: data.reminderHour,
            minute: data.reminderMinute
        )
    }

    func dueItems(from items: [PracticeItem], on date: Date = Date()) -> [PracticeItem] {
        let itemByID = itemLookup(from: items)
        let dueIDs = data.reviewStates
            .filter { $0.dueAt <= date }
            .sorted { $0.dueAt < $1.dueAt }
            .map(\.itemID)

        return dueIDs.compactMap { itemByID[$0] }
    }

    func mistakeItems(from items: [PracticeItem]) -> [PracticeItem] {
        let itemByID = itemLookup(from: items)
        let mistakeIDs = data.mistakes
            .sorted { left, right in
                if left.mistakeCount == right.mistakeCount {
                    return left.lastMistakeAt > right.lastMistakeAt
                }
                return left.mistakeCount > right.mistakeCount
            }
            .map(\.itemID)

        var seen = Set<PracticeItem.ID>()
        return mistakeIDs.compactMap { id in
            guard !seen.contains(id), let item = itemByID[id] else {
                return nil
            }
            seen.insert(id)
            return item
        }
    }

    private func itemLookup(from items: [PracticeItem]) -> [PracticeItem.ID: PracticeItem] {
        items.reduce(into: [:]) { result, item in
            result[item.id] = result[item.id] ?? item
        }
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

        updateBehaviorMetric(itemID: item.id) { metric in
            metric.spellingErrorCount += 1
        }
        scheduleBackgroundSave()
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

        updateReviewState(itemID: item.id, wrongBlankCount: wrongBlankCount)
        updateBehaviorMetric(itemID: item.id) { metric in
            metric.completionCount += 1
            metric.lastPracticedAt = Date()
        }

        if data.history.count > 100 {
            data.history = Array(data.history.prefix(100))
        }

        scheduleBackgroundSave()
    }

    func recordHintViewed(item: PracticeItem) {
        guard currentUserID != nil else {
            return
        }

        updateBehaviorMetric(itemID: item.id) { metric in
            metric.hintViewCount += 1
            metric.lastPracticedAt = Date()
        }
        scheduleBackgroundSave()
    }

    func recordSkip(item: PracticeItem) {
        guard currentUserID != nil else {
            return
        }

        updateBehaviorMetric(itemID: item.id) { metric in
            metric.skipCount += 1
            metric.lastPracticedAt = Date()
        }
        scheduleBackgroundSave()
    }

    func recordInputTiming(
        item: PracticeItem,
        secondsPerLetter: TimeInterval,
        wordStartDelay: TimeInterval
    ) {
        guard currentUserID != nil else {
            return
        }

        let clampedSecondsPerLetter = min(30, max(0, secondsPerLetter))
        let clampedWordStartDelay = min(120, max(0, wordStartDelay))
        updateBehaviorMetric(itemID: item.id) { metric in
            let sampleCount = Double(metric.timingSampleCount)
            metric.averageSecondsPerLetter = weightedAverage(
                currentAverage: metric.averageSecondsPerLetter,
                sampleCount: sampleCount,
                newValue: clampedSecondsPerLetter
            )
            metric.averageWordStartDelay = weightedAverage(
                currentAverage: metric.averageWordStartDelay,
                sampleCount: sampleCount,
                newValue: clampedWordStartDelay
            )
            metric.timingSampleCount += 1
            metric.lastPracticedAt = Date()
        }
        scheduleBackgroundSave()
    }

    private func dueDate(days: Int, from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    private func updateReviewState(itemID: PracticeItem.ID, wrongBlankCount: Int) {
        let now = Date()
        if let index = data.reviewStates.firstIndex(where: { $0.itemID == itemID }) {
            if wrongBlankCount == 0 {
                data.reviewStates[index].consecutiveCorrect += 1
                data.reviewStates[index].ease = min(3.0, data.reviewStates[index].ease + 0.12)
                let nextInterval = max(1, Int(Double(max(1, data.reviewStates[index].intervalDays)) * data.reviewStates[index].ease))
                data.reviewStates[index].intervalDays = nextInterval
                data.reviewStates[index].dueAt = dueDate(days: nextInterval, from: now)
            } else {
                data.reviewStates[index].lapseCount += 1
                data.reviewStates[index].consecutiveCorrect = 0
                data.reviewStates[index].ease = max(1.3, data.reviewStates[index].ease - 0.2)
                data.reviewStates[index].intervalDays = 1
                data.reviewStates[index].dueAt = dueDate(days: 1, from: now)
            }
            data.reviewStates[index].lastReviewedAt = now
        } else {
            let firstInterval = wrongBlankCount == 0 ? 1 : 0
            data.reviewStates.append(
                PracticeReviewState(
                    id: itemID,
                    itemID: itemID,
                    ease: wrongBlankCount == 0 ? 2.2 : 1.6,
                    intervalDays: firstInterval,
                    dueAt: dueDate(days: firstInterval, from: now),
                    lastReviewedAt: now,
                    consecutiveCorrect: wrongBlankCount == 0 ? 1 : 0,
                    lapseCount: wrongBlankCount == 0 ? 0 : 1
                )
            )
        }
    }

    private func updateBehaviorMetric(
        itemID: PracticeItem.ID,
        update: (inout PracticeBehaviorMetrics) -> Void
    ) {
        let now = Date()
        let index: Int
        if let existingIndex = data.behaviorMetrics.firstIndex(where: { $0.itemID == itemID }) {
            index = existingIndex
        } else {
            data.behaviorMetrics.append(.empty(itemID: itemID, now: now))
            index = data.behaviorMetrics.count - 1
        }

        update(&data.behaviorMetrics[index])
        data.behaviorMetrics[index].updatedAt = now
    }

    private func weightedAverage(
        currentAverage: Double,
        sampleCount: Double,
        newValue: Double
    ) -> Double {
        guard sampleCount > 0 else {
            return newValue
        }
        return (currentAverage * sampleCount + newValue) / (sampleCount + 1)
    }

    private var saveThrottleTask: Task<Void, Never>?

    private func save() {
        data.updatedAt = Date()
        do {
            try library.save(data)
            saveError = nil
        } catch {
            saveError = "保存学习记录失败：\(error.localizedDescription)"
        }
    }

    private func scheduleBackgroundSave() {
        data.updatedAt = Date()
        let snapshot = data
        let lib = library
        saveThrottleTask?.cancel()
        saveThrottleTask = Task.detached(priority: .background) {
            _ = try? lib.save(snapshot)
        }
    }
}

struct WeeklyStudySummary: Identifiable, Hashable {
    let id: String
    let label: String
    let completedCount: Int
    let isToday: Bool
}
