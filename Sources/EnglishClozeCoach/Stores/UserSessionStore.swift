import Foundation

final class UserSessionStore: ObservableObject {
    @Published private(set) var accounts: [UserAccount]
    @Published private(set) var currentUser: UserAccount?
    @Published var authError: String?

    private let library: UserAccountLibrary

    init(library: UserAccountLibrary = UserAccountLibrary()) {
        self.library = library
        let loadedAccounts = library.loadAccounts()
        self.accounts = loadedAccounts

        if let activeUserID = library.activeUserID(),
           let account = loadedAccounts.first(where: { $0.id == activeUserID }) {
            self.currentUser = account
        }
    }

    var hasAccounts: Bool {
        !accounts.isEmpty
    }

    @discardableResult
    func createUser(username: String, password: String, confirmation: String) -> Bool {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedUsername.count >= 2 else {
            authError = "用户名至少 2 个字符。"
            return false
        }
        guard password.count >= 4 else {
            authError = "密码至少 4 位。"
            return false
        }
        guard password == confirmation else {
            authError = "两次密码不一致。"
            return false
        }
        guard accounts.allSatisfy({ $0.username.lowercased() != normalizedUsername.lowercased() }) else {
            authError = "这个用户名已存在。"
            return false
        }

        let salt = PasswordHasher.makeSalt()
        let account = UserAccount(
            id: UUID().uuidString,
            username: normalizedUsername,
            passwordSalt: salt,
            passwordHash: PasswordHasher.hash(password: password, salt: salt),
            createdAt: Date(),
            lastLoginAt: Date()
        )

        accounts.append(account)
        do {
            try library.saveAccounts(accounts)
            setCurrentUser(account)
            authError = nil
            return true
        } catch {
            accounts.removeAll { $0.id == account.id }
            authError = "创建用户失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func login(username: String, password: String) -> Bool {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = accounts.firstIndex(where: { $0.username.lowercased() == normalizedUsername.lowercased() }),
              PasswordHasher.verify(
                password: password,
                salt: accounts[index].passwordSalt,
                hash: accounts[index].passwordHash
              ) else {
            authError = "用户名或密码不正确。"
            return false
        }

        accounts[index].lastLoginAt = Date()
        do {
            try library.saveAccounts(accounts)
            setCurrentUser(accounts[index])
            authError = nil
            return true
        } catch {
            authError = "登录失败：\(error.localizedDescription)"
            return false
        }
    }

    func logout() {
        currentUser = nil
        authError = nil
        library.setActiveUserID(nil)
    }

    private func setCurrentUser(_ account: UserAccount) {
        currentUser = account
        library.setActiveUserID(account.id)
    }
}
