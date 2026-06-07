import Foundation

struct PracticeLibrarySummary: Identifiable, Hashable {
    let id: String
    let name: String
    let itemCount: Int
    let completedCount: Int
    let mistakeCount: Int
    let detail: String
    let isActive: Bool
}
