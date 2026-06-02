import Foundation

struct PracticeLibrary {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadItems() -> [PracticeItem] {
        if let savedItems = try? loadSavedItems(), !savedItems.isEmpty {
            return savedItems
        }
        return loadSeedItems()
    }

    func save(_ items: [PracticeItem]) throws {
        let directory = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(items)
        try data.write(to: directory.appendingPathComponent("PracticeItems.json"), options: .atomic)
    }

    private func loadSeedItems() -> [PracticeItem] {
        guard let url = Bundle.module.url(forResource: "SeedPracticeItems", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? decoder.decode([PracticeItem].self, from: data) else {
            return []
        }
        return items
    }

    private func loadSavedItems() throws -> [PracticeItem] {
        let url = try applicationSupportDirectory().appendingPathComponent("PracticeItems.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([PracticeItem].self, from: data)
    }

    private func applicationSupportDirectory() throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL.appendingPathComponent("EnglishClozeCoach", isDirectory: true)
    }
}
