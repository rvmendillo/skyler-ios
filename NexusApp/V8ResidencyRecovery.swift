import SwiftUI

struct NexusResidencyRecoveryView: View {
    @ObservedObject private var language = NexusPortableModelStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastActiveID = UserDefaults.standard.string(forKey: "nexus.residency.lastObservedLanguage.v1") ?? ""

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear {
                if !language.activeModelID.isEmpty { remember(language.activeModelID) }
            }
            .onChange(of: language.activeModelID) { _, newID in
                if !newID.isEmpty { remember(newID) }
            }
            .onChange(of: language.status) { _, newStatus in
                let status = newStatus.lowercased()
                if language.activeModelID.isEmpty &&
                    (status.contains("ensemble pass complete") || status.contains("temporary model memory released")) {
                    restoreLastActive(after: 250_000_000)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, language.activeModelID.isEmpty else { return }
                let status = language.status.lowercased()
                if status.contains("memory pressure") {
                    restoreLastActive(after: 1_200_000_000)
                }
            }
    }

    private func remember(_ id: String) {
        lastActiveID = id
        UserDefaults.standard.set(id, forKey: "nexus.residency.lastObservedLanguage.v1")
    }

    private func restoreLastActive(after delay: UInt64) {
        let id = lastActiveID
        guard !id.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard language.activeModelID.isEmpty, !language.busy,
                  let model = language.models.first(where: { $0.id == id }),
                  language.isDownloaded(model) else { return }
            await NexusModelResidencyCoordinator.shared.loadLanguage(model)
        }
    }
}
