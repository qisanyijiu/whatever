import Foundation

struct PracticeItem: Identifiable, Hashable, Codable {
    let id: String
    let sourceChinese: String
    let targetEnglish: String
    let segments: [ClozeSegment]

    var blanks: [ClozeBlank] {
        segments.compactMap { segment in
            if case let .blank(blank) = segment {
                return blank
            }
            return nil
        }
    }
}

enum ClozeSegment: Hashable, Codable {
    case text(String)
    case blank(ClozeBlank)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case blank
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "blank":
            self = .blank(try container.decode(ClozeBlank.self, forKey: .blank))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown cloze segment type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .blank(blank):
            try container.encode("blank", forKey: .type)
            try container.encode(blank, forKey: .blank)
        }
    }
}

struct ClozeBlank: Identifiable, Hashable, Codable {
    let id: String
    let answer: String
}
