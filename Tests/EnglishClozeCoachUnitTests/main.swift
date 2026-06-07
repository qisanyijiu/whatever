import Darwin
import Foundation
@testable import EnglishClozeCoach

struct UnitTest: @unchecked Sendable {
    let name: String
    let run: () throws -> Void
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let file: StaticString
    let line: UInt

    var description: String {
        "\(file):\(line): \(message)"
    }
}

func expect(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String = "Expectation failed",
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    if try !condition() {
        throw TestFailure(message: message, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(
    _ left: @autoclosure () throws -> T,
    _ right: @autoclosure () throws -> T,
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    let leftValue = try left()
    let rightValue = try right()
    if leftValue != rightValue {
        throw TestFailure(
            message: "Expected \(leftValue) to equal \(rightValue)",
            file: file,
            line: line
        )
    }
}

func require<T>(
    _ value: @autoclosure () throws -> T?,
    _ message: String = "Required value was nil",
    file: StaticString = #fileID,
    line: UInt = #line
) throws -> T {
    guard let value = try value() else {
        throw TestFailure(message: message, file: file, line: line)
    }
    return value
}

func fail(_ message: String, file: StaticString = #fileID, line: UInt = #line) throws -> Never {
    throw TestFailure(message: message, file: file, line: line)
}

func runAsync(_ operation: @escaping @Sendable () async throws -> Void) throws {
    let semaphore = DispatchSemaphore(value: 0)
    let box = AsyncResultBox()

    Task.detached {
        do {
            try await operation()
            box.result = .success(())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()
    try box.result?.get()
}

final class AsyncResultBox: @unchecked Sendable {
    var result: Result<Void, Error>?
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("whatever-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func removeTemporaryDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

func sampleItem(id: String = "item-1") -> PracticeItem {
    PracticeItem(
        id: id,
        sourceChinese: "我今天下午要和朋友见面。",
        targetEnglish: "I am going to meet my friend this afternoon.",
        segments: [
            .text("I am going to "),
            .blank(ClozeBlank(id: "\(id)-blank-1", answer: "meet")),
            .text(" my friend this "),
            .blank(ClozeBlank(id: "\(id)-blank-2", answer: "afternoon")),
            .text(".")
        ]
    )
}

func sampleDeck(id: String = "deck-1", items: [PracticeItem]? = nil) -> PracticeDeck {
    PracticeDeck(
        id: id,
        name: "测试题库",
        source: "unit-test",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        items: items ?? [sampleItem()]
    )
}

struct FixedTranslationService: TranslationService {
    let value: String

    func translate(english: String) -> String {
        value
    }
}

let coreLearningTests: [UnitTest] = [
    UnitTest(name: "Configuration and draft models expose derived values") {
        let readyProvider = AIProviderConfig(
            id: "ready",
            name: "AI",
            baseURL: "https://example.com/v1",
            model: "model",
            apiKey: "key",
            createdAt: Date(),
            updatedAt: Date()
        )
        let incompleteProvider = AIProviderConfig(
            id: "not-ready",
            name: "AI",
            baseURL: " ",
            model: "model",
            apiKey: "key",
            createdAt: Date(),
            updatedAt: Date()
        )
        let draftItem = ImportDraftItem(
            id: "draft",
            sourceChinese: "中文",
            targetEnglish: "Practice builds confidence.",
            blankText: " Practice,  confidence ,, "
        )

        try expect(readyProvider.isReady)
        try expect(!incompleteProvider.isReady)
        try expectEqual(AIProviderSettings.empty.providers.count, 0)
        try expectEqual(draftItem.blankAnswers, ["Practice", "confidence"])
        try expectEqual(PlaceholderTranslationService().translate(english: "Hello"), "待翻译")
    },
    UnitTest(name: "ClozeGenerator creates one-based blank IDs") {
        let itemID = "generated-item"
        let segments = ClozeGenerator().segments(
            from: "Curiosity makes difficult practice feel meaningful.",
            itemID: itemID
        )
        let blanks = blanks(from: segments)

        try expect(!blanks.isEmpty)
        try expectEqual(blanks.first?.id, "\(itemID)-blank-1")
        try expect(!blanks.contains { $0.id.hasSuffix("blank-0") })
        try expectEqual(renderedSentence(from: segments), "Curiosity makes difficult practice feel meaningful.")
    },
    UnitTest(name: "ClozeGenerator uses manual blanks in sentence order") {
        let segments = ClozeGenerator().segments(
            from: "Could you send me the document after the meeting?",
            itemID: "manual",
            blankAnswers: ["document", "send"]
        )
        let blanks = blanks(from: segments)

        try expectEqual(blanks.map(\.answer), ["send", "document"])
        try expectEqual(blanks.map(\.id), ["manual-blank-1", "manual-blank-2"])
    },
    UnitTest(name: "ClozeGenerator falls back when manual blanks are missing") {
        let segments = ClozeGenerator().segments(
            from: "Practice builds durable confidence.",
            itemID: "fallback",
            blankAnswers: ["nonexistent"]
        )

        try expect(!blanks(from: segments).isEmpty)
    },
    UnitTest(name: "QuestionImporter creates editable draft from English text") {
        let importer = QuestionImporter(translationService: FixedTranslationService(value: "中文占位"))
        let draft = try require(importer.importDraft(
            from: "This is too short. Deliberate practice improves fluent speaking! 中文不会生成题。",
            name: "导入",
            source: "paste"
        ))

        try expectEqual(draft.name, "导入")
        try expectEqual(draft.source, "paste")
        try expectEqual(draft.items.count, 2)
        try expect(draft.items.allSatisfy { $0.sourceChinese == "中文占位" })
        try expect(draft.items.allSatisfy { !$0.blankText.isEmpty })
    },
    UnitTest(name: "QuestionImporter builds practice items from edited draft") {
        let draft = ImportDraft(
            name: "TED",
            source: "paste",
            items: [
                ImportDraftItem(
                    id: "draft-1",
                    sourceChinese: "练习会增强信心。",
                    targetEnglish: "Practice builds confidence.",
                    blankText: "Practice, confidence"
                ),
                ImportDraftItem(id: "empty", sourceChinese: "空句子", targetEnglish: "   ", blankText: "missing")
            ]
        )

        let items = QuestionImporter().practiceItems(from: draft)

        try expectEqual(items.count, 1)
        try expectEqual(items[0].id, "draft-1")
        try expectEqual(items[0].sourceChinese, "练习会增强信心。")
        try expectEqual(items[0].targetEnglish, "Practice builds confidence.")
        try expectEqual(items[0].blanks.map(\.id), ["draft-1-blank-1", "draft-1-blank-2"])
    },
    UnitTest(name: "AnswerMatcher accepts useful variants") {
        let matcher = AnswerMatcher()

        try expect(matcher.matches("  MEET  ", answer: "meet"))
        try expect(matcher.matches("I’m ready", answer: "I am ready"))
        try expect(matcher.matches("well-known", answer: "well known"))
        try expect(matcher.matches("meeting", answer: "meet"))
        try expect(matcher.matches("confidense", answer: "confidence"))
        try expect(!matcher.matches("", answer: "meet"))
        try expect(!matcher.matches("coffee", answer: "document"))
    },
    UnitTest(name: "AnswerExplanationService uses one-based blank numbers") {
        let item = sampleItem()
        let explanation = AnswerExplanationService().explanation(
            for: item,
            answers: [
                "item-1-blank-1": "wrong",
                "item-1-blank-2": "afternoon"
            ]
        )

        try expect(explanation.contains("空位 1：meet"))
        try expect(explanation.contains("空位 2：afternoon"))
        try expect(!explanation.contains("空位 0"))
    },
    UnitTest(name: "PracticeItem codable round trip keeps segments") {
        let item = sampleItem()
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(PracticeItem.self, from: data)

        try expectEqual(decoded, item)
        try expectEqual(decoded.blanks.map(\.answer), ["meet", "afternoon"])
    }
]

let practiceStoreTests: [UnitTest] = [
    UnitTest(name: "PracticeLibrary loads saved decks before seed decks") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let library = PracticeLibrary(applicationSupportDirectory: directory)
        try library.save([sampleDeck(id: "saved")])

        let loadedDecks = library.loadDecks()

        try expectEqual(loadedDecks.map(\.id), ["saved"])
        try expectEqual(loadedDecks[0].items[0].targetEnglish, sampleItem().targetEnglish)
    },
    UnitTest(name: "PracticeLibrary migrates legacy flat saved items") {
        let directory = try temporaryDirectory()
        let legacyDirectory = try temporaryDirectory()
        defer {
            removeTemporaryDirectory(directory)
            removeTemporaryDirectory(legacyDirectory)
        }
        let legacyData = try JSONEncoder().encode([sampleItem(id: "legacy-item")])
        try legacyData.write(to: legacyDirectory.appendingPathComponent("PracticeItems.json"))

        let library = PracticeLibrary(
            applicationSupportDirectory: directory,
            legacyApplicationSupportDirectory: legacyDirectory
        )
        let loadedDecks = library.loadDecks()

        try expect(loadedDecks.contains { $0.id == "seed" })
        try expect(loadedDecks.contains { $0.id == "legacy-saved" })
        try expectEqual(loadedDecks.first { $0.id == "legacy-saved" }?.items.first?.id, "legacy-item")
    },
    UnitTest(name: "PracticeStore selects deck and tracks answers") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let firstItem = sampleItem(id: "item-a")
        let secondItem = PracticeItem(
            id: "item-b",
            sourceChinese: "请发送文件。",
            targetEnglish: "Please send the document.",
            segments: [
                .text("Please "),
                .blank(ClozeBlank(id: "item-b-blank-1", answer: "send")),
                .text(" the "),
                .blank(ClozeBlank(id: "item-b-blank-2", answer: "document")),
                .text(".")
            ]
        )
        let library = PracticeLibrary(applicationSupportDirectory: directory)
        try library.save([
            sampleDeck(id: "deck-a", items: [firstItem]),
            sampleDeck(id: "deck-b", items: [secondItem])
        ])

        let store = PracticeStore(library: library)
        store.selectDeck("deck-b")

        try expectEqual(store.selectedDeckID, "deck-b")
        try expectEqual(store.selectedItem?.id, "item-b")
        try expect(!store.canAdvance)

        store.setAnswer("send", for: secondItem.blanks[0])
        store.setAnswer("wrong", for: secondItem.blanks[1])
        try expect(store.answerState(for: secondItem.blanks[0]) == .correct)
        try expect(store.answerState(for: secondItem.blanks[1]) == .incorrect)
        try expect(!store.isCompleted(secondItem))

        store.setAnswer("document", for: secondItem.blanks[1])
        try expect(store.isCompleted(secondItem))

        store.resetCurrentAnswers()
        try expectEqual(store.answerText(for: secondItem.blanks[0]), "")
        try expect(store.answerState(for: secondItem.blanks[0]) == .idle)
    },
    UnitTest(name: "PracticeStore custom practice navigation returns to deck") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let library = PracticeLibrary(applicationSupportDirectory: directory)
        try library.save([sampleDeck(id: "main", items: [sampleItem(id: "main-item")])])
        let store = PracticeStore(library: library)
        let customItems = [sampleItem(id: "custom-1"), sampleItem(id: "custom-2")]

        store.startCustomPractice(items: customItems, title: "错题复习")
        try expectEqual(store.currentPracticeTitle, "错题复习")
        try expectEqual(store.selectedItemID, "custom-1")
        try expect(store.canAdvance)

        store.advance()
        try expectEqual(store.selectedItemID, "custom-2")
        try expect(store.canGoBack)

        store.goBack()
        try expectEqual(store.selectedItemID, "custom-1")

        store.returnToSelectedDeck()
        try expectEqual(store.selectedDeckID, "main")
        try expectEqual(store.selectedItemID, "main-item")
    },
    UnitTest(name: "PracticeStore saves import draft as new deck") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = PracticeStore(library: PracticeLibrary(applicationSupportDirectory: directory))
        let initialDeckCount = store.decks.count
        let draft = ImportDraft(
            name: " 导入题库 ",
            source: "paste",
            items: [
                ImportDraftItem(
                    id: "draft-1",
                    sourceChinese: "练习会增强信心。",
                    targetEnglish: "Practice builds confidence.",
                    blankText: "Practice"
                )
            ]
        )

        let savedCount = store.saveImportDraft(draft)

        try expectEqual(savedCount, 1)
        try expectEqual(store.decks.count, initialDeckCount + 1)
        try expectEqual(store.selectedDeck?.name, "导入题库")
        try expectEqual(store.selectedDeck?.source, "paste")
        try expectEqual(store.selectedItem?.id, "draft-1")
        try expect(store.librarySummaries.contains { $0.id == store.selectedDeckID && $0.itemCount == 1 })
    },
    UnitTest(name: "PracticeStore renames updates deletes deck and items") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = PracticeStore(library: PracticeLibrary(applicationSupportDirectory: directory))
        let draft = ImportDraft(
            name: "可编辑",
            source: "unit",
            items: [
                ImportDraftItem(
                    id: "editable-1",
                    sourceChinese: "旧中文",
                    targetEnglish: "Practice builds confidence.",
                    blankText: "Practice"
                )
            ]
        )
        _ = store.saveImportDraft(draft)
        let deckID = try require(store.selectedDeckID)

        store.renameDeck(deckID, name: "新题库")
        try expectEqual(store.selectedDeck?.name, "新题库")

        store.updateItem(
            "editable-1",
            in: deckID,
            sourceChinese: "新中文",
            targetEnglish: "Confidence grows with practice.",
            blankText: "Confidence, practice"
        )
        try expectEqual(store.selectedItem?.sourceChinese, "新中文")
        try expectEqual(store.selectedItem?.blanks.map(\.answer), ["Confidence", "practice"])

        store.deleteItem("editable-1", in: deckID)
        try expect(store.selectedDeck?.items.isEmpty == true)

        let seedDeckID = try require(store.decks.first { $0.id != deckID }?.id)
        store.selectDeck(seedDeckID)
        store.deleteDeck(deckID)
        try expect(!store.decks.contains { $0.id == deckID })
    }
]

let userStudyAndAITests: [UnitTest] = [
    UnitTest(name: "UserSessionStore creates persists logs in and logs out") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let suiteName = "whatever.tests.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let library = UserAccountLibrary(userDefaults: defaults, applicationSupportDirectory: directory)
        let store = UserSessionStore(library: library)

        try expect(!store.createUser(username: "a", password: "1234", confirmation: "1234"))
        try expect(!store.createUser(username: "li", password: "123", confirmation: "123"))
        try expect(!store.createUser(username: "li", password: "1234", confirmation: "4321"))

        try expect(store.createUser(username: " Li ", password: "1234", confirmation: "1234"))
        try expect(store.hasAccounts)
        try expectEqual(store.currentUser?.username, "Li")
        try expect(!store.createUser(username: "li", password: "5678", confirmation: "5678"))

        store.logout()
        try expect(store.currentUser == nil)
        try expect(!store.login(username: "Li", password: "wrong"))
        try expect(store.login(username: "li", password: "1234"))
        try expectEqual(store.currentUser?.username, "Li")

        let reloadedStore = UserSessionStore(library: library)
        try expectEqual(reloadedStore.currentUser?.username, "Li")
    },
    UnitTest(name: "PasswordHasher salts and verifies passwords") {
        let firstSalt = PasswordHasher.makeSalt()
        let secondSalt = PasswordHasher.makeSalt()
        let firstHash = PasswordHasher.hash(password: "secret", salt: firstSalt)
        let secondHash = PasswordHasher.hash(password: "secret", salt: secondSalt)

        try expect(firstSalt != secondSalt)
        try expect(firstHash != secondHash)
        try expect(PasswordHasher.verify(password: "secret", salt: firstSalt, hash: firstHash))
        try expect(!PasswordHasher.verify(password: "wrong", salt: firstSalt, hash: firstHash))
    },
    UnitTest(name: "StudyDataLibrary saves loads and decodes old data") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let library = StudyDataLibrary(applicationSupportDirectory: directory)
        let userID = "user-1"

        try expectEqual(try library.load(userID: userID).dailyGoal, 10)

        var data = UserStudyData.empty(userID: userID)
        data.dailyGoal = 25
        data.reminderEnabled = true
        data.reminderHour = 7
        data.reminderMinute = 30
        try library.save(data)

        let loaded = try library.load(userID: userID)
        try expectEqual(loaded.dailyGoal, 25)
        try expect(loaded.reminderEnabled)
        try expectEqual(loaded.reminderHour, 7)
        try expectEqual(loaded.reminderMinute, 30)

        let oldJSON = """
        {
          "userID": "legacy",
          "completedItemIDs": ["a"],
          "history": [],
          "mistakes": [],
          "reviewStates": [],
          "dailyGoal": 12,
          "updatedAt": 0
        }
        """
        let legacy = try JSONDecoder().decode(UserStudyData.self, from: Data(oldJSON.utf8))
        try expect(!legacy.reminderEnabled)
        try expectEqual(legacy.reminderHour, 20)
        try expectEqual(legacy.reminderMinute, 0)
    },
    UnitTest(name: "StudyStore records completion mistakes and review queues") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let studyStore = StudyStore(
            library: StudyDataLibrary(applicationSupportDirectory: directory),
            reminderService: StudyReminderService(schedulesNotifications: false)
        )
        let user = UserAccount(
            id: "user-1",
            username: "Li",
            passwordSalt: "salt",
            passwordHash: "hash",
            createdAt: Date(),
            lastLoginAt: nil
        )
        let item = sampleItem(id: "study-item")

        studyStore.load(for: user)
        studyStore.updateDailyGoal(2)
        studyStore.updateDailyReminder(enabled: true)
        studyStore.updateReminderTime(time(hour: 6, minute: 45))
        try expectEqual(studyStore.data.dailyGoal, 2)
        try expect(studyStore.data.reminderEnabled)
        try expectEqual(studyStore.data.reminderHour, 6)
        try expectEqual(studyStore.data.reminderMinute, 45)

        studyStore.recordMistake(item: item, blank: item.blanks[0], wrongAnswer: "met")
        studyStore.recordMistake(item: item, blank: item.blanks[0], wrongAnswer: "mate")
        try expectEqual(studyStore.frequentMistakes.first?.mistakeCount, 2)
        try expectEqual(studyStore.mistakeItems(from: [item]).map(\.id), [item.id])

        studyStore.recordCompletion(item: item, wrongBlankCount: 1)
        try expectEqual(studyStore.completedCount, 1)
        try expectEqual(studyStore.todayCompletedCount, 1)
        try expectEqual(studyStore.currentStreak, 1)
        try expectEqual(studyStore.dailyGoalProgress, 0.5)
        try expectEqual(studyStore.dueItems(from: [item], on: Date().addingTimeInterval(1)).map(\.id), [item.id])
        try expectEqual(studyStore.weeklySummaries.count, 7)
        try expectEqual(studyStore.weeklySummaries.last?.completedCount, 1)

        studyStore.clear()
        try expectEqual(studyStore.completedCount, 0)
    },
    UnitTest(name: "AIProviderStore persists profiles and keeps secrets out of JSON") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let secretStore = InMemorySecretStore()
        let library = AIProviderLibrary(secretStore: secretStore, applicationSupportDirectory: directory)
        let provider = AIProviderConfig(
            id: "provider-1",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: "secret-key",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        try library.save(AIProviderSettings(activeProviderID: provider.id, providers: [provider]))
        let rawJSON = try String(contentsOf: directory.appendingPathComponent("AIProviders.json"), encoding: .utf8)
        try expect(!rawJSON.contains("secret-key"))
        try expectEqual(secretStore.values[provider.id], "secret-key")

        let loaded = library.load()
        try expectEqual(loaded.activeProviderID, provider.id)
        try expectEqual(loaded.providers.first?.apiKey, "secret-key")

        let store = AIProviderStore(library: library)
        try expectEqual(store.activeProvider?.name, "OpenAI")
        store.selectProvider(provider.id)
        var editedProvider = provider
        editedProvider.name = "Edited"
        editedProvider.apiKey = "new-secret"
        store.saveProvider(editedProvider)
        try expectEqual(secretStore.values[provider.id], "new-secret")
        try expectEqual(store.activeProvider?.name, "Edited")

        store.deleteProvider(provider.id)
        try expect(secretStore.values[provider.id] == nil)
        try expect(store.providers.isEmpty)
    },
    UnitTest(name: "AIProviderLibrary migrates legacy JSON secrets") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let secretStore = InMemorySecretStore()
        let legacyJSON = """
        {
          "activeProviderID": "legacy",
          "providers": [
            {
              "id": "legacy",
              "name": "Legacy",
              "baseURL": "https://example.com/v1",
              "model": "model",
              "apiKey": "legacy-secret",
              "createdAt": 1,
              "updatedAt": 1
            }
          ]
        }
        """
        try legacyJSON.write(
            to: directory.appendingPathComponent("AIProviders.json"),
            atomically: true,
            encoding: .utf8
        )

        let library = AIProviderLibrary(secretStore: secretStore, applicationSupportDirectory: directory)
        let settings = library.load()

        try expectEqual(settings.providers.first?.apiKey, "legacy-secret")
        try expectEqual(secretStore.values["legacy"], "legacy-secret")
        let sanitizedJSON = try String(contentsOf: directory.appendingPathComponent("AIProviders.json"), encoding: .utf8)
        try expect(!sanitizedJSON.contains("legacy-secret"))
    }
]

