import Foundation

@MainActor
final class BlankInputTimingTracker: ObservableObject {
    private var focusStartedAtByBlankID: [ClozeBlank.ID: Date] = [:]
    private var firstInputAtByBlankID: [ClozeBlank.ID: Date] = [:]
    private var recordedBlankIDs = Set<ClozeBlank.ID>()

    func reset() {
        focusStartedAtByBlankID = [:]
        firstInputAtByBlankID = [:]
        recordedBlankIDs = []
    }

    func focusChanged(to blankID: ClozeBlank.ID?) {
        guard let blankID else {
            return
        }
        focusStartedAtByBlankID[blankID] = Date()
    }

    func inputChanged(
        blank: ClozeBlank,
        text: String,
        isCorrect: Bool,
        record: (TimeInterval, TimeInterval) -> Void
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            firstInputAtByBlankID[blank.id] = nil
            recordedBlankIDs.remove(blank.id)
            return
        }

        let now = Date()
        if firstInputAtByBlankID[blank.id] == nil {
            firstInputAtByBlankID[blank.id] = now
        }

        guard isCorrect, !recordedBlankIDs.contains(blank.id) else {
            return
        }

        let firstInputAt = firstInputAtByBlankID[blank.id] ?? now
        let focusStartedAt = focusStartedAtByBlankID[blank.id] ?? firstInputAt
        let characterCount = max(1, blank.answer.count)
        let secondsPerLetter = max(0, now.timeIntervalSince(firstInputAt)) / Double(characterCount)
        let wordStartDelay = max(0, firstInputAt.timeIntervalSince(focusStartedAt))
        recordedBlankIDs.insert(blank.id)
        record(secondsPerLetter, wordStartDelay)
    }
}
