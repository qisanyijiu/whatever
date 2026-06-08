import Foundation

struct PracticeLibrary {
    private let fileManager: FileManager
    private let applicationSupportOverride: URL?
    private let legacyApplicationSupportOverride: URL?
    private let seedItemsProvider: () -> [PracticeItem]
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        legacyApplicationSupportDirectory: URL? = nil,
        seedItemsProvider: (() -> [PracticeItem])? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportOverride = applicationSupportDirectory
        self.legacyApplicationSupportOverride = legacyApplicationSupportDirectory
        self.seedItemsProvider = seedItemsProvider ?? {
            Self.bundledSeedItems(decoder: JSONDecoder())
        }
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadDecks() -> [PracticeDeck] {
        if let savedDecks = try? loadSavedDecks(), !savedDecks.isEmpty {
            return savedDecks
        }

        if let legacyItems = try? loadLegacySavedItems(), !legacyItems.isEmpty {
            return seedDecks() + [
                PracticeDeck(
                    id: "legacy-saved",
                    name: "本机保存题库",
                    source: "旧版导入数据",
                    createdAt: Date(),
                    updatedAt: Date(),
                    items: legacyItems
                )
            ]
        }

        return seedDecks()
    }

    func save(_ decks: [PracticeDeck]) throws {
        let directory = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(decks)
        try data.write(to: directory.appendingPathComponent("Decks.json"), options: .atomic)
    }

    private func loadSavedDecks() throws -> [PracticeDeck] {
        let url = try applicationSupportDirectory().appendingPathComponent("Decks.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([PracticeDeck].self, from: data)
    }

    private func seedDecks() -> [PracticeDeck] {
        let items = seedItemsProvider()
        guard !items.isEmpty else {
            return []
        }

        return [
            PracticeDeck(
                id: "seed",
                name: "内置题库",
                source: "应用内置 JSON 资源",
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0),
                items: items
            )
        ]
    }

    static func bundledSeedItems(decoder: JSONDecoder = JSONDecoder()) -> [PracticeItem] {
        let data = Bundle.module.url(forResource: "SeedPracticeItems", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        return seedItems(from: data, decoder: decoder)
    }

    static func seedItems(from data: Data?, decoder: JSONDecoder = JSONDecoder()) -> [PracticeItem] {
        guard let data else {
            return []
        }
        return (try? decoder.decode([PracticeItem].self, from: data)) ?? []
    }

    private func loadLegacySavedItems() throws -> [PracticeItem] {
        let primaryURL = try applicationSupportDirectory().appendingPathComponent("PracticeItems.json")
        let legacyURL = try legacyApplicationSupportDirectory().appendingPathComponent("PracticeItems.json")
        let url = fileManager.fileExists(atPath: primaryURL.path) ? primaryURL : legacyURL
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([PracticeItem].self, from: data)
    }

    private func applicationSupportDirectory() throws -> URL {
        try applicationSupportOverride ?? Self.defaultApplicationSupportDirectory(fileManager: fileManager)
    }

    static func defaultApplicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return baseURL.appendingPathComponent("whatever", isDirectory: true)
    }

    private func legacyApplicationSupportDirectory() throws -> URL {
        try legacyApplicationSupportOverride ?? Self.defaultLegacyApplicationSupportDirectory(fileManager: fileManager)
    }

    static func defaultLegacyApplicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return baseURL.appendingPathComponent("EnglishClozeCoach", isDirectory: true)
    }
}
