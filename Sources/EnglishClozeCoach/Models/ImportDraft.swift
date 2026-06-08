import Foundation

struct ImportDraft: Identifiable, Hashable {
    let id: String
    var name: String
    var source: String
    var items: [ImportDraftItem]

    init(id: String = UUID().uuidString, name: String, source: String, items: [ImportDraftItem]) {
        self.id = id
        self.name = name
        self.source = source
        self.items = items
    }
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
