import SwiftUI
@preconcurrency import Translation

@available(macOS 15.0, *)
struct SystemTranslationTaskView: View {
    @ObservedObject var coordinator: SystemTranslationCoordinator
    @State private var configuration: TranslationSession.Configuration?

    private let sourceLanguage = Locale.Language(identifier: "en")
    private let targetLanguage = Locale.Language(identifier: "zh-Hans")

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                refreshConfiguration()
            }
            .onChange(of: coordinator.activeRequest?.id) {
                refreshConfiguration()
            }
            .translationTask(configuration) { session in
                guard let request = coordinator.activeRequest else {
                    return
                }
                await translate(request, session: session)
            }
    }

    private func refreshConfiguration() {
        guard coordinator.activeRequest != nil else {
            configuration = nil
            return
        }

        if var current = configuration {
            current.invalidate()
            configuration = current
        } else {
            configuration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage
            )
        }
    }

    private func translate(_ request: SystemTranslationRequest, session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            var translations = Array(repeating: "", count: request.sourceTexts.count)

            for index in request.sourceTexts.indices {
                do {
                    let translation = try await translateText(request.sourceTexts[index], session: session)
                    translations[index] = translation
                    coordinator.recordProgress(requestID: request.id, index: index, translation: translation)
                } catch {
                    coordinator.recordFailure(requestID: request.id, index: index, error: error)
                }
            }

            coordinator.complete(requestID: request.id, translations: translations)
        } catch {
            coordinator.fail(requestID: request.id, error: error)
        }
    }

    private func translateText(_ text: String, session: TranslationSession) async throws -> String {
        do {
            let response = try await session.translate(text)
            return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let response = try await session.translate(text)
            return response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
