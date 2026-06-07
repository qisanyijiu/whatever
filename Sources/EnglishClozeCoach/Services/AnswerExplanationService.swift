import Foundation

struct AnswerExplanationService {
    func explanation(for item: PracticeItem, answers: [String: String]) -> String {
        let lines = item.blanks.enumerated().map { index, blank in
            let blankNumber = index + 1
            let userAnswer = answers[blank.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if userAnswer.isEmpty {
                return "### 空位 \(blankNumber)：\(blank.answer)\n还没有作答。"
            }
            if AnswerMatcher().matches(userAnswer, answer: blank.answer) {
                return "### 空位 \(blankNumber)：\(blank.answer)\n正确。注意它在原句中的搭配位置。"
            }
            return "### 空位 \(blankNumber)：\(blank.answer)\n你的答案是 \(userAnswer)。建议回到完整句子中记忆：\(item.targetEnglish)"
        }

        return lines.joined(separator: "\n\n")
    }
}
