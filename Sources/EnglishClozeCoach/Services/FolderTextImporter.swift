import Foundation

struct FolderImportResult: Equatable {
    var folderName: String
    var fileCount: Int
    var text: String
    var sourceLabel: String
}

struct FolderTextImporter {
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

    var supportedExtensions: Set<String> = ["txt", "text", "md", "markdown", "srt", "vtt", "html", "htm"]
    var fileManager: FileManager = .default
    var scriptTextDownloader: ScriptTextDownloader = ScriptTextDownloader()

    func importText(from folderURL: URL) throws -> FolderImportResult {
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

        let importedTexts = files.compactMap(importedText)
        guard !importedTexts.isEmpty else {
            throw ImportError.noSupportedEnglishFiles
        }

        let folderName = folderURL.lastPathComponent.isEmpty ? "文件夹题库" : folderURL.lastPathComponent
        let combinedText = importedTexts.joined(separator: "\n\n")

        return FolderImportResult(
            folderName: folderName,
            fileCount: importedTexts.count,
            text: combinedText,
            sourceLabel: "\(folderName) 文件夹（\(importedTexts.count) 个英文文件）"
        )
    }

    private func isSupportedRegularFile(_ url: URL) -> Bool {
        guard supportedExtensions.contains(url.pathExtension.lowercased()),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey]) else {
            return false
        }
        return values.isRegularFile == true
    }

    private func importedText(from url: URL) -> String? {
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
        return preparedText
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
