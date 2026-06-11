import Foundation

struct UserAccountLibrary: @unchecked Sendable {
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let applicationSupportOverride: URL?
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder
    private let activeUserIDKey = "whatever.activeUserID"

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        applicationSupportDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.applicationSupportOverride = applicationSupportDirectory
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadAccounts() -> [UserAccount] {
        guard let data = try? Data(contentsOf: accountsURL()),
              let accounts = try? decoder.decode([UserAccount].self, from: data) else {
            return []
        }
        return accounts
    }

    func saveAccounts(_ accounts: [UserAccount]) throws {
        try fileManager.createDirectory(at: applicationSupportDirectory(), withIntermediateDirectories: true)
        let data = try encoder.encode(accounts)
        try data.write(to: accountsURL(), options: .atomic)
    }

    func activeUserID() -> String? {
        userDefaults.string(forKey: activeUserIDKey)
    }

    func setActiveUserID(_ id: String?) {
        if let id {
            userDefaults.set(id, forKey: activeUserIDKey)
        } else {
            userDefaults.removeObject(forKey: activeUserIDKey)
        }
    }

    private func accountsURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("Users.json")
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
