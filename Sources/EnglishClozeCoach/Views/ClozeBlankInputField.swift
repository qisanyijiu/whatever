import SwiftUI

enum ClozeBlankInputState: Equatable {
    case idle
    case correct
    case incorrect

    init(_ answerState: PracticeStore.AnswerState) {
        switch answerState {
        case .idle:
            self = .idle
        case .correct:
            self = .correct
        case .incorrect:
            self = .incorrect
        }
    }

    var underlineColor: Color {
        switch self {
        case .idle:
            return .secondary.opacity(0.35)
        case .correct:
            return .green
        case .incorrect:
            return .red
        }
    }
}

struct ClozeBlankInputField: View {
    let blank: ClozeBlank
    @Binding var text: String
    let state: ClozeBlankInputState
    let showsAnswer: Bool
    var isReadOnly = false
    var focusedBlankID: FocusState<ClozeBlank.ID?>.Binding?

    var body: some View {
        VStack(spacing: 4) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 34, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(width: fieldWidth)
                .modifier(ClozeBlankFocusModifier(focusedBlankID: focusedBlankID, blankID: blank.id))
                .disabled(isReadOnly)
                .accessibilityLabel(AppStrings.clozeBlankAccessibilityLabel)
                .accessibilityValue(text)
                .accessibilityHint(AppStrings.clozeBlankAccessibilityHint)

            Rectangle()
                .fill(state.underlineColor)
                .frame(width: fieldWidth, height: 3)

            if showsAnswer {
                Text(blank.answer)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .frame(width: fieldWidth)
    }

    private var fieldWidth: CGFloat {
        ClozeBlankInputMetrics.width(for: blank.answer)
    }
}

private enum ClozeBlankInputMetrics {
    static func width(for answer: String) -> CGFloat {
        min(280, max(54, CGFloat(answer.count) * 24 + 18))
    }
}

private struct ClozeBlankFocusModifier: ViewModifier {
    let focusedBlankID: FocusState<ClozeBlank.ID?>.Binding?
    let blankID: ClozeBlank.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focusedBlankID {
            content.focused(focusedBlankID, equals: blankID)
        } else {
            content
        }
    }
}
