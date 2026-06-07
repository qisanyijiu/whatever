import Foundation

struct AnswerMatcher {
    func matches(_ input: String, answer: String) -> Bool {
        let left = normalized(input)
        let right = normalized(answer)

        guard !left.isEmpty else {
            return false
        }
        if left == right {
            return true
        }
        if expandContractions(left) == expandContractions(right) {
            return true
        }
        if strippedPunctuation(left) == strippedPunctuation(right) {
            return true
        }
        if stemmed(left) == stemmed(right) {
            return true
        }
        return right.count >= 5 && levenshtein(left, right) <= 1
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func strippedPunctuation(_ value: String) -> String {
        value.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
    }

    private func expandContractions(_ value: String) -> String {
        var expanded = value
        [
            "i'm": "i am",
            "you're": "you are",
            "he's": "he is",
            "she's": "she is",
            "it's": "it is",
            "we're": "we are",
            "they're": "they are",
            "can't": "cannot",
            "won't": "will not",
            "n't": " not",
            "'re": " are",
            "'ve": " have",
            "'ll": " will",
            "'d": " would"
        ].forEach { expanded = expanded.replacingOccurrences(of: $0.key, with: $0.value) }
        return expanded
    }

    private func stemmed(_ value: String) -> String {
        let words = strippedPunctuation(value).split(separator: " ").map { word in
            var text = String(word)
            for suffix in ["ing", "ed", "es", "s"] where text.count > suffix.count + 3 && text.hasSuffix(suffix) {
                text.removeLast(suffix.count)
                break
            }
            return text
        }
        return words.joined(separator: " ")
    }

    private func levenshtein(_ left: String, _ right: String) -> Int {
        let left = Array(left)
        let right = Array(right)
        var distances = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var previous = distances[0]
            distances[0] = leftIndex + 1

            for (rightIndex, rightCharacter) in right.enumerated() {
                let old = distances[rightIndex + 1]
                distances[rightIndex + 1] = min(
                    distances[rightIndex + 1] + 1,
                    distances[rightIndex] + 1,
                    previous + (leftCharacter == rightCharacter ? 0 : 1)
                )
                previous = old
            }
        }

        return distances[right.count]
    }
}
