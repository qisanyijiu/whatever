import Foundation

struct PracticeSessionScheduler {
    func orderedItems(
        _ items: [PracticeItem],
        studyData: UserStudyData,
        now: Date = Date()
    ) -> [PracticeItem] {
        guard items.count > 1 else {
            return items
        }

        return items
            .map { item in
                let weight = priorityWeight(for: item, studyData: studyData, now: now)
                let random = max(Double.random(in: 0..<1), Double.leastNonzeroMagnitude)
                return (item: item, sortKey: -log(random) / weight)
            }
            .sorted { $0.sortKey < $1.sortKey }
            .map(\.item)
    }

    func priorityWeight(
        for item: PracticeItem,
        studyData: UserStudyData,
        now: Date = Date()
    ) -> Double {
        let reviewState = studyData.reviewStates.first { $0.itemID == item.id }
        let behaviorMetric = studyData.behaviorMetrics.first { $0.itemID == item.id }

        var weight = reviewWeight(for: reviewState, now: now)
        weight *= behaviorWeight(for: behaviorMetric)
        return min(12, max(0.12, weight))
    }

    private func reviewWeight(for state: PracticeReviewState?, now: Date) -> Double {
        guard let state else {
            return 2.4
        }

        let lastReviewedAt = state.lastReviewedAt ?? now
        let elapsedDays = max(0, now.timeIntervalSince(lastReviewedAt) / 86_400)
        let intervalDays = max(1, state.intervalDays)
        let retention = exp(-elapsedDays / (Double(intervalDays) * max(0.55, state.ease / 2.2)))
        let forgettingPressure = 1 - retention

        var weight = 0.45 + forgettingPressure * 3.5
        if state.dueAt <= now {
            let overdueDays = max(0, now.timeIntervalSince(state.dueAt) / 86_400)
            weight += 1.2 + min(4, overdueDays * 0.5)
        } else {
            weight *= 0.55
        }

        weight += min(1.5, Double(state.lapseCount) * 0.25)
        weight -= min(1.1, Double(state.consecutiveCorrect) * 0.18)
        return max(0.2, weight)
    }

    private func behaviorWeight(for metric: PracticeBehaviorMetrics?) -> Double {
        guard let metric else {
            return 1.15
        }

        let spellingPressure = min(3.0, Double(metric.spellingErrorCount) * 0.18)
        let hintPressure = min(2.0, Double(metric.hintViewCount) * 0.16)
        let skipPressure = min(2.5, Double(metric.skipCount) * 0.35)
        let typingPressure = min(1.6, max(0, metric.averageSecondsPerLetter - 0.45) * 1.8)
        let waitPressure = min(1.8, max(0, metric.averageWordStartDelay - 1.2) * 0.55)
        let familiarityDiscount = min(2.2, Double(metric.completionCount) * 0.18)

        return max(
            0.25,
            1 + spellingPressure + hintPressure + skipPressure + typingPressure + waitPressure - familiarityDiscount
        )
    }
}
