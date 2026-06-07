import Foundation

struct PracticeDeck: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var source: String
    var createdAt: Date
    var updatedAt: Date
    var items: [PracticeItem]
}
