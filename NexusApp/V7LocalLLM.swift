import Foundation
import SwiftUI
import UniformTypeIdentifiers
import NobodyWho

struct NexusPortableModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let path: String
    let source: String
    var enabledForEnsemble: Bool

    var isPreset: Bool { path.hasPrefix("hf://") || path.hasPrefix("https://") }
}

@MainActor
final class NexusPortableModelStore: ObservableObject {
    @Published var models: [NexusPortableModel] = []
    @Published var activeModelID: String = ""
    @Published var status: String = "No portable model loaded"
    @Published var progress: Double = 0
    @Published var busy = false
    @Published var lastError = ""

    private var chat: Chat?
    private let defaultsKey = "nexus.portable.models.v1"
    private let activeKey = "nexus.portable.active.v1"

    init() {
        loadCatalog()
    }

    static let qwenTinyPreset = NexusPortableModel(
        id: "qwen3-0.6b-q4",
        name: "Qwen3 0.6B Q4",
        path: "hf://NobodyWho/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf",
        source: "Optional GGUF download • llama.cpp runtime",
        enabledForEnsemble: true
    )

    func addTinyPreset() {
        guard !models.contains(where: { $0.id == Self.qwenTinyPreset.id }) else { return }
        models.append(Self.qwenTinyPreset)
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
            let id = "local:\(destination.lastPathComponent.lowercased())"
            let item = NexusPortableModel(id: id, name: destination.deletingPathExtension().lastPathComponent, path: destination.path, source: "Imported local GGUF", enabledForEnsemble: models.filter(\.enabledForEnsemble).count < 2)
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
            let stream = chat.ask(prompt)
            let answer = try await stream.completed()
            return answer.trimmingCharacters(in: .whitespacesAndNewlines)
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
                systemPrompt: "You are one independent local analyst in an ensemble. Use only evidence supplied. Return a concise interpretation plus uncertainty. Do not infer protected/sensitive traits.",
                contextSize: 3072,
                threadCount: nil,
                onDownloadProgress: { _, _ in }
            )
            let prompt = "QUESTION: \(question)\nEVIDENCE:\n\(String(context.prefix(6500)))\nGive one concise evidence-based opinion."
            let output = try await localChat.ask(prompt).completed()
            return NexusModelOpinion(id: "portable:\(model.id)", model: model.name, role: "local GGUF generative interpretation", finding: output.trimmingCharacters(in: .whitespacesAndNewlines), confidence: 0.62, evidence: ["Local GGUF runtime • no API key", model.source])
        } catch {
            return NexusModelOpinion(id: "portable:\(model.id)", model: model.name, role: "local GGUF generative interpretation", finding: "This model could not complete the local inference pass: \(error.localizedDescription)", confidence: 0.10, evidence: [])
        }
    }

    func toggleEnsemble(_ model: NexusPortableModel) {
        guard let idx = models.firstIndex(where: { $0.id == model.id }) else { return }
        if !models[idx].enabledForEnsemble && models.filter(\.enabledForEnsemble).count >= 2 { return }
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
    @StateObject private var store = NexusPortableModelStore()
    @State private var picker = false

    var body: some View {
        List {
            Section {
                Text("Run additional LLMs fully on-device through a llama.cpp-based Swift runtime. Model weights are optional and separate from the NEXUS IPA.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.busy || store.progress > 0 {
                    ProgressView(value: store.progress) { Text(store.status).font(.caption) }
                } else { Text(store.status).font(.caption).foregroundStyle(.secondary) }
                if !store.lastError.isEmpty { Text(store.lastError).font(.caption).foregroundStyle(.red) }
            }

            Section("Quick model") {
                Button { store.addTinyPreset() } label: { Label("Add Qwen3 0.6B Q4", systemImage: "arrow.down.circle.fill") }
                Text("This preset is intentionally small for iPhone. The first Load may download its GGUF weights; later inference is local and needs no API key.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Your GGUF models") {
                Button { picker = true } label: { Label("Import GGUF model", systemImage: "square.and.arrow.down") }
                ForEach(store.models) { model in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading) { Text(model.name).font(.headline); Text(model.source).font(.caption).foregroundStyle(.secondary) }
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
                Text("NEXUS runs at most two optional GGUF models in an ensemble and evaluates them sequentially rather than holding several large LLMs in RAM at once. Apple Intelligence and the lightweight statistical/NLP engines remain separate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Portable Local LLMs")
        .sheet(isPresented: $picker) { NexusGGUFDocumentPicker { url in picker = false; Task { await store.importGGUF(url) } } }
    }
}
