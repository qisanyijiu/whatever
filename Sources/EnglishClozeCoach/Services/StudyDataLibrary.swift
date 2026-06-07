import Foundation

struct StudyDataLibrary {
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

    func load(userID: String) throws -> UserStudyData {
        let url = studyDataURL(userID: userID)
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty(userID: userID)
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(UserStudyData.self, from: data)
    }

    func save(_ data: UserStudyData) throws {
        let directory = userDirectory(userID: data.userID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = try encoder.encode(data)
        try encoded.write(to: directory.appendingPathComponent("StudyData.json"), options: .atomic)
    }

    private func studyDataURL(userID: String) -> URL {
        userDirectory(userID: userID).appendingPathComponent("StudyData.json")
    }

    private func userDirectory(userID: String) -> URL {
        applicationSupportDirectory()
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent(userID, isDirectory: true)
    }

    private func applicationSupportDirectory() -> URL {
        if let applicationSupportOverride {
            return applicationSupportOverride
        }

        let baseURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser

        return baseURL.appendingPathComponent("whatever", isDirectory: true)
    }
}
