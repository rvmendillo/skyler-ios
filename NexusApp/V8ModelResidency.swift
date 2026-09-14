import Foundation
import SwiftUI

@MainActor
final class NexusModelResidencyCoordinator: ObservableObject {
    static let shared = NexusModelResidencyCoordinator()

    @Published private(set) var preferredLanguageModelID: String
    @Published private(set) var preferredVisionPresetID: String
    @Published var keepPreferredLanguageLoaded: Bool {
        didSet { UserDefaults.standard.set(keepPreferredLanguageLoaded, forKey: keepLanguageKey) }
    }
    @Published private(set) var residencyStatus = "Model residency ready"

    private let languageKey = "nexus.residency.preferredLanguage.v1"
    private let visionKey = "nexus.residency.preferredVision.v1"
    private let keepLanguageKey = "nexus.residency.keepLanguage.v1"
    private var temporaryLanguageSuspension = 0
    private var restoreTask: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        preferredLanguageModelID = defaults.string(forKey: languageKey) ?? ""
        preferredVisionPresetID = defaults.string(forKey: visionKey) ?? ""
        keepPreferredLanguageLoaded = defaults.object(forKey: keepLanguageKey) == nil ? true : defaults.bool(forKey: keepLanguageKey)
    }

    func loadLanguage(_ model: NexusPortableModel) async {
        preferredLanguageModelID = model.id
        UserDefaults.standard.set(model.id, forKey: languageKey)
        residencyStatus = "Loading preferred language model…"
        await NexusPortableModelStore.shared.load(model)
        if NexusPortableModelStore.shared.activeModelID == model.id {
            residencyStatus = "Preferred language model resident"
        }
    }

    func clearLanguagePreference(if modelID: String? = nil) {
        if let modelID, preferredLanguageModelID != modelID { return }
        preferredLanguageModelID = ""
        UserDefaults.standard.removeObject(forKey: languageKey)
        restoreTask?.cancel()
    }

    func adoptActiveLanguageIfNeeded() {
        guard preferredLanguageModelID.isEmpty else { return }
        let active = NexusPortableModelStore.shared.activeModelID
        guard !active.isEmpty else { return }
        preferredLanguageModelID = active
        UserDefaults.standard.set(active, forKey: languageKey)
    }

    func restorePreferredLanguageIfNeeded() async {
        guard keepPreferredLanguageLoaded, temporaryLanguageSuspension == 0 else { return }
        let store = NexusPortableModelStore.shared
        guard store.activeModelID.isEmpty, !store.busy else { return }
        guard !preferredLanguageModelID.isEmpty,
              let model = store.models.first(where: { $0.id == preferredLanguageModelID }),
              store.isDownloaded(model) else { return }
        residencyStatus = "Restoring preferred language model…"
        await store.load(model)
        if store.activeModelID == model.id { residencyStatus = "Preferred language model restored" }
    }

    func rememberVision(_ preset: NexusMultimodalPreset) {
        preferredVisionPresetID = preset.id
        UserDefaults.standard.set(preset.id, forKey: visionKey)
    }

    func clearVisionPreference(if presetID: String? = nil) {
        if let presetID, preferredVisionPresetID != presetID { return }
        preferredVisionPresetID = ""
        UserDefaults.standard.removeObject(forKey: visionKey)
    }

    func loadVision(_ preset: NexusMultimodalPreset) async {
        rememberVision(preset)
        await NexusMultimodalStore.shared.load(preset)
    }

    func bestDownloadedVisionPreset() -> NexusMultimodalPreset? {
        let vision = NexusMultimodalStore.shared
        if let active = NexusMultimodalStore.presets.first(where: { $0.id == vision.activePresetID && vision.isDownloaded($0) }) {
            return active
        }
        if let preferred = NexusMultimodalStore.presets.first(where: { $0.id == preferredVisionPresetID && vision.isDownloaded($0) }) {
            return preferred
        }
        if vision.isDownloaded(vision.selectedPreset) { return vision.selectedPreset }
        return NexusMultimodalStore.presets.first(where: { vision.isDownloaded($0) })
    }

    func hasDownloadedVisionModel() -> Bool {
        bestDownloadedVisionPreset() != nil
    }

    func withVisionRuntime<T>(_ operation: @escaping () async -> T) async -> T? {
        let vision = NexusMultimodalStore.shared
        guard let preset = bestDownloadedVisionPreset() else { return nil }

        let language = NexusPortableModelStore.shared
        let previousLanguageID = language.activeModelID
        let previousLanguage = language.models.first(where: { $0.id == previousLanguageID })
        let visionWasAlreadyActive = vision.activePresetID == preset.id

        if !previousLanguageID.isEmpty {
            temporaryLanguageSuspension += 1
            residencyStatus = "Temporarily freeing language-model RAM for vision analysis"
            language.unload()
        }

        if !visionWasAlreadyActive {
            residencyStatus = "Loading vision model for analyzed library…"
            await vision.load(preset)
        }

        guard vision.activePresetID == preset.id else {
            if temporaryLanguageSuspension > 0 { temporaryLanguageSuspension -= 1 }
            if let previousLanguage { await loadLanguage(previousLanguage) }
            return nil
        }

        let value = await operation()

        if !visionWasAlreadyActive {
            vision.unload()
        }

        if temporaryLanguageSuspension > 0 { temporaryLanguageSuspension -= 1 }
        if let previousLanguage, keepPreferredLanguageLoaded {
            residencyStatus = "Restoring language model after vision analysis…"
            await loadLanguage(previousLanguage)
        }
        return value
    }

    func handleLanguageRuntimeStatus(_ status: String) {
        guard keepPreferredLanguageLoaded, temporaryLanguageSuspension == 0 else { return }
        let lower = status.lowercased()
        guard lower.contains("ensemble pass complete") || lower.contains("temporary model memory released") else { return }
        scheduleLanguageRestore(afterNanoseconds: 250_000_000)
    }

    func handleAppBecameActive() {
        guard keepPreferredLanguageLoaded, temporaryLanguageSuspension == 0 else { return }
        let status = NexusPortableModelStore.shared.status.lowercased()
        // If iOS forced a memory-pressure release, wait for a foreground transition before trying again.
        if status.contains("memory pressure") || status.contains("ensemble pass complete") || status.contains("temporary model memory released") {
            scheduleLanguageRestore(afterNanoseconds: 900_000_000)
        }
    }

    private func scheduleLanguageRestore(afterNanoseconds delay: UInt64) {
        restoreTask?.cancel()
        restoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            await self.restorePreferredLanguageIfNeeded()
        }
    }
}

