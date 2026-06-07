import Foundation
import Security

protocol SecretStore {
    func read(account: String) -> String?
    func save(_ value: String, account: String) throws
    func delete(account: String) throws
}

struct KeychainService: SecretStore {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return message
                }
                return "Keychain 操作失败：\(status)"
            }
        }
    }

    let service: String

    func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func save(_ value: String, account: String) throws {
        try delete(account: account)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
