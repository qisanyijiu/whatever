import Foundation
import SQLite3

enum PracticeLibraryError: LocalizedError {
    case sqlite(String)
    case unsupportedLocalLibraryFile

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "SQLite 题库错误：\(message)"
        case .unsupportedLocalLibraryFile:
            return "本地题库文件格式无效，支持 Decks.json 或 PracticeItems.json。"
        }
    }
}

struct PracticeLibrary: @unchecked Sendable {
    static let sqliteFileName = "PracticeLibrary.sqlite3"
    static let legacyMigrationMarkerFileName = "PracticeLibraryLegacyMigration.done"

    private let fileManager: FileManager
    private let applicationSupportOverride: URL?
    private let legacyApplicationSupportOverride: URL?
    private let seedItemsProvider: () -> [PracticeItem]
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        legacyApplicationSupportDirectory: URL? = nil,
        seedItemsProvider: (() -> [PracticeItem])? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportOverride = applicationSupportDirectory
        self.legacyApplicationSupportOverride = legacyApplicationSupportDirectory
        self.seedItemsProvider = seedItemsProvider ?? {
            Self.bundledSeedItems(decoder: JSONDecoder())
        }
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadDecks() -> [PracticeDeck] {
        if let savedDecks = try? loadSQLiteDecks(), !savedDecks.isEmpty {
            return migrateLegacyFilesIfNeeded(into: savedDecks)
        }

        if let savedDecks = try? loadJSONDecks(), !savedDecks.isEmpty {
            try? save(savedDecks)
            return savedDecks
        }

        if let legacyItems = try? loadLegacySavedItems(), !legacyItems.isEmpty {
            let decks = seedDecks() + [
                PracticeDeck(
                    id: "legacy-saved",
                    name: "本机保存题库",
                    source: "旧版导入数据",
                    createdAt: Date(),
                    updatedAt: Date(),
                    items: legacyItems
                )
            ]
            try? save(decks)
            return decks
        }

        return seedDecks()
    }

    func save(_ decks: [PracticeDeck]) throws {
        let directory = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try SQLitePracticeDatabase(url: sqliteURL(in: directory))
        try database.save(decks, encoder: encoder)
    }

    func exportEncryptedArchive(decks: [PracticeDeck], password: String) throws -> Data {
        try PracticeArchiveService().encrypt(decks: decks, password: password)
    }

    func importEncryptedArchive(_ data: Data, password: String) throws -> [PracticeDeck] {
        try PracticeArchiveService().decryptDecks(from: data, password: password)
    }

    func localLibraryFileDecks(from data: Data, fileName: String) throws -> [PracticeDeck] {
        if let decks = try? decoder.decode([PracticeDeck].self, from: data) {
            guard !decks.isEmpty else {
                return []
            }
            return decks
        }

        if let items = try? decoder.decode([PracticeItem].self, from: data) {
            guard !items.isEmpty else {
                return []
            }
            return [
                legacySavedDeck(
                    items: items,
                    id: "local-file-\(UUID().uuidString)",
                    name: localLibraryName(from: fileName),
                    source: "本地题库文件：\(fileName)"
                )
            ]
        }

        throw PracticeLibraryError.unsupportedLocalLibraryFile
    }

    private func loadSQLiteDecks() throws -> [PracticeDeck] {
        let directory = try applicationSupportDirectory()
        let url = sqliteURL(in: directory)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let database = try SQLitePracticeDatabase(url: url)
        return try database.loadDecks(decoder: decoder)
    }

