import Foundation

struct UserAccountLibrary {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder
    private let activeUserIDKey = "whatever.activeUserID"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
        UserDefaults.standard.string(forKey: activeUserIDKey)
    }

    func setActiveUserID(_ id: String?) {
        if let id {
            UserDefaults.standard.set(id, forKey: activeUserIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeUserIDKey)
        }
    }

    private func accountsURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("Users.json")
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
