import Foundation

struct AIProviderLibrary {
    private let fileManager: FileManager
    private let keychain: KeychainService
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init(
        fileManager: FileManager = .default,
        keychain: KeychainService = KeychainService(service: "whatever.ai-providers")
    ) {
        self.fileManager = fileManager
        self.keychain = keychain
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AIProviderSettings {
        guard let data = try? Data(contentsOf: settingsURL()),
              let settings = try? decoder.decode(AIProviderSettings.self, from: data) else {
            return .empty
        }

        var shouldSanitizeJSON = false
        let hydratedProviders = settings.providers.map { provider in
            var hydratedProvider = provider
            if !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shouldSanitizeJSON = true
            }
            if let savedAPIKey = keychain.read(account: provider.id), !savedAPIKey.isEmpty {
                hydratedProvider.apiKey = savedAPIKey
            } else if !provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? keychain.save(provider.apiKey, account: provider.id)
            }
            return hydratedProvider
        }

        let hydratedSettings = AIProviderSettings(
            activeProviderID: settings.activeProviderID,
            providers: hydratedProviders
        )
        if shouldSanitizeJSON {
            try? save(hydratedSettings)
        }
        return hydratedSettings
    }

    func save(_ settings: AIProviderSettings) throws {
        var sanitizedSettings = settings
        for index in sanitizedSettings.providers.indices {
            let provider = sanitizedSettings.providers[index]
            if provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try keychain.delete(account: provider.id)
            } else {
                try keychain.save(provider.apiKey, account: provider.id)
            }
            sanitizedSettings.providers[index].apiKey = ""
        }

        try fileManager.createDirectory(at: applicationSupportDirectory(), withIntermediateDirectories: true)
        let data = try encoder.encode(sanitizedSettings)
        try data.write(to: settingsURL(), options: .atomic)
    }

    func deleteSecret(for providerID: AIProviderConfig.ID) throws {
        try keychain.delete(account: providerID)
    }

    private func settingsURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("AIProviders.json")
    }

    private func applicationSupportDirectory() -> URL {
        let baseURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser

        return baseURL.appendingPathComponent("whatever", isDirectory: true)
    }
}