    private func loadJSONDecks() throws -> [PracticeDeck] {
        var decks: [PracticeDeck] = []
        var firstError: Error?

        for url in try legacyDeckFileURLs() where fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                decks.append(contentsOf: try decoder.decode([PracticeDeck].self, from: data))
            } catch {
                firstError = firstError ?? error
            }
        }

        if !decks.isEmpty {
            return decks
        }
        if let firstError {
            throw firstError
        }
        return []
    }

    private func migrateLegacyFilesIfNeeded(into decks: [PracticeDeck]) -> [PracticeDeck] {
        guard let directory = try? applicationSupportDirectory() else {
            return decks
        }

        let markerURL = directory.appendingPathComponent(Self.legacyMigrationMarkerFileName)
        guard !fileManager.fileExists(atPath: markerURL.path) else {
            return decks
        }

        let legacyDecks = legacyDecksForMigration()
        guard !legacyDecks.isEmpty else {
            return decks
        }

        let mergedDecks = mergeLegacyDecks(legacyDecks, into: decks)
        if mergedDecks != decks {
            do {
                try save(mergedDecks)
            } catch {
                return decks
            }
        }

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data().write(to: markerURL, options: .atomic)
        return mergedDecks
    }

    private func legacyDecksForMigration() -> [PracticeDeck] {
        var decks = (try? loadJSONDecks()) ?? []
        if let legacyItems = try? loadLegacySavedItems(), !legacyItems.isEmpty {
            decks.append(legacySavedDeck(items: legacyItems))
        }
        return decks
    }

    private func mergeLegacyDecks(_ legacyDecks: [PracticeDeck], into decks: [PracticeDeck]) -> [PracticeDeck] {
        var mergedDecks = decks
        var existingItemIDs = Set(decks.flatMap { $0.items.map(\.id) })

        for legacyDeck in legacyDecks where !legacyDeck.items.isEmpty {
            if let deckIndex = mergedDecks.firstIndex(where: { $0.id == legacyDeck.id }) {
                let newItems = legacyDeck.items.filter { item in
                    guard !existingItemIDs.contains(item.id) else {
                        return false
                    }
                    existingItemIDs.insert(item.id)
                    return true
                }

                guard !newItems.isEmpty else {
                    continue
                }
                mergedDecks[deckIndex].items.append(contentsOf: newItems)
                mergedDecks[deckIndex].updatedAt = Date()
            } else {
                legacyDeck.items.forEach { existingItemIDs.insert($0.id) }
                mergedDecks.append(legacyDeck)
            }
        }

        return mergedDecks
    }

    private func seedDecks() -> [PracticeDeck] {
        let items = seedItemsProvider()
        guard !items.isEmpty else {
            return []
        }

        return [
            PracticeDeck(
                id: "seed",
                name: "内置题库",
                source: "应用内置 JSON 资源",
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0),
                items: items
            )
        ]
    }

    static func bundledSeedItems(decoder: JSONDecoder = JSONDecoder()) -> [PracticeItem] {
        let data = Bundle.module.url(forResource: "SeedPracticeItems", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
        return seedItems(from: data, decoder: decoder)
    }

    static func seedItems(from data: Data?, decoder: JSONDecoder = JSONDecoder()) -> [PracticeItem] {
        guard let data else {
            return []
        }
        return (try? decoder.decode([PracticeItem].self, from: data)) ?? []
    }

    private func loadLegacySavedItems() throws -> [PracticeItem] {
        let primaryURL = try applicationSupportDirectory().appendingPathComponent("PracticeItems.json")
        let legacyURL = try legacyApplicationSupportDirectory().appendingPathComponent("PracticeItems.json")
        let url = fileManager.fileExists(atPath: primaryURL.path) ? primaryURL : legacyURL
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([PracticeItem].self, from: data)
    }

    private func legacySavedDeck(
        items: [PracticeItem],
        id: String = "legacy-saved",
        name: String = "本机保存题库",
        source: String = "旧版导入数据"
    ) -> PracticeDeck {
        PracticeDeck(
            id: id,
            name: name,
            source: source,
            createdAt: Date(),
            updatedAt: Date(),
            items: items
        )
    }

    private func localLibraryName(from fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "本地文件题库"
        }
        if trimmed == "PracticeItems.json" {
            return "本地文件题库"
        }

        let url = URL(fileURLWithPath: trimmed)
        let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "本地文件题库" : name
    }

    private func legacyDeckFileURLs() throws -> [URL] {
        let primaryURL = try applicationSupportDirectory().appendingPathComponent("Decks.json")
        let legacyURL = try legacyApplicationSupportDirectory().appendingPathComponent("Decks.json")
        guard primaryURL.path != legacyURL.path else {
            return [primaryURL]
        }
        return [primaryURL, legacyURL]
    }

    private func sqliteURL(in directory: URL) -> URL {
        directory.appendingPathComponent(Self.sqliteFileName)
    }

    private func applicationSupportDirectory() throws -> URL {
        try applicationSupportOverride ?? Self.defaultApplicationSupportDirectory(fileManager: fileManager)
    }

    static func defaultApplicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return baseURL.appendingPathComponent("whatever", isDirectory: true)
    }

    private func legacyApplicationSupportDirectory() throws -> URL {
        if let legacyApplicationSupportOverride {
            return legacyApplicationSupportOverride
        }
        if applicationSupportOverride != nil {
            return try applicationSupportDirectory()
        }
        return try Self.defaultLegacyApplicationSupportDirectory(fileManager: fileManager)
    }

    static func defaultLegacyApplicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return baseURL.appendingPathComponent("EnglishClozeCoach", isDirectory: true)
    }
}

