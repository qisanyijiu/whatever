import Foundation

struct ImportDraft: Identifiable, Hashable {
    let id = UUID().uuidString
    var name: String
    var source: String
    var items: [ImportDraftItem]
}

struct ImportDraftItem: Identifiable, Hashable {
    let id: String
    var sourceChinese: String
    var targetEnglish: String
    var blankText: String

    var blankAnswers: [String] {
        blankText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
