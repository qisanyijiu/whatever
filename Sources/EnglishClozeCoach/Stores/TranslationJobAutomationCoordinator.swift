import Foundation

@MainActor
final class TranslationJobAutomationCoordinator: ObservableObject {
    private var autoImportedTranslationJobIDs = Set<TranslationJob.ID>()
    private var systemTranslatingJobIDs = Set<TranslationJob.ID>()

    func sync(
        jobStore: TranslationJobStore,
        practiceStore: PracticeStore,
        systemTranslator: SystemTranslationCoordinator
    ) {
        translateLocalFileJobsWithSystemAPI(jobStore: jobStore, systemTranslator: systemTranslator)
        autoImportCompletedTranslationJobs(jobStore: jobStore, practiceStore: practiceStore)
    }

    private func translateLocalFileJobsWithSystemAPI(
        jobStore: TranslationJobStore,
        systemTranslator: SystemTranslationCoordinator
    ) {
        for job in jobStore.jobs where job.needsSystemTranslation {
            guard !systemTranslatingJobIDs.contains(job.id) else {
                continue
            }
            systemTranslatingJobIDs.insert(job.id)

            Task { @MainActor in
                let requests = jobStore.systemTranslationRequests(for: job.id)
                guard !requests.isEmpty else {
                    systemTranslatingJobIDs.remove(job.id)
                    return
                }

                do {
                    jobStore.markSystemTranslationStarted(jobID: job.id)
                    let translations = try await systemTranslator.translateEnglishToSimplifiedChinese(
                        requests.map(\.sourceText),
                        progress: { index, translation in
                            guard requests.indices.contains(index) else {
                                return
                            }
                            jobStore.applySystemTranslation(
                                jobID: job.id,
                                itemID: requests[index].itemID,
                                translation: translation
                            )
                        },
                        failure: { index, _, error in
                            guard requests.indices.contains(index) else {
                                return
                            }
                            jobStore.markSystemTranslationItemFailed(
                                jobID: job.id,
                                itemID: requests[index].itemID,
                                message: "macOS 系统翻译失败：\(error.localizedDescription)"
                            )
                        }
                    )
                    let translationsByItemID = Dictionary(
                        uniqueKeysWithValues: zip(requests.map(\.itemID), translations)
                    )
                    jobStore.applySystemTranslations(
                        jobID: job.id,
                        translationsByItemID: translationsByItemID
                    )
                    jobStore.finishSystemTranslation(jobID: job.id)
                } catch {
                    jobStore.markSystemTranslationFailed(
                        jobID: job.id,
                        message: "macOS 系统翻译失败：\(error.localizedDescription)"
                    )
                }
                systemTranslatingJobIDs.remove(job.id)
            }
        }
    }

    private func autoImportCompletedTranslationJobs(
        jobStore: TranslationJobStore,
        practiceStore: PracticeStore
    ) {
        for job in jobStore.jobs where job.status == .completed {
            guard job.importedToLibraryAt == nil else {
                continue
            }
            guard !autoImportedTranslationJobIDs.contains(job.id) else {
                continue
            }
            autoImportedTranslationJobIDs.insert(job.id)

            guard let draft = jobStore.importDraft(for: job.id) else {
                autoImportedTranslationJobIDs.remove(job.id)
                continue
            }

            let savedCount = practiceStore.saveImportDraft(draft, selectAfterSave: false)
            if savedCount > 0 {
                jobStore.markImportedToLibrary(jobID: job.id)
            } else {
                autoImportedTranslationJobIDs.remove(job.id)
            }
        }
    }
}
