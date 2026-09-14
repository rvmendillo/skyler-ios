import SwiftUI

@main
struct NEXUSApp: App {
    @StateObject private var model = NexusModel()

    var body: some Scene {
        WindowGroup {
            RootV8View()
                .environmentObject(model)
                .background(NexusResidencyRecoveryView())
                .task {
                    let intelligence = NexusV9IntelligenceStore.shared
                    let residency = NexusModelResidencyCoordinator.shared
                    let language = NexusPortableModelStore.shared
                    let files = NexusV8FileLibrary.shared.files

                    await intelligence.index(records: model.records, files: files)

                    let hasVision = residency.hasDownloadedVisionModel()
                    if !hasVision && intelligence.performanceMode != .battery {
                        await restoreLastLanguageModelOrWarm(intelligence: intelligence, residency: residency, language: language)
                    }

                    await NexusPreanalysisStore.shared.analyzePending(files)

                    if hasVision && intelligence.performanceMode != .battery {
                        await restoreLastLanguageModelOrWarm(intelligence: intelligence, residency: residency, language: language)
                    }
                }
                .onOpenURL { url in
                    NexusV9DeepLink.shared.handle(url, model: model)
                }
        }
    }

    @MainActor
    private func restoreLastLanguageModelOrWarm(
        intelligence: NexusV9IntelligenceStore,
        residency: NexusModelResidencyCoordinator,
        language: NexusPortableModelStore
    ) async {
        guard language.activeModelID.isEmpty else { return }

        if let lastID = UserDefaults.standard.string(forKey: "nexus.residency.lastObservedLanguage.v1"),
           let last = language.models.first(where: { $0.id == lastID }),
           language.isDownloaded(last) {
            await residency.loadLanguage(last)
            return
        }

        await residency.restorePreferredLanguageIfNeeded()
        if language.activeModelID.isEmpty {
            await intelligence.warmBestLocalModel()
            residency.adoptActiveLanguageIfNeeded()
        }
    }
}
