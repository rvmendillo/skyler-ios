import Foundation
import SwiftUI

struct NexusPreanalysisEntry: Codable, Hashable, Identifiable {
    let fileID: String
    let fingerprint: String
    let fileName: String
    let kind: String
    let answer: String
    let analyzedAt: Date
    let needsVisionUpgrade: Bool?

    var id: String { fileID }
}

@MainActor
final class NexusPreanalysisStore: ObservableObject {
    static let shared = NexusPreanalysisStore()

    @Published private(set) var entries: [String:NexusPreanalysisEntry] = [:]
    @Published private(set) var busy = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status = "Ready"
    @Published private(set) var currentFile = ""

    private let defaultsKey = "nexus.preanalysis.entries.v1"
    private var rerunRequested = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String:NexusPreanalysisEntry].self, from: data) {
            entries = decoded
        }
    }

    func entry(for item: NexusV8FileItem) -> NexusPreanalysisEntry? {
        guard let entry = entries[item.id.uuidString], entry.fingerprint == fingerprint(item) else { return nil }
        return entry
    }

    func isCurrent(_ item: NexusV8FileItem) -> Bool {
        guard let entry = entry(for: item) else { return false }
        if entry.needsVisionUpgrade == true && NexusModelResidencyCoordinator.shared.hasDownloadedVisionModel() {
            return false
        }
        return true
    }

    func isFullyAnalyzed(_ item: NexusV8FileItem) -> Bool {
        guard let entry = entry(for: item) else { return false }
        return entry.needsVisionUpgrade != true
    }

    func prune(to files: [NexusV8FileItem]) {
        let valid = Set(files.map { $0.id.uuidString })
        entries = entries.filter { valid.contains($0.key) }
        persist()
    }

    func analyzePending(_ requestedFiles: [NexusV8FileItem], force: Bool = false) async {
        if busy {
            rerunRequested = true
            return
        }

        busy = true
        defer {
            busy = false
            currentFile = ""
        }

        var files = requestedFiles
        var forceThisPass = force

        repeat {
            rerunRequested = false
            let libraryFiles = NexusV8FileLibrary.shared.files
            prune(to: libraryFiles)

            if files.isEmpty { files = libraryFiles }
            guard !files.isEmpty else {
                status = "No imported files yet"
                progress = 0
                return
            }

            let pending = files.filter { forceThisPass || !isCurrent($0) }
            forceThisPass = false

            guard !pending.isEmpty else {
                let full = files.filter { isFullyAnalyzed($0) }.count
                status = full == files.count
                    ? "All \(files.count) imported file\(files.count == 1 ? " is" : "s are") fully analyzed"
                    : "Baseline analysis ready • install a vision model to upgrade visual media"
                progress = 1
                if rerunRequested { files = NexusV8FileLibrary.shared.files }
                continue
            }

            progress = 0
            let residency = NexusModelResidencyCoordinator.shared
            let vision = NexusMultimodalStore.shared
            let question = "Analyze this file comprehensively for the NEXUS analyzed library. Summarize its purpose and content, extract important facts, visible text and structure, identify patterns or anomalies, and clearly separate observation from inference. Mention limitations when the file or preview is incomplete."

            var visionResults: [UUID:NexusFileAnalysisResult] = [:]
            if residency.hasDownloadedVisionModel() && !vision.busy {
                status = "Preparing multimodal analysis for \(pending.count) file\(pending.count == 1 ? "" : "s")…"
                if let results = await residency.withVisionRuntime({
                    await self.analyzeVisionSafely(items: pending, vision: vision, question: question)
                }) {
                    visionResults = results
                }
            }

            for (index, item) in pending.enumerated() {
                currentFile = item.name
                status = "Saving analysis • \(index + 1)/\(pending.count)"

                if let result = visionResults[item.id],
                   result.kind != "Error",
                   !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    entries[item.id.uuidString] = NexusPreanalysisEntry(
                        fileID: item.id.uuidString,
                        fingerprint: fingerprint(item),
                        fileName: item.name,
                        kind: result.kind,
                        answer: result.answer,
                        analyzedAt: Date(),
                        needsVisionUpgrade: false
                    )
                } else {
                    entries[item.id.uuidString] = await baselineEntry(for: item, question: question)
                }

                persist()
                progress = Double(index + 1) / Double(max(1, pending.count))
                await Task.yield()
            }

            let allFiles = NexusV8FileLibrary.shared.files
            let fullCount = allFiles.filter { isFullyAnalyzed($0) }.count
            let baselineCount = allFiles.filter { entry(for: $0) != nil }.count
            if fullCount == allFiles.count {
                status = "Analyzed library ready • \(fullCount)/\(allFiles.count) files fully analyzed"
            } else if baselineCount == allFiles.count {
                status = "Library baseline ready • \(fullCount) full analyses, \(baselineCount - fullCount) awaiting vision upgrade"
            } else {
                status = "Analyzed \(baselineCount)/\(allFiles.count) imported files"
            }

            if rerunRequested { files = allFiles }
        } while rerunRequested
    }

    func analyze(_ item: NexusV8FileItem, force: Bool = true) async {
        if force {
            entries.removeValue(forKey: item.id.uuidString)
            persist()
        }
        await analyzePending([item], force: force)
    }

    private func analyzeVisionSafely(
        items: [NexusV8FileItem],
        vision: NexusMultimodalStore,
        question: String
    ) async -> [UUID:NexusFileAnalysisResult] {
        var output: [UUID:NexusFileAnalysisResult] = [:]
        output.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            currentFile = item.name
            status = "Multimodal analysis • \(index + 1)/\(items.count) • \(item.name)"
            progress = 0.72 * Double(index) / Double(max(1, items.count))

            if NexusMediaTypes.isVideo(item.url) {
                do {
                    let contactSheet = try await NexusVideoFrameExtractor.contactSheet(for: item.url)
                    defer { try? FileManager.default.removeItem(at: contactSheet) }
                    let videoQuestion = """
                    These are representative frames sampled across the actual video \(item.name). Analyze what visibly happens across the sampled timeline: scenes, people/objects, activities, locations, text on screen, transitions and recurring patterns. Distinguish direct observation from inference. State clearly that audio and unsampled moments were not inspected.
                    """
                    await vision.analyzeFiles([contactSheet], question: videoQuestion)
                    if let result = vision.results.first {
                        output[item.id] = NexusFileAnalysisResult(
                            fileName: item.name,
                            kind: "Video • representative frame analysis",
                            answer: result.answer
                        )
                    }
                } catch {
                    output[item.id] = NexusFileAnalysisResult(fileName: item.name, kind: "Error", answer: error.localizedDescription)
                }
            } else {
                await vision.analyzeFiles([item.url], question: question)
                if let result = vision.results.first {
                    output[item.id] = NexusFileAnalysisResult(
                        fileName: item.name,
                        kind: result.kind,
                        answer: result.answer
                    )
                }
            }

            // One file at a time keeps decoded images, PDF page renders and model output bounded.
            await Task.yield()
        }

        return output
    }

    private func baselineEntry(for item: NexusV8FileItem, question: String) async -> NexusPreanalysisEntry {
        let ext = item.ext
        let definitelyVisual = NexusV8FileSupport.imageExtensions.contains(ext) || NexusMediaTypes.isVideo(item.url)
        let mayNeedVision = definitelyVisual || ext == "pdf" || !NexusV8FileSupport.textExtensions.contains(ext)

        var extracted = ""
        var kind = "Baseline local analysis"
        do {
            if ext == "pdf" {
                extracted = try NexusV8FileSupport.pdfText(item.url, maxPages: 40, maxCharacters: 42_000)
                kind = "PDF text baseline • vision upgrade pending"
            } else if NexusV8FileSupport.textExtensions.contains(ext) {
                extracted = try NexusV8FileSupport.readableText(item.url, maxBytes: 1_200_000, maxCharacters: 42_000)
                kind = "Text / structured file • local analysis"
            } else if NexusMediaTypes.isVideo(item.url) {
                extracted = NexusV8FileSupport.metadata(item)
                kind = "Video metadata baseline • frame analysis pending"
            } else if NexusV8FileSupport.imageExtensions.contains(ext) {
                extracted = NexusV8FileSupport.metadata(item)
                kind = "Image metadata baseline • pixel analysis pending"
            } else {
                extracted = NexusV8FileSupport.metadata(item)
                kind = "Metadata baseline • vision upgrade pending"
            }
        } catch {
            extracted = "\(NexusV8FileSupport.metadata(item))\nExtraction error: \(error.localizedDescription)"
        }

        var answer = ""
        if definitelyVisual {
            let mediaLabel = NexusMediaTypes.isVideo(item.url) ? "video frames" : "image pixels"
            answer = "This media file is safely stored and queued. Full visual understanding of the actual \(mediaLabel) needs an installed vision model. NEXUS retained its metadata and will automatically upgrade this entry when a downloaded vision model is available.\n\n\(NexusV8FileSupport.metadata(item))"
        } else {
            let prompt = """
            Analyze the supplied file evidence for the NEXUS analyzed library. Summarize purpose/content, important facts, structure, patterns or anomalies, and uncertainty. Do not invent information that is not present.

            FILE: \(item.name)
            REQUEST: \(question)
            EVIDENCE:
            \(String(extracted.prefix(42_000)))
            """
            if let generated = await NexusIntelligenceEngine.respond(question: prompt, context: "Private local file analysis"),
               !generated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                answer = generated.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let preview = String(extracted.prefix(5_500))
                answer = "NEXUS extracted this file successfully, but no language/vision runtime was available for a richer synthesis. Extracted evidence:\n\n\(preview)"
            }
        }

        return NexusPreanalysisEntry(
            fileID: item.id.uuidString,
            fingerprint: fingerprint(item),
            fileName: item.name,
            kind: kind,
            answer: answer,
            analyzedAt: Date(),
            needsVisionUpgrade: mayNeedVision
        )
    }

    private func fingerprint(_ item: NexusV8FileItem) -> String {
        let values = try? item.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = String(values?.fileSize ?? Int(item.size))
        return "\(item.path)|\(fileSize)|\(modified)"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

struct NexusAnalyzedLibraryView: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var store = NexusPreanalysisStore.shared
    @ObservedObject private var vision = NexusMultimodalStore.shared
    @ObservedObject private var residency = NexusModelResidencyCoordinator.shared

    var body: some View {
        List {
            Section {
                Text("Imported files are analyzed here automatically. Photos are analyzed from their pixels. Videos are analyzed from representative frames sampled across the real video. NEXUS processes one file at a time and falls back safely instead of crashing when a heavyweight model is unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Label("Fully analyzed", systemImage: "sparkles.rectangle.stack.fill")
                    Spacer()
                    Text("\(fullCount) / \(library.files.count)")
                        .monospacedDigit()
                        .foregroundStyle(fullCount == library.files.count && !library.files.isEmpty ? Color.green : Color.secondary)
                }

                let baselineCount = library.files.filter { store.entry(for: $0) != nil }.count
                if baselineCount != fullCount {
                    LabeledContent("Baseline / queued", value: "\(baselineCount - fullCount)")
                        .font(.caption)
                }

                if store.busy {
                    ProgressView(value: store.progress) {
                        Text(store.status).font(.caption)
                    }
                    if !store.currentFile.isEmpty {
                        Text(store.currentFile).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }

                if !residency.hasDownloadedVisionModel() {
                    NavigationLink("Install a vision model for full multimodal analysis") { SharedVisionModelsEnhancedView() }
                }

                NavigationLink("Import actual photos & videos") { NexusMediaImportView() }

                Button {
                    Task { await store.analyzePending(library.files) }
                } label: {
                    Label("Analyze new or changed files", systemImage: "wand.and.stars")
                }
                .disabled(store.busy || library.files.isEmpty)

                Button {
                    Task { await store.analyzePending(library.files, force: true) }
                } label: {
                    Label("Reanalyze entire library", systemImage: "arrow.clockwise")
                }
                .disabled(store.busy || library.files.isEmpty)
            }

            Section("Analyzed library") {
                if library.files.isEmpty {
                    ContentUnavailableView(
                        "No imported files",
                        systemImage: "folder",
                        description: Text("Import files, Meta media, or Apple Photos once. They will appear here automatically; no second picker is required.")
                    )
                }

                ForEach(library.files) { item in
                    NavigationLink {
                        NexusAnalyzedFileDetailView(item: item)
                    } label: {
                        HStack(spacing: 11) {
                            let entry = store.entry(for: item)
                            let full = store.isFullyAnalyzed(item)
                            Image(systemName: full ? "checkmark.seal.fill" : (entry == nil ? "clock.badge.exclamationmark" : "eye.trianglebadge.exclamationmark"))
                                .foregroundStyle(full ? Color.green : Color.orange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.headline).lineLimit(1)
                                if let entry {
                                    Text(entry.kind).font(.caption).foregroundStyle(full ? Color.cyan : Color.orange).lineLimit(1)
                                    Text(entry.answer.replacingOccurrences(of: "\n", with: " "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                } else {
                                    Text("Pending automatic analysis")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Analyzed Library")
        .task {
            await store.analyzePending(library.files)
        }
        .onChange(of: library.files.count) { _, _ in
            Task { await store.analyzePending(library.files) }
        }
        .onChange(of: vision.status) { _, _ in
            if residency.hasDownloadedVisionModel() && !store.busy {
                Task { await store.analyzePending(library.files) }
            }
        }
    }

    private var fullCount: Int {
        library.files.reduce(0) { $0 + (store.isFullyAnalyzed($1) ? 1 : 0) }
    }
}

struct NexusAnalyzedFileDetailView: View {
    let item: NexusV8FileItem
    @ObservedObject private var store = NexusPreanalysisStore.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.headline)
                    Text("\(item.kindLabel) • \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let entry = store.entry(for: item) {
                Section(entry.needsVisionUpgrade == true ? "Current baseline" : "Multimodal analysis") {
                    Text(entry.kind).font(.caption).foregroundStyle(entry.needsVisionUpgrade == true ? Color.orange : Color.cyan)
                    Text(entry.answer).textSelection(.enabled)
                    Text("Analyzed \(entry.analyzedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if entry.needsVisionUpgrade == true {
                        Text("This entry will automatically upgrade when an installed vision model is available.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Analysis pending",
                        systemImage: "sparkles",
                        description: Text("NEXUS will analyze this imported file without asking you to select it again.")
                    )
                }
            }

            Section {
                Button {
                    Task { await store.analyze(item, force: true) }
                } label: {
                    Label("Reanalyze this file", systemImage: "arrow.clockwise")
                }
                .disabled(store.busy)
            }
        }
        .navigationTitle("File Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !store.isCurrent(item) {
                await store.analyze(item, force: false)
            }
        }
    }
}
