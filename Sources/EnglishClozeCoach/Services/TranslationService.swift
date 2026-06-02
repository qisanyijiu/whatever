import Foundation

protocol TranslationService {
    func translate(english: String) -> String
}

struct PlaceholderTranslationService: TranslationService {
    func translate(english: String) -> String {
        "待翻译"
    }
}
