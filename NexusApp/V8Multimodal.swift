import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO
import PDFKit
import QuickLookThumbnailing
import NobodyWho

struct NexusMultimodalPreset: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let basePath: String
    let projectionPath: String
    let approximateDownload: String
    let estimatedBytes: UInt64
    let detail: String
}

struct NexusMultimodalInstall: Codable, Hashable {
    let baseLocalPath: String
    let projectionLocalPath: String
}

struct NexusFileAnalysisResult: Identifiable, Hashable {
    let id = UUID()
    let fileName: String
    let kind: String
    let answer: String
}

@MainActor
final class NexusMultimodalStore: ObservableObject {
    static let shared = NexusMultimodalStore()

    @Published var selectedPresetID = "lfm25-vl-1.6b-q4"
    @Published var activePresetID = ""
    @Published var status = "Choose a multimodal model"
    @Published var progress: Double = 0
    @Published var busy = false
    @Published var lastError = ""
    @Published var results: [NexusFileAnalysisResult] = []
    @Published var languageDownload: NexusDownloadSnapshot = .zero
    @Published var visionDownload: NexusDownloadSnapshot = .zero
    @Published var downloadingPresetID = ""

    private var installs: [String:NexusMultimodalInstall] = [:]
    private var model: Model?
    private var chat: Chat?
    private var memoryObserver: NSObjectProtocol?
    private let installKey = "nexus.multimodal.installs.v1"

    static let lfm25 = NexusMultimodalPreset(
        id: "lfm25-vl-1.6b-q4",
        name: "LFM2.5-VL 1.6B Q4",
        basePath: "hf://LiquidAI/LFM2.5-VL-1.6B-GGUF/LFM2.5-VL-1.6B-Q4_0.gguf",
        projectionPath: "hf://LiquidAI/LFM2.5-VL-1.6B-GGUF/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf",
        approximateDownload: "~1.28 GB total",
        estimatedBytes: 1_279_000_000,
        detail: "Fast edge vision-language model for images, screenshots, scanned pages and visual file previews."
    )

    static let qwenVL3B = NexusMultimodalPreset(
        id: "qwen25-vl-3b-q4",
        name: "Qwen2.5-VL 3B Q4_K_M",
        basePath: "hf://ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf",
        projectionPath: "hf://ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf",
        approximateDownload: "~2.78 GB total",
        estimatedBytes: 2_775_000_000,
        detail: "Heavier vision-language model for richer document, chart, screenshot and image interpretation."
    )

    static let presets = [lfm25, qwenVL3B]

