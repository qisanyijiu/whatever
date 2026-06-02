import Foundation

struct ClozeGenerator {
    private struct WordMatch {
        let range: NSRange
        let text: String
        let lowercasedText: String
        let score: Int
    }

    private let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "than", "so",
        "to", "of", "in", "on", "at", "by", "for", "from", "with", "without",
        "about", "into", "over", "under", "after", "before", "between",
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her",
        "us", "them", "my", "your", "his", "its", "our", "their", "this",
        "that", "these", "those", "is", "am", "are", "was", "were", "be",
        "been", "being", "do", "does", "did", "can", "could", "will", "would",
        "shall", "should", "may", "might", "must", "have", "has", "had",
        "not", "no", "yes", "as", "too", "very", "just"
    ]

    func segments(from sentence: String, itemID: String) -> [ClozeSegment] {
        let words = wordMatches(in: sentence)
        guard !words.isEmpty else {
            return [.text(sentence)]
        }

        let selectedWords = selectBlankWords(from: words)
        guard !selectedWords.isEmpty else {
            return [.text(sentence)]
        }

        let nsSentence = sentence as NSString
        var cursor = 0
        var segments: [ClozeSegment] = []

        for (index, word) in selectedWords.enumerated() {
            if word.range.location > cursor {
                let textRange = NSRange(location: cursor, length: word.range.location - cursor)
                segments.append(.text(nsSentence.substring(with: textRange)))
            }

            segments.append(.blank(ClozeBlank(id: "\(itemID)-blank-\(index)", answer: word.text)))
            cursor = word.range.location + word.range.length
        }

        if cursor < nsSentence.length {
            segments.append(.text(nsSentence.substring(from: cursor)))
        }

        return segments
    }

    private func wordMatches(in sentence: String) -> [WordMatch] {
        let nsSentence = sentence as NSString
        let regex = try? NSRegularExpression(pattern: #"[A-Za-z]+(?:'[A-Za-z]+)?"#)
        let matches = regex?.matches(
            in: sentence,
            range: NSRange(location: 0, length: nsSentence.length)
        ) ?? []

        return matches.map { match in
            let word = nsSentence.substring(with: match.range)
            let lowercasedWord = word.lowercased()
            return WordMatch(
                range: match.range,
                text: word,
                lowercasedText: lowercasedWord,
                score: word.count + importanceBonus(for: lowercasedWord)
            )
        }
    }

    private func selectBlankWords(from words: [WordMatch]) -> [WordMatch] {
        let targetCount = min(3, max(1, words.count / 7 + 1))
        var selected: [WordMatch] = []
        var usedWords = Set<String>()

        let candidates = words
            .filter { $0.text.count >= 4 && !stopWords.contains($0.lowercasedText) }
            .sorted { left, right in
                if left.score == right.score {
                    return left.range.location < right.range.location
                }
                return left.score > right.score
            }

        for candidate in candidates where !usedWords.contains(candidate.lowercasedText) {
            selected.append(candidate)
            usedWords.insert(candidate.lowercasedText)
            if selected.count == targetCount {
                break
            }
        }

        if selected.isEmpty, let fallback = words.max(by: { $0.text.count < $1.text.count }) {
            selected.append(fallback)
        }

        return selected.sorted { $0.range.location < $1.range.location }
    }

    private func importanceBonus(for word: String) -> Int {
        if word.hasSuffix("ing") || word.hasSuffix("ed") {
            return 4
        }
        if word.hasSuffix("ly") || word.hasSuffix("tion") || word.hasSuffix("ment") {
            return 3
        }
        return 0
    }
}