let aiTextServiceTests: [UnitTest] = [
    UnitTest(name: "AITextService translates JSON response in order") {
        let client = FakeAICompletionClient(response: #"["你好。","再见。"]"#)
        let service = AITextService(client: client)

        try runAsync {
            let translations = try await service.translateEnglishToChinese(
                ["Hello.", "Goodbye."],
                using: readyProvider()
            )

            try expectEqual(translations, ["你好。", "再见。"])
            try expect(client.lastSystemPrompt?.contains("JSON array") == true)
            try expect(client.lastUserPrompt?.contains("1. Hello.") == true)
            try expect(client.lastUserPrompt?.contains("2. Goodbye.") == true)
        }
    },
    UnitTest(name: "AITextService translates numbered lines as fallback") {
        let client = FakeAICompletionClient(response: "1. 第一条\n2. 第二条")
        let service = AITextService(client: client)

        try runAsync {
            let translations = try await service.translateEnglishToChinese(
                ["First.", "Second."],
                using: readyProvider()
            )

            try expectEqual(translations, ["第一条", "第二条"])
        }
    },
    UnitTest(name: "AITextService throws on translation count mismatch") {
        let service = AITextService(client: FakeAICompletionClient(response: #"["只有一条"]"#))

        try runAsync {
            do {
                _ = try await service.translateEnglishToChinese(["One.", "Two."], using: readyProvider())
                try fail("Expected translation count mismatch")
            } catch let error as AITextServiceError {
                try expectEqual(error.localizedDescription, "AI 返回的翻译数量不匹配，期望 2 条，实际 1 条。")
            }
        }
    },
    UnitTest(name: "AITextService skips empty translation input") {
        let client = FakeAICompletionClient(response: "should not be used")
        let service = AITextService(client: client)

        try runAsync {
            let translations = try await service.translateEnglishToChinese(["  ", "\n"], using: readyProvider())

            try expectEqual(translations, [])
            try expect(client.lastUserPrompt == nil)
        }
    },
    UnitTest(name: "AITextService explains with one-based blank numbers") {
        let client = FakeAICompletionClient(response: "### 空位 1\n解释")
        let service = AITextService(client: client)
        let item = sampleItem()

        try runAsync {
            let explanation = try await service.explainAnswer(
                for: item,
                answers: ["item-1-blank-1": "met"],
                using: readyProvider()
            )

            try expectEqual(explanation, "### 空位 1\n解释")
            try expect(client.lastUserPrompt?.contains("空位 1") == true)
            try expect(client.lastUserPrompt?.contains("空位 2") == true)
            try expect(client.lastUserPrompt?.contains("blank-0") != true)
            try expect(client.lastSystemPrompt?.contains("simple Markdown") == true)
        }
    },
    UnitTest(name: "OpenAICompatibleAIClient rejects incomplete provider before network") {
        try runAsync {
            do {
                _ = try await OpenAICompatibleAIClient().complete(
                    provider: AIProviderConfig(
                        id: "bad",
                        name: "",
                        baseURL: "",
                        model: "",
                        apiKey: "",
                        createdAt: Date(),
                        updatedAt: Date()
                    ),
                    systemPrompt: "system",
                    userPrompt: "user"
                )
                try fail("Expected provider not ready")
            } catch let error as AITextServiceError {
                try expectEqual(error.localizedDescription, "当前 AI 配置不完整。")
            }
        }
    }
]

func blanks(from segments: [ClozeSegment]) -> [ClozeBlank] {
    segments.compactMap { segment in
        if case let .blank(blank) = segment {
            return blank
        }
        return nil
    }
}

func renderedSentence(from segments: [ClozeSegment]) -> String {
    segments.map { segment in
        switch segment {
        case let .text(text):
            return text
        case let .blank(blank):
            return blank.answer
        }
    }
    .joined()
}

func time(hour: Int, minute: Int) -> Date {
    var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    components.hour = hour
    components.minute = minute
    return Calendar.current.date(from: components) ?? Date()
}

func readyProvider() -> AIProviderConfig {
    AIProviderConfig(
        id: "ai-1",
        name: "Test",
        baseURL: "https://example.com/v1",
        model: "test-model",
        apiKey: "secret",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}

private final class FakeAICompletionClient: AICompletionClient, @unchecked Sendable {
    let response: String
    var lastSystemPrompt: String?
    var lastUserPrompt: String?

    init(response: String) {
        self.response = response
    }

    func complete(provider: AIProviderConfig, systemPrompt: String, userPrompt: String) async throws -> String {
        lastSystemPrompt = systemPrompt
        lastUserPrompt = userPrompt
        return response
    }
}

private final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func read(account: String) -> String? {
        values[account]
    }

    func save(_ value: String, account: String) throws {
        values[account] = value
    }

    func delete(account: String) throws {
        values[account] = nil
    }
}

let runUnitTestsAtLoad: Void = {
    let tests = coreLearningTests + practiceStoreTests + userStudyAndAITests + aiTextServiceTests
    var failureCount = 0

    for test in tests {
        do {
            try test.run()
            print("✓ \(test.name)")
        } catch {
            failureCount += 1
            print("✗ \(test.name)")
            print("  \(error)")
        }
    }

    print("\n\(tests.count - failureCount)/\(tests.count) tests passed")
    if failureCount > 0 {
        exit(1)
    }
}()
