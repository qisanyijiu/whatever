import Foundation

@MainActor
final class TranslationJobPersistenceCoordinator {
    private let library: TranslationJobLibrary
    private var backgroundSaveTask: Task<Void, Never>?

    init(library: TranslationJobLibrary) {
        self.library = library
    }

    func cancel() {
        backgroundSaveTask?.cancel()
        backgroundSaveTask = nil
    }

    func save(_ jobs: [TranslationJob]) -> String? {
        do {
            try library.save(jobs)
            return nil
        } catch {
            return "保存翻译任务失败：\(error.localizedDescription)"
        }
    }

    func saveInBackground(
        _ jobs: [TranslationJob],
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        backgroundSaveTask?.cancel()
        let snapshot = jobs
        let lib = library
        backgroundSaveTask = Task.detached(priority: .background) {
            guard !Task.isCancelled else { return }
            do {
                try lib.save(snapshot)
            } catch {
                await MainActor.run {
                    onFailure("保存翻译任务失败：\(error.localizedDescription)")
                }
            }
        }
    }
}
