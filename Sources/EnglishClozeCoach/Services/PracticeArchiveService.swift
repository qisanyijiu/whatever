import CryptoKit
import Foundation

enum PracticeArchiveError: LocalizedError {
    case emptyPassword
    case invalidFormat
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "请输入导入/导出密码。"
        case .invalidFormat:
            return "加密题库文件格式无效，或密码不正确。"
        case .encryptionFailed:
            return "加密题库失败。"
        }
    }
}

struct PracticeArchiveService {
    static let fileExtension = "eccbin"

    private static let magic = Data([0x45, 0x43, 0x43, 0x4C, 0x49, 0x42, 0x31, 0x00])
    private static let saltLength = 16

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func encrypt(decks: [PracticeDeck], password: String) throws -> Data {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            throw PracticeArchiveError.emptyPassword
        }

        let payload = PracticeArchivePayload(version: 1, exportedAt: Date(), decks: decks)
        let payloadData = try encoder.encode(payload)
        let salt = randomData(count: Self.saltLength)
        let nonceData = randomData(count: 12)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let key = deriveKey(password: trimmedPassword, salt: salt)
        let sealedBox = try AES.GCM.seal(payloadData, using: key, nonce: nonce)
        guard let combined = sealedBox.combined else {
            throw PracticeArchiveError.encryptionFailed
        }

        var result = Data()
        result.append(Self.magic)
        result.append(salt)
        result.append(combined)
        return result
    }

    func decryptDecks(from data: Data, password: String) throws -> [PracticeDeck] {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            throw PracticeArchiveError.emptyPassword
        }
        guard data.count > Self.magic.count + Self.saltLength,
              data.prefix(Self.magic.count) == Self.magic else {
            throw PracticeArchiveError.invalidFormat
        }

        let saltStart = Self.magic.count
        let saltEnd = saltStart + Self.saltLength
        let salt = data[saltStart..<saltEnd]
        let encryptedPayload = data[saltEnd..<data.count]
        let key = deriveKey(password: trimmedPassword, salt: Data(salt))

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedPayload)
            let payloadData = try AES.GCM.open(sealedBox, using: key)
            let payload = try decoder.decode(PracticeArchivePayload.self, from: payloadData)
            guard payload.version == 1 else {
                throw PracticeArchiveError.invalidFormat
            }
            return payload.decks
        } catch {
            throw PracticeArchiveError.invalidFormat
        }
    }

    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(password.utf8)),
            salt: salt,
            info: Data("EnglishClozeCoachPracticeArchive".utf8),
            outputByteCount: 32
        )
    }

    private func randomData(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
    }
}

private struct PracticeArchivePayload: Codable {
    let version: Int
    let exportedAt: Date
    let decks: [PracticeDeck]
}
