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
        try expect(!ImportDraft(name: "Draft", source: "unit", items: [draftItem]).id.isEmpty)
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
    UnitTest(name: "ClozeGenerator handles no words and stop word fallback") {
        let emptySegments = ClozeGenerator().segments(from: "1234 !!!", itemID: "empty")
        try expectEqual(emptySegments, [.text("1234 !!!")])

        let stopWordSegments = ClozeGenerator().segments(from: "I am at the sea.", itemID: "stops")
        try expectEqual(blanks(from: stopWordSegments).count, 1)

        let multiBlankSegments = ClozeGenerator().segments(
            from: "Curiosity improves deliberate listening and thoughtful repetition daily.",
            itemID: "multi"
        )
        try expect(blanks(from: multiBlankSegments).count >= 2)
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
    UnitTest(name: "QuestionImporter imports direct items and reports empty drafts") {
        let importer = QuestionImporter(translationService: FixedTranslationService(value: "中文"))

        try expect(importer.importDraft(from: "12345。没有英文。", name: "空", source: "unit") == nil)

        let items = importer.importItems(
            from: "Focused listening improves pronunciation. Repetition turns phrases into habits."
        )

        try expectEqual(items.count, 2)
        try expect(items.allSatisfy { $0.sourceChinese == "中文" })
        try expect(items.allSatisfy { !$0.blanks.isEmpty })
        try expectEqual(items.map(\.targetEnglish), [
            "Focused listening improves pronunciation.",
            "Repetition turns phrases into habits."
        ])

        let noBlankItems = importer.practiceItems(
            from: ImportDraft(
                name: "No blanks",
                source: "unit",
                items: [
                    ImportDraftItem(
                        id: "numbers",
                        sourceChinese: "数字",
                        targetEnglish: "1234 !!!",
                        blankText: ""
                    )
                ]
            )
        )
        try expect(noBlankItems.isEmpty)
    },
    UnitTest(name: "FolderTextImporter recursively imports supported English files") {
        let directory = try temporaryDirectory().appendingPathComponent("Course Pack", isDirectory: true)
        defer { removeTemporaryDirectory(directory.deletingLastPathComponent()) }
        let nestedDirectory = directory.appendingPathComponent("Week 1", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        try """
        Deliberate practice builds confidence because learners notice useful patterns quickly.
        Reflection turns difficult sentences into reusable speaking habits.
        """.write(
            to: directory.appendingPathComponent("lesson.txt"),
            atomically: true,
            encoding: .utf8
        )
        try """
        1
        00:00:01,000 --> 00:00:04,000
        Speaker: Curiosity makes difficult practice feel meaningful.

        2
        00:00:04,000 --> 00:00:08,000
        Repetition helps new phrases become natural.
        """.write(
            to: nestedDirectory.appendingPathComponent("talk.srt"),
            atomically: true,
            encoding: .utf8
        )
        try "这是中文说明。".write(
            to: directory.appendingPathComponent("notes.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Ignored English content.".write(
            to: directory.appendingPathComponent("skip.pdf"),
            atomically: true,
            encoding: .utf8
        )

        let result = try FolderTextImporter().importText(from: directory)

        try expectEqual(result.folderName, "Course Pack")
        try expectEqual(result.fileCount, 2)
        try expect(result.sourceLabel.contains("2 个英文文件"))
        try expect(result.text.contains("Deliberate practice builds confidence"))
        try expect(result.text.contains("Curiosity makes difficult practice feel meaningful"))
        try expect(!result.text.contains("00:00:01"))
        try expect(!result.text.contains("Ignored English content"))
    },
    UnitTest(name: "FolderTextImporter reports empty or missing folders") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        do {
            _ = try FolderTextImporter().importText(from: directory)
            try fail("Expected no supported English files")
        } catch let error as FolderTextImporter.ImportError {
            try expectEqual(error, .noSupportedEnglishFiles)
            try expectEqual(error.localizedDescription, "文件夹中没有找到可用的英文文本文件。")
        }

        do {
            _ = try FolderTextImporter().importText(from: directory.appendingPathComponent("missing"))
            try fail("Expected missing folder")
        } catch let error as FolderTextImporter.ImportError {
            try expectEqual(error, .folderNotFound)
            try expectEqual(error.localizedDescription, "没有找到可读取的文件夹。")
        }
    },
    UnitTest(name: "FolderTextImporter reads alternate encodings and skips unreadable files") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        let utf16Text = """
        Encoding practice helps learners keep useful English sentences available for review.
        Unicode files should still become normal cloze questions after import.
        """
        try utf16Text.write(
            to: directory.appendingPathComponent("utf16.txt"),
            atomically: true,
            encoding: .utf16
        )

        var latinBytes: [UInt8] = [0xE9] + Array(
            " practice makes imported English text readable after encoding fallback.".utf8
        )
        if latinBytes.count.isMultiple(of: 2) {
            latinBytes.append(0x21)
        }
        try Data(latinBytes).write(to: directory.appendingPathComponent("latin.text"))

        let unreadableURL = directory.appendingPathComponent("unreadable.txt")
        try "中文内容，不应该生成英文文本。".write(to: unreadableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadableURL.path)
        }

        let result = try FolderTextImporter().importText(from: directory)

        try expectEqual(result.fileCount, 2)
        try expect(result.text.contains("Encoding practice helps learners"))
        try expect(result.text.contains("practice makes imported English text readable"))
        try expect(!result.text.contains("中文内容"))
    },
    UnitTest(name: "AnswerMatcher accepts useful variants") {
        let matcher = AnswerMatcher()

        try expect(matcher.matches("  MEET  ", answer: "meet"))
        try expect(matcher.matches("I’m ready", answer: "I am ready"))
        try expect(matcher.matches("hello!", answer: "hello"))
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
    UnitTest(name: "AnswerExplanationService explains unanswered blanks") {
        let item = sampleItem()
        let explanation = AnswerExplanationService().explanation(for: item, answers: [:])

        try expect(explanation.contains("空位 1：meet"))
        try expect(explanation.contains("还没有作答。"))
        try expect(!explanation.contains("未作答"))
    },
    UnitTest(name: "PracticeItem codable round trip keeps segments") {
        let item = sampleItem()
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(PracticeItem.self, from: data)

        try expectEqual(decoded, item)
        try expectEqual(decoded.blanks.map(\.answer), ["meet", "afternoon"])
    },
    UnitTest(name: "ClozeSegment rejects unknown segment type") {
        let json = #"{"type":"mystery","text":"hello"}"#

        do {
            _ = try JSONDecoder().decode(ClozeSegment.self, from: Data(json.utf8))
            try fail("Expected unknown segment type to fail decoding")
        } catch let error as DecodingError {
            guard case .dataCorrupted = error else {
                try fail("Expected dataCorrupted error")
            }
        }
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
    UnitTest(name: "PracticeLibrary falls back to seed decks and exposes default paths") {
        let directory = try temporaryDirectory()
        let legacyDirectory = try temporaryDirectory()
        defer {
            removeTemporaryDirectory(directory)
            removeTemporaryDirectory(legacyDirectory)
        }

        let seedDecks = PracticeLibrary(
            applicationSupportDirectory: directory,
            legacyApplicationSupportDirectory: legacyDirectory
        )
        .loadDecks()
        try expectEqual(seedDecks.map(\.id), ["seed"])

        let emptySeedDecks = PracticeLibrary(
            applicationSupportDirectory: directory,
            legacyApplicationSupportDirectory: legacyDirectory,
            seedItemsProvider: { [] }
        )
        .loadDecks()
        try expect(emptySeedDecks.isEmpty)
        try expect(PracticeLibrary.seedItems(from: nil).isEmpty)
        try expect(PracticeLibrary.seedItems(from: Data("bad json".utf8)).isEmpty)

        let redirectedSupport = try temporaryDirectory()
        defer { removeTemporaryDirectory(redirectedSupport) }
        let redirectedFileManager = StubApplicationSupportFileManager(applicationSupportDirectory: redirectedSupport)
        let redirectedDecks = PracticeLibrary(
            fileManager: redirectedFileManager,
            seedItemsProvider: { [] }
        )
        .loadDecks()
        try expect(redirectedDecks.isEmpty)
        try expectEqual(
            AIProviderLibrary(fileManager: redirectedFileManager, secretStore: InMemorySecretStore()).load(),
            .empty
        )
        try expectEqual(try StudyDataLibrary(fileManager: redirectedFileManager).load(userID: "redirected").userID, "redirected")
        try expect(UserAccountLibrary(fileManager: redirectedFileManager).loadAccounts().isEmpty)

        try expectEqual(try PracticeLibrary.defaultApplicationSupportDirectory().lastPathComponent, "whatever")
        try expectEqual(try PracticeLibrary.defaultLegacyApplicationSupportDirectory().lastPathComponent, "EnglishClozeCoach")
        try expect(!PracticeLibrary.bundledSeedItems().isEmpty)
        try expectEqual(AIProviderLibrary.defaultApplicationSupportDirectory().lastPathComponent, "whatever")
        try expectEqual(StudyDataLibrary.defaultApplicationSupportDirectory().lastPathComponent, "whatever")
        try expectEqual(UserAccountLibrary.defaultApplicationSupportDirectory().lastPathComponent, "whatever")
        let failingFileManager = StubApplicationSupportFileManager(
            applicationSupportDirectory: redirectedSupport,
            throwsForApplicationSupport: true
        )
        try expectEqual(AIProviderLibrary.defaultApplicationSupportDirectory(fileManager: failingFileManager).lastPathComponent, "whatever")
        try expectEqual(StudyDataLibrary.defaultApplicationSupportDirectory(fileManager: failingFileManager).lastPathComponent, "whatever")
        try expectEqual(UserAccountLibrary.defaultApplicationSupportDirectory(fileManager: failingFileManager).lastPathComponent, "whatever")
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
    },
    UnitTest(name: "PracticeStore imports text and handles empty selection boundaries") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = PracticeStore(library: PracticeLibrary(applicationSupportDirectory: directory))
        let originalDeckID = try require(store.selectedDeckID)

        store.selectDeck("missing")
        try expectEqual(store.selectedDeckID, originalDeckID)
        try expect(store.prepareImportDraft(text: "没有英文。12345", name: "空", source: "unit") == nil)
        try expectEqual(store.importText("没有英文。12345"), 0)
        try expectEqual(store.importError, "没有找到可生成题目的英文句子。")
        try expectEqual(store.saveImportDraft(ImportDraft(name: "坏数据", source: "unit", items: [])), 0)
        try expectEqual(store.importError, "没有生成题目。")

        let importedCount = store.importText(
            "Deliberate practice builds confidence. Focused review improves long-term memory."
        )
        try expectEqual(importedCount, 2)
        let importedDeckID = try require(store.selectedDeckID)
        try expectEqual(store.selectedDeck?.name, "导入题库")
        try expectEqual(store.librarySummaries.first { $0.id == importedDeckID }?.itemCount, 2)

        let selectedItem = try require(store.selectedItem)
        let mistake = MistakeRecord(
            id: "mistake",
            itemID: selectedItem.id,
            blankID: selectedItem.blanks[0].id,
            sourceChinese: selectedItem.sourceChinese,
            targetEnglish: selectedItem.targetEnglish,
            answer: selectedItem.blanks[0].answer,
            lastWrongAnswer: "wrong",
            mistakeCount: 1,
            lastMistakeAt: Date()
        )
        var studyData = UserStudyData.empty(userID: "user")
        studyData.completedItemIDs = [selectedItem.id]
        studyData.mistakes = [mistake]
        store.refreshLibrarySummaries(studyData: studyData)
        let summary = try require(store.librarySummaries.first { $0.id == importedDeckID })
        try expectEqual(summary.completedCount, 1)
        try expectEqual(summary.mistakeCount, 1)

        store.selectedDeckID = nil
        store.selectedItemID = nil
        try expect(store.selectedDeck != nil)
        try expect(store.selectedItem != nil)
        try expectEqual(store.selectedIndex, 0)
        try expect(store.explanationForSelectedItem()?.contains("空位 1") == true)

        store.selectedDeckID = "missing-deck"
        store.selectedItemID = "missing-item"
        try expect(store.selectedDeck != nil)
        try expect(store.selectedItem != nil)
        try expectEqual(store.selectedIndex, 0)

        store.startCustomPractice(items: [], title: "空练习")
        store.resetCurrentAnswers()
        store.advance()
        store.goBack()
        try expect(store.selectedItem == nil)
        try expect(store.explanationForSelectedItem() == nil)
        try expect(!store.canAdvance)
        try expect(!store.canGoBack)
    },
    UnitTest(name: "PracticeStore handles deck editing edge cases") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let first = sampleDeck(id: "deck-a", items: [sampleItem(id: "shared"), sampleItem(id: "unique-a")])
        let second = sampleDeck(id: "deck-b", items: [sampleItem(id: "shared"), sampleItem(id: "unique-b")])
        let library = PracticeLibrary(applicationSupportDirectory: directory)
        try library.save([first, second])
        let store = PracticeStore(library: library)

        try expectEqual(store.allItems.map(\.id), ["shared", "unique-a", "unique-b"])

        store.renameDeck("missing", name: "不会保存")
        store.renameDeck("deck-a", name: "   ")
        try expectEqual(store.decks.first { $0.id == "deck-a" }?.name, "测试题库")

        store.deleteItem("whatever", in: "missing")
        store.deleteItem("unique-b", in: "deck-b")
        try expectEqual(store.selectedDeckID, "deck-a")
        try expectEqual(store.decks.first { $0.id == "deck-b" }?.items.map(\.id), ["shared"])

        store.updateItem(
            "shared",
            in: "deck-b",
            sourceChinese: "非当前题库更新",
            targetEnglish: "Repeated review keeps useful language available.",
            blankText: "Repeated, available"
        )
        try expectEqual(store.selectedDeckID, "deck-a")
        try expectEqual(store.decks.first { $0.id == "deck-b" }?.items.first?.sourceChinese, "非当前题库更新")

        store.updateItem("missing", in: "deck-b", sourceChinese: "x", targetEnglish: "x", blankText: "x")
        store.selectDeck("deck-b")
        store.deleteDeck("deck-b")
        try expectEqual(store.selectedDeckID, "deck-a")

        let singleDirectory = try temporaryDirectory()
        defer { removeTemporaryDirectory(singleDirectory) }
        let singleLibrary = PracticeLibrary(applicationSupportDirectory: singleDirectory)
        try singleLibrary.save([sampleDeck(id: "only")])
        let singleStore = PracticeStore(library: singleLibrary)
        singleStore.deleteDeck("only")
        try expectEqual(singleStore.importError, "至少保留一个题库。")

        let blankNameCount = singleStore.saveImportDraft(
            ImportDraft(
                name: "   ",
                source: "manual",
                items: [
                    ImportDraftItem(
                        id: "blank-name",
                        sourceChinese: "中文",
                        targetEnglish: "Careful repetition builds fluent recall.",
                        blankText: "repetition"
                    )
                ]
            )
        )
        try expectEqual(blankNameCount, 1)
        try expectEqual(singleStore.selectedDeck?.name, "导入题库")
    },
    UnitTest(name: "PracticeStore surfaces deck save failures") {
        let directory = try temporaryDirectory()
        let legacyDirectory = try temporaryDirectory()
        defer {
            removeTemporaryDirectory(directory)
            removeTemporaryDirectory(legacyDirectory)
        }
        let fileURL = directory.appendingPathComponent("not-a-directory")
        try "file".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = PracticeStore(
            library: PracticeLibrary(
                applicationSupportDirectory: fileURL,
                legacyApplicationSupportDirectory: legacyDirectory
            )
        )

        store.renameDeck("seed", name: "无法保存")

        try expect(store.importError?.contains("保存题库失败") == true)
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
    UnitTest(name: "UserSessionStore surfaces create and login save failures") {
        let createDirectory = try temporaryDirectory()
        defer { removeTemporaryDirectory(createDirectory) }
        let createFileURL = createDirectory.appendingPathComponent("not-a-directory")
        try "file".write(to: createFileURL, atomically: true, encoding: .utf8)
        let createSuiteName = "whatever.tests.create.\(UUID().uuidString)"
        let createDefaults = try require(UserDefaults(suiteName: createSuiteName))
        defer { createDefaults.removePersistentDomain(forName: createSuiteName) }
        let createStore = UserSessionStore(
            library: UserAccountLibrary(
                userDefaults: createDefaults,
                applicationSupportDirectory: createFileURL
            )
        )

        try expect(!createStore.createUser(username: "Li", password: "1234", confirmation: "1234"))
        try expect(createStore.authError?.contains("创建用户失败") == true)
        try expect(createStore.accounts.isEmpty)

        let loginDirectory = try temporaryDirectory()
        defer { removeTemporaryDirectory(loginDirectory) }
        let loginSuiteName = "whatever.tests.login.\(UUID().uuidString)"
        let loginDefaults = try require(UserDefaults(suiteName: loginSuiteName))
        defer { loginDefaults.removePersistentDomain(forName: loginSuiteName) }
        let loginLibrary = UserAccountLibrary(
            userDefaults: loginDefaults,
            applicationSupportDirectory: loginDirectory
        )
        let loginStore = UserSessionStore(library: loginLibrary)
        try expect(loginStore.createUser(username: "Li", password: "1234", confirmation: "1234"))
        loginStore.logout()
        try FileManager.default.removeItem(at: loginDirectory)
        try "file".write(to: loginDirectory, atomically: true, encoding: .utf8)

        try expect(!loginStore.login(username: "Li", password: "1234"))
        try expect(loginStore.authError?.contains("登录失败") == true)
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

        let minimalLegacy = try JSONDecoder().decode(
            UserStudyData.self,
            from: Data(#"{"userID":"minimal"}"#.utf8)
        )
        try expectEqual(minimalLegacy.userID, "minimal")
        try expect(minimalLegacy.completedItemIDs.isEmpty)
        try expect(minimalLegacy.history.isEmpty)
        try expect(minimalLegacy.mistakes.isEmpty)
        try expect(minimalLegacy.reviewStates.isEmpty)
        try expectEqual(minimalLegacy.dailyGoal, 10)
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
    UnitTest(name: "StudyStore covers guards sorting review updates and history trimming") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let studyStore = StudyStore(
            library: StudyDataLibrary(applicationSupportDirectory: directory),
            reminderService: StudyReminderService(schedulesNotifications: false)
        )
        let user = UserAccount(
            id: "review-user",
            username: "Review",
            passwordSalt: "salt",
            passwordHash: "hash",
            createdAt: Date(),
            lastLoginAt: nil
        )
        let firstItem = sampleItem(id: "review-a")
        let secondItem = sampleItem(id: "review-b")

        studyStore.recordMistake(item: firstItem, blank: firstItem.blanks[0], wrongAnswer: "met")
        studyStore.recordCompletion(item: firstItem, wrongBlankCount: 0)
        try expectEqual(studyStore.completedCount, 0)
        try expect(studyStore.frequentMistakes.isEmpty)

        studyStore.load(for: user)
        studyStore.updateDailyGoal(-20)
        try expectEqual(studyStore.data.dailyGoal, 1)
        studyStore.updateDailyGoal(500)
        try expectEqual(studyStore.data.dailyGoal, 200)

        studyStore.recordMistake(item: firstItem, blank: firstItem.blanks[0], wrongAnswer: "   ")
        try expect(studyStore.frequentMistakes.isEmpty)
        studyStore.recordMistake(item: firstItem, blank: firstItem.blanks[0], wrongAnswer: "met")
        studyStore.recordMistake(item: secondItem, blank: secondItem.blanks[0], wrongAnswer: "built")
        studyStore.recordMistake(item: secondItem, blank: secondItem.blanks[0], wrongAnswer: "builded")
        studyStore.recordMistake(item: firstItem, blank: firstItem.blanks[1], wrongAnswer: "tomorrow")
        try expectEqual(studyStore.frequentMistakes.first?.itemID, secondItem.id)
        try expectEqual(studyStore.mistakeItems(from: [firstItem, secondItem, firstItem]).map(\.id), [
            secondItem.id,
            firstItem.id
        ])
        try expectEqual(studyStore.mistakeItems(from: [secondItem]).map(\.id), [secondItem.id])

        studyStore.recordCompletion(item: firstItem, wrongBlankCount: 0)
        studyStore.recordCompletion(item: firstItem, wrongBlankCount: 0)
        var reviewState = try require(studyStore.data.reviewStates.first { $0.itemID == firstItem.id })
        try expectEqual(reviewState.consecutiveCorrect, 2)
        try expect(reviewState.intervalDays >= 1)

        studyStore.recordCompletion(item: firstItem, wrongBlankCount: 1)
        reviewState = try require(studyStore.data.reviewStates.first { $0.itemID == firstItem.id })
        try expectEqual(reviewState.consecutiveCorrect, 0)
        try expectEqual(reviewState.intervalDays, 1)
        try expectEqual(reviewState.lapseCount, 1)

        studyStore.recordCompletion(item: secondItem, wrongBlankCount: 0)
        let dueItems = studyStore.dueItems(from: [firstItem, secondItem], on: Date().addingTimeInterval(60 * 60 * 48))
        try expectEqual(Set(dueItems.map(\.id)), Set([firstItem.id, secondItem.id]))

        for index in 0..<105 {
            studyStore.recordCompletion(item: sampleItem(id: "bulk-\(index)"), wrongBlankCount: 0)
        }
        try expectEqual(studyStore.data.history.count, 100)
        try expectEqual(studyStore.recentHistory.count, 8)
    },
    UnitTest(name: "StudyStore handles old streaks zero goals and bad saved data") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let library = StudyDataLibrary(applicationSupportDirectory: directory)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        var data = UserStudyData.empty(userID: "streak-user")
        data.dailyGoal = 0
        data.history = [
            PracticeHistoryEntry(
                id: "yesterday",
                itemID: "item",
                sourceChinese: "中文",
                targetEnglish: "Practice builds confidence.",
                completedAt: yesterday,
                wrongBlankCount: 0
            )
        ]
        try library.save(data)

        let studyStore = StudyStore(
            library: library,
            reminderService: StudyReminderService(schedulesNotifications: false)
        )
        let user = UserAccount(
            id: "streak-user",
            username: "Streak",
            passwordSalt: "salt",
            passwordHash: "hash",
            createdAt: Date(),
            lastLoginAt: nil
        )
        studyStore.load(for: user)
        try expectEqual(studyStore.dailyGoalProgress, 0)
        try expectEqual(studyStore.currentStreak, 1)

        let badDirectory = try temporaryDirectory()
        defer { removeTemporaryDirectory(badDirectory) }
        let badUserDirectory = badDirectory
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent("bad-user", isDirectory: true)
        try FileManager.default.createDirectory(at: badUserDirectory, withIntermediateDirectories: true)
        try "{ bad json".write(
            to: badUserDirectory.appendingPathComponent("StudyData.json"),
            atomically: true,
            encoding: .utf8
        )
        let badStore = StudyStore(
            library: StudyDataLibrary(applicationSupportDirectory: badDirectory),
            reminderService: StudyReminderService(schedulesNotifications: false)
        )
        badStore.load(
            for: UserAccount(
                id: "bad-user",
                username: "Bad",
                passwordSalt: "salt",
                passwordHash: "hash",
                createdAt: Date(),
                lastLoginAt: nil
            )
        )
        try expectEqual(badStore.data.userID, "bad-user")
        try expect(badStore.saveError?.contains("无法读取学习记录") == true)
        try expectEqual(badStore.currentStreak, 0)
    },
    UnitTest(name: "StudyStore surfaces save failures") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileURL = directory.appendingPathComponent("not-a-directory")
        try "file".write(to: fileURL, atomically: true, encoding: .utf8)
        let studyStore = StudyStore(
            library: StudyDataLibrary(applicationSupportDirectory: fileURL),
            reminderService: StudyReminderService(schedulesNotifications: false)
        )
        studyStore.load(
            for: UserAccount(
                id: "save-fails",
                username: "Save",
                passwordSalt: "salt",
                passwordHash: "hash",
                createdAt: Date(),
                lastLoginAt: nil
            )
        )

        studyStore.updateDailyGoal(12)

        try expect(studyStore.saveError?.contains("保存学习记录失败") == true)
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
    },
    UnitTest(name: "AIProviderStore adds appends selects and deletes providers") {
        let directory = try temporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let secretStore = InMemorySecretStore()
        let library = AIProviderLibrary(secretStore: secretStore, applicationSupportDirectory: directory)
        let store = AIProviderStore(library: library)

        try expect(store.activeProvider == nil)
        let addedProvider = store.addProvider()
        try expectEqual(store.providers.count, 1)
        try expectEqual(store.activeProviderID, addedProvider.id)
        try expectEqual(store.activeProvider?.name, "新 AI")

        store.selectProvider("missing")
        try expectEqual(store.activeProviderID, addedProvider.id)

        let externalProvider = AIProviderConfig(
            id: "external",
            name: "External",
            baseURL: "https://example.com/v1",
            model: "model",
            apiKey: "external-secret",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        store.saveProvider(externalProvider)
        try expect(store.providers.contains { $0.id == externalProvider.id })
        try expectEqual(secretStore.values[externalProvider.id], "external-secret")

        store.selectProvider(externalProvider.id)
        store.deleteProvider(addedProvider.id)
        try expectEqual(store.activeProviderID, externalProvider.id)
        try expect(!store.providers.contains { $0.id == addedProvider.id })

        secretStore.values["empty-key"] = "old-secret"
        let emptyKeyProvider = AIProviderConfig(
            id: "empty-key",
            name: "Empty",
            baseURL: "https://example.com/v1",
            model: "model",
            apiKey: "",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try library.save(AIProviderSettings(activeProviderID: nil, providers: [emptyKeyProvider]))
        try expect(secretStore.values["empty-key"] == nil)
    },
    UnitTest(name: "AIProviderStore surfaces delete and save failures") {
        let deleteDirectory = try temporaryDirectory()
        defer { removeTemporaryDirectory(deleteDirectory) }
        let provider = AIProviderConfig(
            id: "delete-fails",
            name: "Delete Fails",
            baseURL: "https://example.com/v1",
            model: "model",
            apiKey: "",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try JSONEncoder()
            .encode(AIProviderSettings(activeProviderID: provider.id, providers: [provider]))
            .write(to: deleteDirectory.appendingPathComponent("AIProviders.json"))

        let deleteFailingStore = AIProviderStore(
            library: AIProviderLibrary(
                secretStore: FailingSecretStore(deleteMessage: "boom"),
                applicationSupportDirectory: deleteDirectory
            )
        )
        deleteFailingStore.deleteProvider(provider.id)
        try expect(deleteFailingStore.saveError?.contains("删除 AI 密钥失败") == true)

        let fileDirectory = try temporaryDirectory()
        defer { removeTemporaryDirectory(fileDirectory) }
        let fileURL = fileDirectory.appendingPathComponent("not-a-directory")
        try "file".write(to: fileURL, atomically: true, encoding: .utf8)
        let saveFailingStore = AIProviderStore(
            library: AIProviderLibrary(
                secretStore: InMemorySecretStore(),
                applicationSupportDirectory: fileURL
            )
        )
        _ = saveFailingStore.addProvider()
        try expect(saveFailingStore.saveError?.contains("保存 AI 配置失败") == true)
    }
]

let aiTextServiceTests: [UnitTest] = [
    UnitTest(name: "AITextService translates JSON response in order") {
        let client = FakeAICompletionClient(response: #"prefix ["你好。","再见。"] suffix"#)
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
    UnitTest(name: "AITextService throws on unparseable translation response") {
        let service = AITextService(client: FakeAICompletionClient(response: "   \n  "))

        try runAsync {
            do {
                _ = try await service.translateEnglishToChinese(["One."], using: readyProvider())
                try fail("Expected invalid response")
            } catch let error as AITextServiceError {
                try expectEqual(error.localizedDescription, "AI 返回格式无法解析。")
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
    UnitTest(name: "AITextService marks unanswered blanks in explanation prompt") {
        let client = FakeAICompletionClient(response: "解释")
        let service = AITextService(client: client)

        try runAsync {
            _ = try await service.explainAnswer(for: sampleItem(), answers: [:], using: readyProvider())

            try expect(client.lastUserPrompt?.contains("学生答案 \"未作答\"") == true)
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
    },
    UnitTest(name: "OpenAICompatibleAIClient sends chat completion request and trims content") {
        let responseBody = """
        {
          "choices": [
            { "message": { "role": "assistant", "content": "  翻译结果  " } }
          ]
        }
        """
        let session = FakeHTTPDataSession(statusCode: 200, body: responseBody)
        var configuredProvider = readyProvider()
        configuredProvider.baseURL = "https://example.com/v1///"
        let provider = configuredProvider
        let client = OpenAICompatibleAIClient(session: session)

        try runAsync {
            let content = try await client.complete(
                provider: provider,
                systemPrompt: "system prompt",
                userPrompt: "user prompt"
            )

            try expectEqual(content, "翻译结果")
            let request = try require(session.lastRequest)
            try expectEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
            try expectEqual(request.httpMethod, "POST")
            try expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")

            let body = try require(request.httpBody)
            let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let json = try require(object)
            try expectEqual(json["model"] as? String, "test-model")
            try expectEqual(json["temperature"] as? Double, 0.2)
            let messages = try require(json["messages"] as? [[String: String]])
            try expectEqual(messages.map { $0["role"] }, ["system", "user"])
            try expectEqual(messages.map { $0["content"] }, ["system prompt", "user prompt"])
        }
    },
    UnitTest(name: "OpenAICompatibleAIClient surfaces response errors") {
        try runAsync {
            var provider = readyProvider()
            provider.baseURL = "http://[::1"
            do {
                _ = try await OpenAICompatibleAIClient(session: FakeHTTPDataSession(statusCode: 200, body: "{}"))
                    .complete(provider: provider, systemPrompt: "system", userPrompt: "user")
                try fail("Expected invalid base URL")
            } catch let error as AITextServiceError {
                try expectEqual(error.localizedDescription, "AI Base URL 无效。")
            }

            do {
                _ = try await OpenAICompatibleAIClient(
                    session: FakeHTTPDataSession(response: URLResponse())
                )
                .complete(provider: readyProvider(), systemPrompt: "system", userPrompt: "user")
                try fail("Expected invalid response")
            } catch let error as AITextServiceError {
                try expectEqual(error.localizedDescription, "AI 返回格式无法解析。")
            }

            do {
                _ = try await OpenAICompatibleAIClient(
                    session: FakeHTTPDataSession(statusCode: 429, body: "rate limited")
                )
                .complete(provider: readyProvider(), systemPrompt: "system", userPrompt: "user")
                try fail("Expected request failure")
            } catch let error as AITextServiceError {
                try expectEqual(error.localizedDescription, "AI 请求失败：rate limited")
            }

            do {
                _ = try await OpenAICompatibleAIClient(
                    session: FakeHTTPDataSession(statusCode: 500, data: Data([0xFF, 0xFE, 0xFD]))
                )
                .complete(provider: readyProvider(), systemPrompt: "system", userPrompt: "user")
                try fail("Expected request failure with fallback HTTP message")
            } catch let error as AITextServiceError {
                try expectEqual(error.localizedDescription, "AI 请求失败：HTTP 500")
            }

            do {
                _ = try await OpenAICompatibleAIClient(
                    session: FakeHTTPDataSession(
                        statusCode: 200,
                        body: #"{"choices":[{"message":{"role":"assistant","content":"   "}}]}"#
                    )
                )
                .complete(provider: readyProvider(), systemPrompt: "system", userPrompt: "user")
                try fail("Expected empty response")
            } catch let error as AITextServiceError {
                try expectEqual(error.localizedDescription, "AI 没有返回内容。")
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

private struct TestError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private final class FailingSecretStore: SecretStore, @unchecked Sendable {
    let deleteMessage: String

    init(deleteMessage: String) {
        self.deleteMessage = deleteMessage
    }

    func read(account: String) -> String? {
        nil
    }

    func save(_ value: String, account: String) throws {}

    func delete(account: String) throws {
        throw TestError(message: deleteMessage)
    }
}

private final class StubApplicationSupportFileManager: FileManager, @unchecked Sendable {
    let applicationSupportDirectory: URL
    let throwsForApplicationSupport: Bool

    init(applicationSupportDirectory: URL, throwsForApplicationSupport: Bool = false) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.throwsForApplicationSupport = throwsForApplicationSupport
        super.init()
    }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if directory == .applicationSupportDirectory {
            if throwsForApplicationSupport {
                throw TestError(message: "application support unavailable")
            }
            return applicationSupportDirectory
        }
        return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
    }
}

private final class FakeHTTPDataSession: HTTPDataSession, @unchecked Sendable {
    private let payload: Data
    private let response: URLResponse
    var lastRequest: URLRequest?

    convenience init(statusCode: Int, body: String) {
        self.init(statusCode: statusCode, data: Data(body.utf8))
    }

    init(statusCode: Int, data: Data) {
        let url = URL(string: "https://example.com/v1/chat/completions")!
        self.payload = data
        self.response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    init(response: URLResponse) {
        self.payload = Data()
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return (payload, response)
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