    init() {
        if let data = UserDefaults.standard.data(forKey: installKey),
           let decoded = try? JSONDecoder().decode([String:NexusMultimodalInstall].self, from: data) {
            installs = decoded.filter {
                FileManager.default.fileExists(atPath: $0.value.baseLocalPath) &&
                FileManager.default.fileExists(atPath: $0.value.projectionLocalPath)
            }
        }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.releaseRuntime(reason: "iOS memory pressure • multimodal model unloaded; downloads remain installed") }
        }
    }

    var selectedPreset: NexusMultimodalPreset {
        Self.presets.first { $0.id == selectedPresetID } ?? Self.lfm25
    }

    var combinedDownloadDetail: String {
        let total = languageDownload.totalBytes + visionDownload.totalBytes
        let done = languageDownload.downloadedBytes + visionDownload.downloadedBytes
        let speed = languageDownload.bytesPerSecond + visionDownload.bytesPerSecond
        guard total > 0 else { return "" }
        let fraction = Double(done) / Double(total)
        let doneText = ByteCountFormatter.string(fromByteCount: done, countStyle: .file)
        let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        var text = String(format: "%.1f%% • %@ / %@", fraction * 100, doneText, totalText)
        if speed > 0 {
            text += String(format: " • %.1f MB/s", speed / 1_048_576.0)
            if done < total {
                let eta = Double(total - done) / speed
                if eta >= 60 { text += String(format: " • ETA %.0fm %.0fs", floor(eta / 60), eta.truncatingRemainder(dividingBy: 60)) }
                else { text += String(format: " • ETA %.0fs", max(0, eta)) }
            }
        }
        let lanes = languageDownload.activeChunks + visionDownload.activeChunks
        if lanes > 0 { text += " • \(lanes) parallel lanes" }
        return text
    }

    func isDownloaded(_ preset: NexusMultimodalPreset) -> Bool {
        guard let i = installs[preset.id] else { return false }
        return FileManager.default.fileExists(atPath: i.baseLocalPath) && FileManager.default.fileExists(atPath: i.projectionLocalPath)
    }

    func download(_ preset: NexusMultimodalPreset) async {
        guard !busy else { return }
        busy = true
        downloadingPresetID = preset.id
        lastError = ""
        progress = 0.01
        languageDownload = .zero
        visionDownload = .zero
        status = "Preparing parallel multimodal download • \(preset.name)"
        defer {
            busy = false
            downloadingPresetID = ""
        }
        do {
            let baseName = preset.basePath.split(separator: "/").last.map(String.init) ?? "base.gguf"
            let projectionName = preset.projectionPath.split(separator: "/").last.map(String.init) ?? "mmproj.gguf"

            async let basePath: String = NexusParallelDownloader.download(
                modelPath: preset.basePath,
                destinationName: "\(preset.id)-base-\(baseName)",
                concurrency: 3
            ) { snapshot in
                Task { @MainActor in
                    self.languageDownload = snapshot
                    self.refreshDownloadProgress(preset)
                }
            }

            async let projectionPath: String = NexusParallelDownloader.download(
                modelPath: preset.projectionPath,
                destinationName: "\(preset.id)-vision-\(projectionName)",
                concurrency: 3
            ) { snapshot in
                Task { @MainActor in
                    self.visionDownload = snapshot
                    self.refreshDownloadProgress(preset)
                }
            }

            let (base, projection) = try await (basePath, projectionPath)
            installs[preset.id] = .init(baseLocalPath: base, projectionLocalPath: projection)
            persistInstalls()
            progress = 1
            status = "Downloaded • \(preset.name) • weights stay off RAM until Load"
        } catch {
            lastError = error.localizedDescription
            status = "Multimodal download interrupted • completed chunks are kept for resume"
            refreshDownloadProgress(preset)
        }
    }

    private func refreshDownloadProgress(_ preset: NexusMultimodalPreset) {
        let total = languageDownload.totalBytes + visionDownload.totalBytes
        let done = languageDownload.downloadedBytes + visionDownload.downloadedBytes
        if total > 0 { progress = min(0.99, Double(done) / Double(total)) }
        status = "Downloading \(preset.name) • \(combinedDownloadDetail)"
    }

    func load(_ preset: NexusMultimodalPreset) async {
        guard !busy else { return }
        guard isSafeToLoad(preset) else {
            status = "\(preset.name) is installed but exceeds this device's conservative runtime-memory budget."
            lastError = "Keep it downloaded or use the smaller multimodal model."
            return
        }
        if !isDownloaded(preset) { await download(preset) }
        guard let install = installs[preset.id], !busy else { return }

        busy = true
        lastError = ""
        progress = max(progress, 0.05)
        status = "Loading \(preset.name)…"
        defer { busy = false }
        do {
            releaseRuntime(reason: nil)
            let loaded = try await Model.load(modelPath: install.baseLocalPath,
                                              useGpu: true,
                                              projectionModelPath: install.projectionLocalPath)
            let ctx = min(loaded.maxCtx, recommendedContext(for: preset))
            let session = try Chat(model: loaded,
                                   systemPrompt: "You are NEXUS Multimodal, a private on-device file analyst. Describe only what is supported by the supplied file content or preview. Separate observation from inference. If a preview is incomplete, say so.",
                                   contextSize: ctx,
                                   threadCount: nil)
            model = loaded
            chat = session
            activePresetID = preset.id
            selectedPresetID = preset.id
            progress = 1
            status = "Loaded • \(preset.name) • \(ctx)-token adaptive context"
        } catch {
            lastError = error.localizedDescription
            status = "Could not load \(preset.name)"
            releaseRuntime(reason: nil)
        }
    }

    func unload() {
        releaseRuntime(reason: "Multimodal runtime unloaded • RAM released")
        progress = 0
    }

    func removeWeights(_ preset: NexusMultimodalPreset) {
        if activePresetID == preset.id { releaseRuntime(reason: nil) }
        guard let install = installs[preset.id] else { return }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: install.baseLocalPath) { try fm.removeItem(atPath: install.baseLocalPath) }
            if fm.fileExists(atPath: install.projectionLocalPath) { try fm.removeItem(atPath: install.projectionLocalPath) }
            installs.removeValue(forKey: preset.id)
            persistInstalls()
            languageDownload = .zero
            visionDownload = .zero
            progress = 0
            status = "Removed \(preset.name) weights from device storage"
        } catch {
            lastError = error.localizedDescription
            status = "Could not remove multimodal weights"
        }
    }

    func analyzeFiles(_ urls: [URL], question: String) async {
        guard !urls.isEmpty else { return }
        guard let chat else {
            status = "Load a multimodal model before analyzing files."
            return
        }
        guard !busy else { return }
        busy = true
        lastError = ""
        progress = 0
        results.removeAll(keepingCapacity: true)
        defer { busy = false }

        let cleanQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = cleanQuestion.isEmpty ? "Analyze this file comprehensively. Summarize its content, important details, patterns, and uncertainty." : cleanQuestion

        for (index, url) in urls.enumerated() {
            status = "Analyzing \(url.lastPathComponent) • \(index + 1)/\(urls.count)"
            progress = Double(index) / Double(max(urls.count, 1))
            do {
                try await chat.resetHistory()
                let result = try await analyzeOne(url: url, question: instruction, chat: chat)
                results.append(result)
            } catch {
                results.append(.init(fileName: url.lastPathComponent, kind: "Error", answer: error.localizedDescription))
            }
            progress = Double(index + 1) / Double(max(urls.count, 1))
        }
        status = "Finished • \(results.count) file result\(results.count == 1 ? "" : "s") • processed sequentially to cap peak memory"
    }

    private func analyzeOne(url: URL, question: String, chat: Chat) async throws -> NexusFileAnalysisResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["png","jpg","jpeg","heic","heif","webp","gif","bmp","tif","tiff"]
        let textExts: Set<String> = ["txt","md","markdown","json","jsonl","csv","tsv","html","htm","xml","yaml","yml","toml","ini","log","swift","py","js","ts","tsx","jsx","java","kt","kts","c","h","cpp","hpp","m","mm","css","scss","sql","sh","zsh","fish","rs","go","rb","php","r","dart"]

        if imageExts.contains(ext) {
            let prepared = try Self.downsampleImage(url, maxPixel: 1600)
            defer { try? FileManager.default.removeItem(at: prepared) }
            let prompt = Prompt([
                Prompt.text("FILE: \(url.lastPathComponent)\nREQUEST: \(question)\nInspect the image carefully. Mention visible text, layout, objects, relationships, anomalies and uncertainty when relevant."),
                Prompt.image(prepared.path)
            ])
            let output = try await chat.ask(prompt).completed()
            return .init(fileName: url.lastPathComponent, kind: "Image • true vision analysis", answer: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if ext == "pdf" { return try await analyzePDF(url: url, question: question, chat: chat) }

        if textExts.contains(ext) || Self.isLikelyText(url) {
            let text = try Self.readTextCapped(url, maxBytes: 1_200_000, maxCharacters: 48_000)
            let prompt = "FILE: \(url.lastPathComponent)\nREQUEST: \(question)\n\nEXTRACTED CONTENT (may be capped for memory):\n\(text)\n\nAnalyze the file from the extracted content. Clearly note if truncation can affect conclusions."
            let output = try await chat.ask(prompt).completed()
            return .init(fileName: url.lastPathComponent, kind: "Text / structured file", answer: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let preview = try? await Self.quickLookPreview(url, maxPixel: 1500) {
            defer { try? FileManager.default.removeItem(at: preview) }
            let metadata = Self.metadataSummary(url)
            let prompt = Prompt([
                Prompt.text("FILE: \(url.lastPathComponent)\nREQUEST: \(question)\nMETADATA: \(metadata)\nThis format is being analyzed from an iOS-generated visual preview rather than full binary decoding. Be explicit about that limitation."),
                Prompt.image(preview.path)
            ])
            let output = try await chat.ask(prompt).completed()
            return .init(fileName: url.lastPathComponent, kind: "Best-effort file preview", answer: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let metadata = Self.metadataSummary(url)
        let output = try await chat.ask("FILE: \(url.lastPathComponent)\nREQUEST: \(question)\nOnly metadata is safely available for this binary format: \(metadata)\nExplain what can and cannot be concluded without inventing file content.").completed()
        return .init(fileName: url.lastPathComponent, kind: "Metadata-only fallback", answer: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func analyzePDF(url: URL, question: String, chat: Chat) async throws -> NexusFileAnalysisResult {
        guard let pdf = PDFDocument(url: url) else {
            throw NSError(domain: "NEXUS.Multimodal", code: 20, userInfo: [NSLocalizedDescriptionKey: "Could not open PDF."])
        }
        var extracted = ""
        let textPageLimit = min(pdf.pageCount, 24)
        for i in 0..<textPageLimit {
            if let pageText = pdf.page(at: i)?.string, !pageText.isEmpty {
                extracted += "\n--- PAGE \(i + 1) ---\n" + pageText
                if extracted.count >= 42_000 { break }
            }
        }
        extracted = String(extracted.prefix(42_000))

        var parts: [PromptPart] = [
            Prompt.text("FILE: \(url.lastPathComponent)\nREQUEST: \(question)\nPDF PAGES: \(pdf.pageCount)\nEXTRACTED TEXT (capped):\n\(extracted)\n\nI may also provide up to two rendered page previews. Analyze both text and visuals; state when later pages were not inspected.")
        ]
        var temps: [URL] = []
        for index in 0..<min(pdf.pageCount, 2) {
            if let page = pdf.page(at: index), let imageURL = try? Self.renderPDFPage(page, index: index, maxPixel: 1350) {
                temps.append(imageURL)
                parts.append(Prompt.image(imageURL.path))
            }
        }
        defer { temps.forEach { try? FileManager.default.removeItem(at: $0) } }
        let output = try await chat.ask(Prompt(parts)).completed()
        return .init(fileName: url.lastPathComponent, kind: "PDF • text + visual page analysis", answer: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func recommendedContext(for preset: NexusMultimodalPreset) -> UInt32 {
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        if ramGB <= 4.5 { return 1536 }
        if ramGB <= 6.5 { return preset.estimatedBytes > 2_000_000_000 ? 1536 : 2048 }
        if ramGB <= 8.5 { return preset.estimatedBytes > 2_000_000_000 ? 2048 : 3072 }
        return 4096
    }

    private func isSafeToLoad(_ preset: NexusMultimodalPreset) -> Bool {
        let runtimeEstimate = Double(preset.estimatedBytes) * 1.24 + 520_000_000
        return runtimeEstimate < Double(ProcessInfo.processInfo.physicalMemory) * 0.72
    }

    private func releaseRuntime(reason: String?) {
        chat?.stopGeneration(); chat = nil; model = nil; activePresetID = ""
        if let reason { status = reason }
    }

    private func persistInstalls() {
        if let data = try? JSONEncoder().encode(installs) { UserDefaults.standard.set(data, forKey: installKey) }
    }

    private static func readTextCapped(_ url: URL, maxBytes: Int, maxCharacters: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes) ?? Data()
        let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        if decoded.isEmpty { throw NSError(domain: "NEXUS.Multimodal", code: 21, userInfo: [NSLocalizedDescriptionKey: "No readable text was found in this file."]) }
        return String(decoded.prefix(maxCharacters))
    }

    private static func isLikelyText(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) || type.conforms(to: .xml)
    }

    private static func downsampleImage(_ url: URL, maxPixel: Int) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw NSError(domain: "NEXUS.Multimodal", code: 22, userInfo: [NSLocalizedDescriptionKey: "Could not decode image."]) }
        let options: [CFString:Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.82) else {
            throw NSError(domain: "NEXUS.Multimodal", code: 23, userInfo: [NSLocalizedDescriptionKey: "Could not prepare image for local vision model."])
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-mm-\(UUID().uuidString).jpg")
        try data.write(to: out, options: .atomic)
        return out
    }

    private static func renderPDFPage(_ page: PDFPage, index: Int, maxPixel: Int) throws -> URL {
        let bounds = page.bounds(for: .mediaBox)
        let ratio = max(bounds.width / max(bounds.height, 1), 0.2)
        let px = CGFloat(maxPixel)
        let size: CGSize = ratio >= 1 ? .init(width: px, height: px / ratio) : .init(width: px * ratio, height: px)
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let data = image.jpegData(compressionQuality: 0.78) else { throw NSError(domain: "NEXUS.Multimodal", code: 24, userInfo: [NSLocalizedDescriptionKey: "Could not render PDF page preview."]) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-pdf-\(index)-\(UUID().uuidString).jpg")
        try data.write(to: out, options: .atomic)
        return out
    }

    private static func quickLookPreview(_ url: URL, maxPixel: Int) async throws -> URL {
        let scale = await MainActor.run { UIScreen.main.scale }
        let px = CGFloat(maxPixel)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: px, height: px), scale: min(scale, 2), representationTypes: .all)
        let representation: QLThumbnailRepresentation = try await withCheckedThrowingContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
                if let rep { continuation.resume(returning: rep) }
                else { continuation.resume(throwing: error ?? NSError(domain: "NEXUS.Multimodal", code: 25, userInfo: [NSLocalizedDescriptionKey: "No system preview is available for this file type."])) }
            }
        }
        guard let data = representation.uiImage.jpegData(compressionQuality: 0.80) else { throw NSError(domain: "NEXUS.Multimodal", code: 26, userInfo: [NSLocalizedDescriptionKey: "Could not encode system file preview."]) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-preview-\(UUID().uuidString).jpg")
        try data.write(to: out, options: .atomic)
        return out
    }

    private static func metadataSummary(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .creationDateKey, .contentModificationDateKey])
        let bytes = values?.fileSize ?? 0
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let type = values?.contentType?.identifier ?? "unknown"
        let modified = values?.contentModificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"
        return "type=\(type); size=\(size); modified=\(modified)"
    }
}

struct NexusAnyFilePicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NexusAnyFilePicker
        init(parent: NexusAnyFilePicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { parent.onPick(urls) }
    }
}