private final class SQLitePracticeDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = Self.errorMessage(from: handle)
            sqlite3_close(handle)
            throw PracticeLibraryError.sqlite(message)
        }
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
    }

    deinit {
        sqlite3_close(handle)
    }

    func loadDecks(decoder: JSONDecoder) throws -> [PracticeDeck] {
        let deckRows = try queryDeckRows()
        guard !deckRows.isEmpty else {
            return []
        }

        var decks: [PracticeDeck] = []
        for row in deckRows {
            decks.append(PracticeDeck(
                id: row.id,
                name: row.name,
                source: row.source,
                createdAt: Date(timeIntervalSince1970: row.createdAt),
                updatedAt: Date(timeIntervalSince1970: row.updatedAt),
                items: try queryItems(deckID: row.id, decoder: decoder)
            ))
        }
        return decks
    }

    func save(_ decks: [PracticeDeck], encoder: JSONEncoder) throws {
        try transaction {
            try execute("DELETE FROM practice_items")
            try execute("DELETE FROM practice_decks")

            for (deckIndex, deck) in decks.enumerated() {
                try insertDeck(deck, sortIndex: deckIndex)
                for (itemIndex, item) in deck.items.enumerated() {
                    try insertItem(item, deckID: deck.id, sortIndex: itemIndex, encoder: encoder)
                }
            }
        }
    }

    private func migrate() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS practice_decks (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                source TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                sort_index INTEGER NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS practice_items (
                deck_id TEXT NOT NULL,
                id TEXT NOT NULL,
                source_chinese TEXT NOT NULL,
                target_english TEXT NOT NULL,
                segments_json BLOB NOT NULL,
                sort_index INTEGER NOT NULL,
                PRIMARY KEY (deck_id, id),
                FOREIGN KEY (deck_id) REFERENCES practice_decks(id) ON DELETE CASCADE
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_practice_items_deck_sort ON practice_items(deck_id, sort_index)")
    }

    private func queryDeckRows() throws -> [DeckRow] {
        let statement = try prepare("""
            SELECT id, name, source, created_at, updated_at
            FROM practice_decks
            ORDER BY sort_index ASC, created_at ASC
            """)
        defer { sqlite3_finalize(statement) }

        var rows: [DeckRow] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            rows.append(DeckRow(
                id: columnString(statement, 0),
                name: columnString(statement, 1),
                source: columnString(statement, 2),
                createdAt: sqlite3_column_double(statement, 3),
                updatedAt: sqlite3_column_double(statement, 4)
            ))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else {
            throw PracticeLibraryError.sqlite(lastErrorMessage())
        }
        return rows
    }

    private func queryItems(deckID: PracticeDeck.ID, decoder: JSONDecoder) throws -> [PracticeItem] {
        let statement = try prepare("""
            SELECT id, source_chinese, target_english, segments_json
            FROM practice_items
            WHERE deck_id = ?
            ORDER BY sort_index ASC
            """)
        defer { sqlite3_finalize(statement) }
        try bind(deckID, to: statement, at: 1)

        var items: [PracticeItem] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let segmentsData = columnData(statement, 3)
            items.append(PracticeItem(
                id: columnString(statement, 0),
                sourceChinese: columnString(statement, 1),
                targetEnglish: columnString(statement, 2),
                segments: try decoder.decode([ClozeSegment].self, from: segmentsData)
            ))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else {
            throw PracticeLibraryError.sqlite(lastErrorMessage())
        }
        return items
    }

    private func insertDeck(_ deck: PracticeDeck, sortIndex: Int) throws {
        let statement = try prepare("""
            INSERT INTO practice_decks (id, name, source, created_at, updated_at, sort_index)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        try bind(deck.id, to: statement, at: 1)
        try bind(deck.name, to: statement, at: 2)
        try bind(deck.source, to: statement, at: 3)
        try bind(deck.createdAt.timeIntervalSince1970, to: statement, at: 4)
        try bind(deck.updatedAt.timeIntervalSince1970, to: statement, at: 5)
        try bind(Int64(sortIndex), to: statement, at: 6)
        try stepDone(statement)
    }

    private func insertItem(
        _ item: PracticeItem,
        deckID: PracticeDeck.ID,
        sortIndex: Int,
        encoder: JSONEncoder
    ) throws {
        let statement = try prepare("""
            INSERT INTO practice_items (
                deck_id, id, source_chinese, target_english, segments_json, sort_index
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        try bind(deckID, to: statement, at: 1)
        try bind(item.id, to: statement, at: 2)
        try bind(item.sourceChinese, to: statement, at: 3)
        try bind(item.targetEnglish, to: statement, at: 4)
        try bind(encoder.encode(item.segments), to: statement, at: 5)
        try bind(Int64(sortIndex), to: statement, at: 6)
        try stepDone(statement)
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? lastErrorMessage()
            sqlite3_free(errorPointer)
            throw PracticeLibraryError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PracticeLibraryError.sqlite(lastErrorMessage())
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PracticeLibraryError.sqlite(lastErrorMessage())
        }
    }

    private func bind(_ value: String, to statement: OpaquePointer?, at index: Int32) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw PracticeLibraryError.sqlite(lastErrorMessage())
        }
    }

    private func bind(_ value: Data, to statement: OpaquePointer?, at index: Int32) throws {
        let status = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), sqliteTransient)
        }
        guard status == SQLITE_OK else {
            throw PracticeLibraryError.sqlite(lastErrorMessage())
        }
    }

    private func bind(_ value: Double, to statement: OpaquePointer?, at index: Int32) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw PracticeLibraryError.sqlite(lastErrorMessage())
        }
    }

    private func bind(_ value: Int64, to statement: OpaquePointer?, at index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw PracticeLibraryError.sqlite(lastErrorMessage())
        }
    }

    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: text)
    }

    private func columnData(_ statement: OpaquePointer?, _ index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func lastErrorMessage() -> String {
        Self.errorMessage(from: handle)
    }

    private static func errorMessage(from handle: OpaquePointer?) -> String {
        guard let message = sqlite3_errmsg(handle) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }

    private struct DeckRow {
        let id: String
        let name: String
        let source: String
        let createdAt: TimeInterval
        let updatedAt: TimeInterval
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
