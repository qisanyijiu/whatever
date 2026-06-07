import Foundation

struct AIProviderConfig: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var baseURL: String
    var model: String
    var apiKey: String
    var createdAt: Date
    var updatedAt: Date

    var isReady: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct AIProviderSettings: Hashable, Codable {
    var activeProviderID: AIProviderConfig.ID?
    var providers: [AIProviderConfig]

    static let empty = AIProviderSettings(activeProviderID: nil, providers: [])
}
