import Foundation
import SwiftUI
import UniformTypeIdentifiers
import NobodyWho

struct NexusPortableModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let path: String
    let source: String
    let approximateSize: String
    var enabledForEnsemble: Bool

    var isPreset: Bool { path.hasPrefix("hf://") || path.hasPrefix("https://") }
}

@MainActor
final class NexusPortableModelStore: ObservableObject {
    static let shared = NexusPortableModelStore()

    @Published var models: [NexusPortableModel] = []
    @Published var activeModelID: String = ""
    @Published var status: String = "No portable model loaded"
    @Published var progress: Double = 0
    @Published var busy = false
    @Published var lastError = ""

    private var chat: Chat?
    private let defaultsKey = "nexus.portable.models.v2"
    private let activeKey = "nexus.portable.active.v2"

    init() { loadCatalog() }

    static let qwenTinyPreset = NexusPortableModel(
        id: "qwen3-0.6b-q4",
        name: "Qwen3 0.6B Q4",
        path: "hf://NobodyWho/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf",
        source: "NobodyWho-compatible GGUF • multilingual reasoning",
        approximateSize: "~484 MB",
        enabledForEnsemble: true
    )

    static let smolTinyPreset = NexusPortableModel(
        id: "smollm2-360m-instruct-q4",
        name: "SmolLM2 360M Instruct Q4",
        path: "hf://tensorblock/SmolLM2-360M-Instruct-GGUF/SmolLM2-360M-Instruct-Q4_K_M.gguf",
        source: "GGUF • very small instruction model",
        approximateSize: "~271 MB",
        enabledForEnsemble: false
    )

    static let qwenBalancedPreset = NexusPortableModel(
        id: "qwen3-1.7b-q4",
        name: "Qwen3 1.7B Q4",
        path: "hf://NobodyWho/Qwen_Qwen3-1.7B-GGUF/Qwen_Qwen3-1.7B-Q4_K_M.gguf",
        source: "NobodyWho-compatible GGUF • higher quality, heavier",
        approximateSize: "~1.28 GB",
        enabledForEnsemble: false
    )

    func addPreset(_ preset: NexusPortableModel) {
        guard !models.contains(where: { $0.id == preset.id }) else { return }
        models.append(preset)
        persist()
    }

    func importGGUF(_ url: URL) async {
        busy = true
        progress = 0.05
        status = "Copying local GGUF model…"
        lastError = ""
        defer { busy = false }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let fm = FileManager.default
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("NEXUS-Models", isDirectory: true)
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            let destination = base.appendingPathComponent(url.lastPathComponent)
            progress = 0.25
            if fm.fileExists(atPath: destination.path) {
                let srcSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                let dstSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -2
                if srcSize != dstSize {
                    try fm.removeItem(at: destination)
                    try fm.copyItem(at: url, to: destination)
                }
            } else {
                try fm.copyItem(at: url, to: destination)
            }
            progress = 0.85
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let mb = max(1, bytes / 1_048_576)
            let id = "local:\(destination.lastPathComponent.lowercased())"
            let item = NexusPortableModel(id: id,
                                          name: destination.deletingPathExtension().lastPathComponent,
                                          path: destination.path,
                                          source: "Imported local GGUF",
                                          approximateSize: "~\(mb) MB",
                                          enabledForEnsemble: models.filter { $0.enabledForEnsemble }.count < 2)
            if let idx = models.firstIndex(where: { $0.id == id }) { models[idx] = item } else { models.append(item) }
            persist()
            progress = 1
            status = "Model installed • tap Load"
        } catch {
            lastError = error.localizedDescription
            status = "Model import failed"
        }
    }

    func load(_ model: NexusPortableModel) async {
        guard !busy else { return }
        busy = true
        progress = 0.02
        status = "Loading \(model.name)…"
        lastError = ""
        defer { busy = false }
        do {
            let loaded = try await Chat.fromPath(
                modelPath: model.path,
                useGpu: true,
                systemPrompt: "You are a private on-device NEXUS reasoning model. Be concise, distinguish evidence from inference, and never invent personal facts.",
                contextSize: 4096,
                threadCount: nil,
                onDownloadProgress: { downloaded, total in
                    let fraction = total > 0 ? Double(downloaded) / Double(total) : 0
                    Task { @MainActor in self.progress = max(0.02, min(0.92, fraction * 0.92)) }
                }
            )
            chat = loaded
            activeModelID = model.id
            UserDefaults.standard.set(model.id, forKey: activeKey)
            progress = 1
            status = "Loaded • \(model.name) • Metal/GGUF"
        } catch {
            lastError = error.localizedDescription
            status = "Could not load \(model.name)"
            chat = nil
        }
    }

    func unload() {
        chat?.stopGeneration()
        chat = nil
        activeModelID = ""
        UserDefaults.standard.removeObject(forKey: activeKey)
        status = "Portable model unloaded"
        progress = 0
    }

    func respond(_ prompt: String, systemContext: String = "") async -> String? {
        guard let chat else { return nil }
        do {
            if !systemContext.isEmpty {
                try await chat.setSystemPrompt("You are a private NEXUS on-device reasoning model. Use only supplied evidence for personal claims. \(systemContext)")
            }
            return try await chat.ask(prompt).completed().trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func opinionFromModel(_ model: NexusPortableModel, question: String, context: String) async -> NexusModelOpinion? {
        guard model.enabledForEnsemble else { return nil }
        do {
            status = "Consulting \(model.name)…"
            let localChat = try await Chat.fromPath(
                modelPath: model.path,
                useGpu: true,
                systemPrompt: "You are one independent local analyst in an ensemble. Use only supplied evidence. Return a concise interpretation plus uncertainty. Do not infer protected/sensitive traits.",
                contextSize: 3072,
                threadCount: nil,
                onDownloadProgress: { _, _ in }
            )
            let prompt = "QUESTION: \(question)\nEVIDENCE:\n\(String(context.prefix(6500)))\nGive one concise evidence-based opinion."
            let output = try await localChat.ask(prompt).completed()
            return NexusModelOpinion(id: "portable:\(model.id)", model: model.name, role: "local GGUF generative interpretation", finding: output.trimmingCharacters(in: .whitespacesAndNewlines), confidence: 0.62, evidence: ["Local GGUF runtime • no API key", model.source])
        } catch {
            return NexusModelOpinion(id: "portable:\(model.id)", model: model.name, role: "local GGUF generative interpretation", finding: "This optional model could not complete its inference pass: \(error.localizedDescription)", confidence: 0.10, evidence: [])
        }
    }

    func ensembleModels() -> [NexusPortableModel] {
        Array(models.filter { $0.enabledForEnsemble }.prefix(2))
    }

    func toggleEnsemble(_ model: NexusPortableModel) {
        guard let idx = models.firstIndex(where: { $0.id == model.id }) else { return }
        if !models[idx].enabledForEnsemble && models.filter({ $0.enabledForEnsemble }).count >= 2 {
            status = "For memory safety, NEXUS uses at most two portable LLMs in one ensemble pass."
            return
        }
        models[idx].enabledForEnsemble.toggle()
        persist()
    }

    func delete(_ model: NexusPortableModel) {
        if activeModelID == model.id { unload() }
        if !model.isPreset { try? FileManager.default.removeItem(atPath: model.path) }
        models.removeAll { $0.id == model.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(models) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    private func loadCatalog() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey), let decoded = try? JSONDecoder().decode([NexusPortableModel].self, from: data) { models = decoded }
        activeModelID = UserDefaults.standard.string(forKey: activeKey) ?? ""
    }
}

struct NexusGGUFDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let type = UTType(filenameExtension: "gguf") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [type, .data], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NexusGGUFDocumentPicker
        init(parent: NexusGGUFDocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let url = urls.first { parent.onPick(url) } }
    }
}

