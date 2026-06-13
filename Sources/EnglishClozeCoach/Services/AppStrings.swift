import Foundation

enum AppStrings {
    static let completed = localized("completed")
    static let clozeBlankAccessibilityLabel = localized("cloze.blank.accessibility.label")
    static let clozeBlankAccessibilityHint = localized("cloze.blank.accessibility.hint")

    private static func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}
