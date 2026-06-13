import Foundation

@MainActor
final class ClozeBlankFocusAdvanceController: ObservableObject {
    private var task: Task<Void, Never>?

    func schedule(
        after blank: ClozeBlank,
        expectedAnswer: String,
        blanks: [ClozeBlank],
        currentFocusedID: @escaping @MainActor () -> ClozeBlank.ID?,
        currentAnswer: @escaping @MainActor (ClozeBlank) -> String,
        isCorrect: @escaping @MainActor (ClozeBlank) -> Bool,
        focus: @escaping @MainActor (ClozeBlank.ID?) -> Void
    ) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard currentAnswer(blank) == expectedAnswer,
                      isCorrect(blank) else {
                    self.task = nil
                    return
                }
                guard currentFocusedID() == nil || currentFocusedID() == blank.id else {
                    self.task = nil
                    return
                }
                guard let currentIndex = blanks.firstIndex(where: { $0.id == blank.id }) else {
                    self.task = nil
                    return
                }

                let nextBlankID = blanks
                    .dropFirst(currentIndex + 1)
                    .first { !isCorrect($0) }?
                    .id
                focus(nextBlankID)
                self.task = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
