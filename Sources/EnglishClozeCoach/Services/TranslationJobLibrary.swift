import Foundation

struct TranslationJobLibrary: @unchecked Sendable {
    private let fileManager: FileManager
    private let applicationSupportOverride: URL?
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default, applicationSupportDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.applicationSupportOverride = applicationSupportDirectory
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadJobs() -> [TranslationJob] {
        guard let data = try? Data(contentsOf: jobsURL()),
              let jobs = try? decoder.decode([TranslationJob].self, from: data) else {
            return []
        }
        return jobs
    }

    func save(_ jobs: [TranslationJob]) throws {
        try fileManager.createDirectory(at: applicationSupportDirectory(), withIntermediateDirectories: true)
        let data = try encoder.encode(jobs)
        try data.write(to: jobsURL(), options: .atomic)
    }

    private func jobsURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("TranslationJobs.json")
    }

    private func applicationSupportDirectory() -> URL {
        applicationSupportOverride ?? Self.defaultApplicationSupportDirectory(fileManager: fileManager)
    }

    static func defaultApplicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let baseURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? fileManager.homeDirectoryForCurrentUser

        return baseURL.appendingPathComponent("whatever", isDirectory: true)
    }
}