struct PortableModelsV7View: View {
    @ObservedObject private var store = NexusPortableModelStore.shared
    @State private var picker = false

    var body: some View {
        List {
            Section {
                Text("Additional LLMs run fully on-device through an iOS Swift runtime powered by llama.cpp. Model weights are optional and separate from the NEXUS IPA.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.busy || store.progress > 0 {
                    ProgressView(value: store.progress) { Text(store.status).font(.caption) }
                } else { Text(store.status).font(.caption).foregroundStyle(.secondary) }
                if !store.lastError.isEmpty { Text(store.lastError).font(.caption).foregroundStyle(.red) }
            }

            Section("iPhone presets") {
                preset(NexusPortableModelStore.smolTinyPreset, note: "Smallest preset; useful as a fast second opinion.")
                preset(NexusPortableModelStore.qwenTinyPreset, note: "Better multilingual reasoning while still relatively compact.")
                preset(NexusPortableModelStore.qwenBalancedPreset, note: "Optional heavier model for devices with more free memory/storage.")
            }

            Section("Your GGUF models") {
                Button { picker = true } label: { Label("Import any compatible GGUF", systemImage: "square.and.arrow.down") }
                ForEach(store.models) { model in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.name).font(.headline)
                                Text("\(model.approximateSize) • \(model.source)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.activeModelID == model.id { Label("Loaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                        }
                        HStack {
                            Button(store.activeModelID == model.id ? "Reload" : "Load") { Task { await store.load(model) } }.buttonStyle(.borderedProminent).disabled(store.busy)
                            Button(model.enabledForEnsemble ? "In ensemble" : "Add to ensemble") { store.toggleEnsemble(model) }.buttonStyle(.bordered)
                            Button(role: .destructive) { store.delete(model) } label: { Image(systemName: "trash") }.buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 4)
                }
            }

            Section("Memory safety") {
                Text("Portable LLMs are evaluated sequentially and NEXUS caps the optional ensemble at two GGUF models. This avoids holding several large models in memory at once. Apple Intelligence, sentence embeddings, entity extraction and statistical engines remain separate ensemble members.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Portable Local LLMs")
        .sheet(isPresented: $picker) { NexusGGUFDocumentPicker { url in picker = false; Task { await store.importGGUF(url) } } }
    }

    @ViewBuilder private func preset(_ model: NexusPortableModel, note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cpu.fill").foregroundStyle(.cyan).padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(.headline)
                Text("\(model.approximateSize) • \(note)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.models.contains(where: { $0.id == model.id }) ? "Added" : "Add") { store.addPreset(model) }.buttonStyle(.bordered).disabled(store.models.contains(where: { $0.id == model.id }))
        }
    }
}
