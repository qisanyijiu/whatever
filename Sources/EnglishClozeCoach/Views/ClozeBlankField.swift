import SwiftUI

struct ClozeBlankField: View {
    let blank: ClozeBlank
    @ObservedObject var store: PracticeStore
    var focusedBlankID: FocusState<ClozeBlank.ID?>.Binding?
    var locksCorrectAnswers = false
    var onAnswerChanged: (ClozeBlank, String, ClozeBlankInputState) -> Void = { _, _, _ in }

    var body: some View {
        let state = ClozeBlankInputState(store.answerState(for: blank))
        ClozeBlankInputField(
            blank: blank,
            text: binding,
            state: state,
            showsAnswer: false,
            isReadOnly: locksCorrectAnswers && state == .correct,
            focusedBlankID: focusedBlankID
        )
    }

    private var binding: Binding<String> {
        Binding(
            get: { store.answerText(for: blank) },
            set: {
                store.setAnswer($0, for: blank)
                onAnswerChanged(
                    blank,
                    store.answerText(for: blank),
                    ClozeBlankInputState(store.answerState(for: blank))
                )
            }
        )
    }
}
