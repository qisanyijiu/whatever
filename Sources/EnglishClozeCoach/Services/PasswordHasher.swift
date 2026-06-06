import CryptoKit
import Foundation

struct PasswordHasher {
    static func makeSalt() -> String {
        "\(UUID().uuidString)-\(UUID().uuidString)"
    }

    static func hash(password: String, salt: String) -> String {
        let data = Data("\(salt):\(password)".utf8)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", Int($0)) }
            .joined()
    }

    static func verify(password: String, salt: String, hash: String) -> Bool {
        Self.hash(password: password, salt: salt) == hash
    }
}