struct NexusResidencyWatcherView: View {
    @ObservedObject private var language = NexusPortableModelStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onChange(of: language.status) { _, newStatus in
                NexusModelResidencyCoordinator.shared.handleLanguageRuntimeStatus(newStatus)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    NexusModelResidencyCoordinator.shared.handleAppBecameActive()
                }
            }
    }
}

struct SharedVisionModelsEnhancedView: View {
    @ObservedObject private var store = NexusMultimodalStore.shared
    @ObservedObject private var residency = NexusModelResidencyCoordinator.shared

    var body: some View {
        List {
            Section {
                Text("Vision models are shared by the Analyzed Library, Chat and file tools. NEXUS remembers the model you explicitly load and reuses any installed vision model for automatic library analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if store.busy || store.progress > 0 {
                    ProgressView(value: store.progress) { Text(store.status).font(.caption) }
                    if !store.combinedDownloadDetail.isEmpty {
                        Text(store.combinedDownloadDetail).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
                if !store.lastError.isEmpty { Text(store.lastError).font(.caption).foregroundStyle(.red) }
            }

            Section("Vision models") {
                ForEach(NexusMultimodalStore.presets) { preset in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.headline)
                                Text("\(preset.approximateDownload) • \(preset.detail)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.activePresetID == preset.id {
                                Label("Loaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                            } else if store.isDownloaded(preset) {
                                Image(systemName: "internaldrive.fill").foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            if !store.isDownloaded(preset) {
                                Button("Download") { Task { await store.download(preset) } }
                                    .buttonStyle(.bordered)
                                    .disabled(store.busy)
                            }
                            Button(store.activePresetID == preset.id ? "Reload" : "Load") {
                                Task { await residency.loadVision(preset) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.busy)

                            if store.activePresetID == preset.id {
                                Button("Unload") {
                                    store.unload()
                                    residency.clearVisionPreference(if: preset.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        if store.isDownloaded(preset) {
                            Button(role: .destructive) {
                                store.removeWeights(preset)
                                residency.clearVisionPreference(if: preset.id)
                            } label: {
                                Label("Delete download", systemImage: "internaldrive.badge.minus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.busy)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            Section("Automatic analyzed-library behavior") {
                Text("When bulk analysis needs vision while a language model is resident, NEXUS temporarily frees the language runtime, performs the vision batch, then restores your preferred language model. This avoids two heavyweight runtimes competing for RAM while keeping your explicit model choice intact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Shared Vision Models")
    }
}
