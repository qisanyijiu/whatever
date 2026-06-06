import Foundation

struct UserAccount: Identifiable, Hashable, Codable {
    let id: String
    var username: String
    var passwordSalt: String
    var passwordHash: String
    var createdAt: Date
    var lastLoginAt: Date?
}
