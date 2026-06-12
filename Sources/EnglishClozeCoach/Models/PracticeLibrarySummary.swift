import Foundation

struct PracticeLibrarySummary: Identifiable, Hashable {
    let id: String
    let name: String
    let itemCount: Int
    let completedCount: Int
    let mistakeCount: Int
    let detail: String
    let isActive: Bool

    var isLocalFileLibrary: Bool {
        if name == "本地文件题库" || detail.contains("本地文件") || detail.contains("英文文件") {
            return true
        }

        let lowercasedDetail = detail.lowercased()
        return [
            ".txt", ".text", ".md", ".markdown", ".srt", ".vtt", ".html", ".htm",
            ".csv", ".tsv", ".json", ".jsonl", ".log", ".sub", ".sbv", ".ass", ".ssa"
        ].contains { lowercasedDetail.hasSuffix($0) }
    }
}
