import Foundation

enum DictationAnswerRules {
    static func sanitizedInput(_ value: String) -> String {
        String(value.compactMap { character -> Character? in
            if character.isLetter || character.isNumber {
                return character
            }
            if character == "'" || character == "’" {
                return "'"
            }
            return nil
        })
    }

    static func isExactMatch(_ input: String, answer: String) -> Bool {
        normalized(sanitizedInput(input)) == normalized(sanitizedInput(answer))
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