struct MultimodalLabV8View: View {
    @ObservedObject private var store = NexusMultimodalStore.shared
    @State private var selectedFiles: [URL] = []
    @State private var showPicker = false
    @State private var question = ""

    var body: some View {
        List {
            Section {
                Text("True local vision for images and rendered pages, full text extraction for common text/code files, PDF text + page previews, and best-effort iOS visual previews for other formats. Unsupported opaque binaries fall back to metadata instead of fabricated content.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.busy || store.progress > 0 {
                    ProgressView(value: store.progress) { Text(store.status).font(.caption) }
                    if !store.combinedDownloadDetail.isEmpty { Text(store.combinedDownloadDetail).font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
                } else { Text(store.status).font(.caption).foregroundStyle(.secondary) }
                if !store.lastError.isEmpty { Text(store.lastError).font(.caption).foregroundStyle(.red) }
            }

            Section("Multimodal models") {
                ForEach(NexusMultimodalStore.presets) { preset in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.headline)
                                Text("\(preset.approximateDownload) • \(preset.detail)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.activePresetID == preset.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            else if store.isDownloaded(preset) { Image(systemName: "internaldrive.fill").foregroundStyle(.secondary) }
                        }
                        if store.downloadingPresetID == preset.id {
                            if store.languageDownload.totalBytes > 0 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Language weights").font(.caption).bold()
                                    ProgressView(value: store.languageDownload.fraction)
                                    Text(store.languageDownload.detailText).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            if store.visionDownload.totalBytes > 0 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Vision projector").font(.caption).bold()
                                    ProgressView(value: store.visionDownload.fraction)
                                    Text(store.visionDownload.detailText).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack {
                            if !store.isDownloaded(preset) { Button("Download") { Task { await store.download(preset) } }.buttonStyle(.bordered).disabled(store.busy) }
                            Button(store.activePresetID == preset.id ? "Reload" : "Load") { Task { await store.load(preset) } }.buttonStyle(.borderedProminent).disabled(store.busy)
                            if store.isDownloaded(preset) { Button(role: .destructive) { store.removeWeights(preset) } label: { Text("Remove weights") }.buttonStyle(.bordered) }
                        }
                    }.padding(.vertical, 3)
                }
                if !store.activePresetID.isEmpty { Button("Unload model and free RAM") { store.unload() } }
            }

            Section("Files") {
                Button { showPicker = true } label: { Label(selectedFiles.isEmpty ? "Choose files" : "Add / replace files", systemImage: "paperclip") }
                ForEach(selectedFiles, id: \.absoluteString) { url in HStack { Image(systemName: "doc"); Text(url.lastPathComponent).lineLimit(1); Spacer() } }
                TextField("What should NEXUS analyze? (optional)", text: $question, axis: .vertical).lineLimit(2...5)
                Button { Task { await store.analyzeFiles(selectedFiles, question: question) } } label: { Label("Analyze sequentially", systemImage: "sparkles") }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedFiles.isEmpty || store.activePresetID.isEmpty || store.busy)
            }

            if !store.results.isEmpty {
                Section("Results") {
                    ForEach(store.results) { result in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.fileName).font(.headline)
                            Text(result.kind).font(.caption).foregroundStyle(.cyan)
                            Text(result.answer).textSelection(.enabled)
                        }.padding(.vertical, 5)
                    }
                }
            }

            Section("Download + memory strategy") {
                Text("Each multimodal component uses resumable HTTP byte ranges. Language weights and the vision projector download at the same time, each with up to three chunk lanes, so a model can use up to six concurrent network lanes when the server supports ranges. Progress shows percentage, bytes, throughput, ETA and active lanes. Inference still keeps only one vision model resident, downsamples visuals, caps text/PDF context and processes files sequentially to control RAM and heat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Multimodal Files")
        .sheet(isPresented: $showPicker) {
            NexusAnyFilePicker { urls in selectedFiles = urls; showPicker = false }
        }
    }
}
