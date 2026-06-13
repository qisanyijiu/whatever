import Foundation

enum ApplicationSupport {
    static let directoryName = "whatever"
    static let legacyDirectoryName = "EnglishClozeCoach"

    static func directory(fileManager: FileManager = .default) -> URL {
        (try? requiredDirectory(fileManager: fileManager))
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func requiredDirectory(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return baseURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func legacyDirectory(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return baseURL.appendingPathComponent(legacyDirectoryName, isDirectory: true)
    }
}
