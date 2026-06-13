import Foundation
import UniformTypeIdentifiers

struct FolderImportResult: Equatable {
    var folderName: String
    var fileCount: Int
    var text: String
    var sourceLabel: String
}

struct FolderImportSummary: Equatable {
    var folderName: String
    var fileCount: Int
    var sourceLabel: String
}

struct FolderImportBatch: Equatable {
    var fileCount: Int
    var byteCount: Int
    var text: String
}

struct FolderTextImporter {
    private struct ImportedFile {
        let url: URL
        let text: String
    }

    enum ImportError: LocalizedError, Equatable {
        case folderNotFound
        case noSupportedEnglishFiles

        var errorDescription: String? {
            switch self {
            case .folderNotFound:
                return "没有找到可读取的文件夹。"
            case .noSupportedEnglishFiles:
                return "文件夹中没有找到可用的英文文本文件。"
            }
        }
    }

    static let importableFileExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "srt", "vtt", "html", "htm",
        "csv", "tsv", "json", "jsonl", "log", "sub", "sbv", "ass", "ssa"
    ]

    var supportedExtensions: Set<String> = FolderTextImporter.importableFileExtensions
    var fileManager: FileManager = .default
    var scriptTextDownloader: ScriptTextDownloader = ScriptTextDownloader()

    func importText(from folderURL: URL) throws -> FolderImportResult {
        var importedTexts: [String] = []
        let summary = try importTextBatches(from: folderURL, maximumBatchByteCount: .max) { batch in
            importedTexts.append(batch.text)
        }

        return FolderImportResult(
            folderName: summary.folderName,
            fileCount: summary.fileCount,
            text: importedTexts.joined(separator: "\n\n"),
            sourceLabel: summary.sourceLabel
        )
    }

    func importText(fromFiles fileURLs: [URL]) throws -> FolderImportResult {
        var importedTexts: [String] = []
        let summary = try importTextBatches(fromFiles: fileURLs, maximumBatchByteCount: .max) { batch in
            importedTexts.append(batch.text)
        }

        return FolderImportResult(
            folderName: summary.folderName,
            fileCount: summary.fileCount,
            text: importedTexts.joined(separator: "\n\n"),
            sourceLabel: summary.sourceLabel
        )
    }

    func importTextBatches(
        from folderURL: URL,
        maximumBatchByteCount: Int = 512 * 1024,
        handleBatch: (FolderImportBatch) throws -> Void
    ) throws -> FolderImportSummary {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            throw ImportError.folderNotFound
        }

        let files = enumerator
            .compactMap { $0 as? URL }
            .filter(isSupportedRegularFile)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let folderName = folderURL.lastPathComponent.isEmpty ? "文件夹题库" : folderURL.lastPathComponent

        return try importTextBatches(
            from: files,
            maximumBatchByteCount: maximumBatchByteCount,
            folderName: folderName,
            sourceLabel: { "\(folderName) 文件夹（\($0) 个英文文件）" }
        ) { batch in
            try handleBatch(batch.publicBatch)
        }
    }

    func importTextBatches(
        fromFiles fileURLs: [URL],
        maximumBatchByteCount: Int = 512 * 1024,
        handleBatch: (FolderImportBatch) throws -> Void
    ) throws -> FolderImportSummary {
        let files = fileURLs
            .filter(isSupportedRegularFile)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        var firstImportedURL: URL?

        let summary = try importTextBatches(
            from: files,
            maximumBatchByteCount: maximumBatchByteCount,
            folderName: "本地文件题库",
            sourceLabel: { fileCount in
                if fileCount == 1, let firstImportedURL {
                    return firstImportedURL.lastPathComponent
                }
                return "本地文件（\(fileCount) 个英文文件）"
            }
        ) { batch in
            if firstImportedURL == nil {
                firstImportedURL = batch.firstFileURL
            }
            try handleBatch(batch.publicBatch)
        }

        guard summary.fileCount == 1, let firstImportedURL else {
            return summary
        }

        let singleFileName = firstImportedURL.deletingPathExtension().lastPathComponent
        return FolderImportSummary(
            folderName: singleFileName.isEmpty ? "本地文件题库" : singleFileName,
            fileCount: summary.fileCount,
            sourceLabel: firstImportedURL.lastPathComponent
        )
    }

    private func isSupportedRegularFile(_ url: URL) -> Bool {
        guard isSupportedTextFile(url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
            return false
        }
        return values.isRegularFile == true
    }

    private func isSupportedTextFile(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        if supportedExtensions.contains(pathExtension) {
            return true
        }

        guard let type = UTType(filenameExtension: pathExtension) else {
            return false
        }
        return type.conforms(to: .text)
    }

    private func importedFile(from url: URL) -> ImportedFile? {
        guard let rawText = readText(from: url) else {
            return nil
        }

        let preparedText = scriptTextDownloader.preparedText(
            from: rawText,
            sourceHint: url.pathExtension
        ) ?? normalizedPlainText(rawText)

        guard containsEnglish(preparedText) else {
            return nil
        }
        return ImportedFile(url: url, text: preparedText)
    }

    private struct InternalImportBatch {
        var fileCount: Int
        var byteCount: Int
        var text: String
        var firstFileURL: URL

        var publicBatch: FolderImportBatch {
            FolderImportBatch(fileCount: fileCount, byteCount: byteCount, text: text)
        }
    }

    private func importTextBatches(
        from files: [URL],
        maximumBatchByteCount: Int,
        folderName: String,
        sourceLabel: (Int) -> String,
        handleBatch: (InternalImportBatch) throws -> Void
    ) throws -> FolderImportSummary {
        let byteLimit = max(1, maximumBatchByteCount)
        var currentTexts: [String] = []
        var currentByteCount = 0
        var currentFileCount = 0
        var currentFirstFileURL: URL?
        var totalImportedFileCount = 0

        func flushBatch() throws {
            guard let firstFileURL = currentFirstFileURL else {
                return
            }

            try handleBatch(
                InternalImportBatch(
                    fileCount: currentFileCount,
                    byteCount: currentByteCount,
                    text: currentTexts.joined(separator: "\n\n"),
                    firstFileURL: firstFileURL
                )
            )
            currentTexts.removeAll(keepingCapacity: true)
            currentByteCount = 0
            currentFileCount = 0
            currentFirstFileURL = nil
        }

        for file in files {
            guard let importedFile = importedFile(from: file) else {
                continue
            }

            let textByteCount = importedFile.text.utf8.count
            if currentByteCount > 0, currentByteCount + textByteCount > byteLimit {
                try flushBatch()
            }

            currentTexts.append(importedFile.text)
            currentByteCount += textByteCount
            currentFileCount += 1
            currentFirstFileURL = currentFirstFileURL ?? importedFile.url
            totalImportedFileCount += 1
        }

        try flushBatch()

        guard totalImportedFileCount > 0 else {
            throw ImportError.noSupportedEnglishFiles
        }

        return FolderImportSummary(
            folderName: folderName,
            fileCount: totalImportedFileCount,
            sourceLabel: sourceLabel(totalImportedFileCount)
        )
    }

    private func readText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        if let utf8Text = String(data: data, encoding: .utf8) {
            return utf8Text
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let utf16Text = String(data: data, encoding: .utf16) {
            return utf16Text
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private func normalizedPlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{FEFF}", with: " ")
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsEnglish(_ text: String) -> Bool {
        text.range(of: #"[A-Za-z]{2,}"#, options: .regularExpression) != nil
    }
}
