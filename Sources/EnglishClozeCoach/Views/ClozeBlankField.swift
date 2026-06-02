import SwiftUI

struct ClozeBlankField: View {
    let blank: ClozeBlank
    @ObservedObject var store: PracticeStore

    var body: some View {
        VStack(spacing: 4) {
            TextField("", text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: 34, weight: .medium))
                .multilineTextAlignment(.center)
                .frame(width: fieldWidth)

            Rectangle()
                .fill(underlineColor)
                .frame(width: fieldWidth, height: 3)
        }
        .frame(width: fieldWidth)
    }

    private var binding: Binding<String> {
        Binding(
            get: { store.answerText(for: blank) },
            set: { store.setAnswer($0, for: blank) }
        )
    }

    private var fieldWidth: CGFloat {
        min(240, max(86, CGFloat(blank.answer.count) * 18))
    }

    private var underlineColor: Color {
        switch store.answerState(for: blank) {
        case .idle:
            return .secondary.opacity(0.35)
        case .correct:
            return .green
        case .incorrect:
            return .red
        }
    }
}
