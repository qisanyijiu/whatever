import Foundation

@MainActor
final class AIProviderStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var providers: [AIProviderConfig]
    @Published private(set) var activeProviderID: AIProviderConfig.ID?
    @Published private(set) var saveError: String?

    private let library: AIProviderLibrary

    init(library: AIProviderLibrary = AIProviderLibrary()) {
        self.library = library
        let settings = library.load()
        self.providers = settings.providers
        self.activeProviderID = settings.activeProviderID
    }

    var activeProvider: AIProviderConfig? {
        guard let activeProviderID else {
            return nil
        }
        return providers.first { $0.id == activeProviderID }
    }

    @discardableResult
    func addProvider() -> AIProviderConfig {
        let provider = AIProviderConfig(
            id: "ai-\(UUID().uuidString)",
            name: "新 AI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: "",
            createdAt: Date(),
            updatedAt: Date()
        )
        providers.append(provider)
        if activeProviderID == nil {
            activeProviderID = provider.id
        }
        persist()
        return provider
    }

    func saveProvider(_ provider: AIProviderConfig) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else {
            providers.append(provider)
            persist()
            return
        }

        var updatedProvider = provider
        updatedProvider.updatedAt = Date()
        providers[index] = updatedProvider
        persist()
    }

    func selectProvider(_ providerID: AIProviderConfig.ID) {
        guard providers.contains(where: { $0.id == providerID }) else {
            return
        }
        activeProviderID = providerID
        persist()
    }

    func deleteProvider(_ providerID: AIProviderConfig.ID) {
        let deletionError: String?
        do {
            try library.deleteSecret(for: providerID)
            deletionError = nil
        } catch {
            deletionError = "删除 AI 密钥失败：\(error.localizedDescription)"
        }

        providers.removeAll { $0.id == providerID }
        if activeProviderID == providerID {
            activeProviderID = providers.first?.id
        }
        persist()
        if let deletionError {
            saveError = deletionError
        }
    }

    private func persist() {
        do {
            try library.save(AIProviderSettings(activeProviderID: activeProviderID, providers: providers))
            saveError = nil
        } catch {
            saveError = "保存 AI 配置失败：\(error.localizedDescription)"
        }
    }
}
