import Foundation

enum PracticeLibraryOrigin: Hashable {
    case bundled
    case database
    case localFile
    case imported

    static func inferred(name: String, detail: String) -> PracticeLibraryOrigin {
        if name == "内置题库" || detail.contains("应用内置") {
            return .bundled
        }
        if name == "本机保存题库" || detail.contains("SQLite") {
            return .database
        }
        if name == "本地文件题库" || detail.contains("本地文件") || detail.contains("英文文件") {
            return .localFile
        }

        let lowercasedDetail = detail.lowercased()
        if FolderTextImporter.importableFileExtensions.contains(where: { lowercasedDetail.hasSuffix(".\($0)") }) {
            return .localFile
        }
        return .imported
    }
}

struct PracticeLibrarySummary: Identifiable, Hashable {
    let id: String
    let name: String
    let itemCount: Int
    let completedCount: Int
    let mistakeCount: Int
    let detail: String
    let isActive: Bool

    var origin: PracticeLibraryOrigin {
        PracticeLibraryOrigin.inferred(name: name, detail: detail)
    }

    var isLocalFileLibrary: Bool {
        origin == .localFile
    }
}
