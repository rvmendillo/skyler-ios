import Foundation
import SwiftUI

struct NexusPreanalysisEntry: Codable, Hashable, Identifiable {
    let fileID: String
    let fingerprint: String
    let fileName: String
    let kind: String
    let answer: String
    let analyzedAt: Date

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
        entry(for: item) != nil
    }

    func prune(to files: [NexusV8FileItem]) {
        let valid = Set(files.map { $0.id.uuidString })
        entries = entries.filter { valid.contains($0.key) }
        persist()
    }

    func analyzePending(_ files: [NexusV8FileItem], force: Bool = false) async {
        guard !busy else { return }
        prune(to: files)
        guard !files.isEmpty else {
            status = "No imported files yet"
            progress = 0
            return
        }

        let pending = files.filter { force || !isCurrent($0) }
        guard !pending.isEmpty else {
            status = "All \(files.count) imported file\(files.count == 1 ? " is" : "s are") already analyzed"
            progress = 1
            return
        }

        let vision = NexusMultimodalStore.shared
        if vision.activePresetID.isEmpty {
            if vision.isDownloaded(vision.selectedPreset) {
                status = "Loading multimodal model…"
                await vision.load(vision.selectedPreset)
            } else {
                status = "Vision model required • install one once, then NEXUS will analyze every imported file automatically"
                progress = 0
                return
            }
        }

        guard !vision.activePresetID.isEmpty else {
            status = vision.lastError.isEmpty ? "Could not load the multimodal model" : vision.lastError
            progress = 0
            return
        }

        busy = true
        progress = 0
        defer {
            busy = false
            currentFile = ""
        }

        for (index, item) in pending.enumerated() {
            currentFile = item.name
            status = "Analyzing \(item.name) • \(index + 1)/\(pending.count)"
            progress = Double(index) / Double(max(1, pending.count))

            await vision.analyzeFiles(
                [item.url],
                question: "Analyze this file comprehensively for the NEXUS analyzed library. Summarize its purpose and content, extract important facts, visible text and structure, identify patterns or anomalies, and clearly separate observation from inference. Mention limitations when the file or preview is incomplete."
            )

            let result = vision.results.first ?? NexusFileAnalysisResult(
                fileName: item.name,
                kind: "Analysis unavailable",
                answer: vision.lastError.isEmpty ? "NEXUS could not produce an analysis for this file." : vision.lastError
            )

            entries[item.id.uuidString] = NexusPreanalysisEntry(
                fileID: item.id.uuidString,
                fingerprint: fingerprint(item),
                fileName: item.name,
                kind: result.kind,
                answer: result.answer,
                analyzedAt: Date()
            )
            persist()
            progress = Double(index + 1) / Double(max(1, pending.count))
        }

        status = "Analyzed library ready • \(entries.count)/\(files.count) files current"
    }

    func analyze(_ item: NexusV8FileItem, force: Bool = true) async {
        if force {
            entries.removeValue(forKey: item.id.uuidString)
            persist()
        }
        await analyzePending(NexusV8FileLibrary.shared.files)
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

    var body: some View {
        List {
            Section {
                Text("Every file already imported into NEXUS is analyzed here as a library. No per-file picker is needed. NEXUS caches completed analysis and automatically skips unchanged files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Label("Analyzed", systemImage: "sparkles.rectangle.stack.fill")
                    Spacer()
                    Text("\(currentCount) / \(library.files.count)")
                        .monospacedDigit()
                        .foregroundStyle(currentCount == library.files.count && !library.files.isEmpty ? Color.green : Color.secondary)
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

                if vision.activePresetID.isEmpty && !vision.isDownloaded(vision.selectedPreset) {
                    NavigationLink("Install multimodal model once") { MultimodalLabV8View() }
                }

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
                        description: Text("Import files once from the Files page. They will appear here automatically for cached multimodal analysis.")
                    )
                }

                ForEach(library.files) { item in
                    NavigationLink {
                        NexusAnalyzedFileDetailView(item: item)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: store.isCurrent(item) ? "checkmark.seal.fill" : "clock.badge.exclamationmark")
                                .foregroundStyle(store.isCurrent(item) ? Color.green : Color.orange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.headline).lineLimit(1)
                                if let entry = store.entry(for: item) {
                                    Text(entry.kind).font(.caption).foregroundStyle(.cyan).lineLimit(1)
                                    Text(entry.answer.replacingOccurrences(of: "\n", with: " "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                } else {
                                    Text("Pending automatic multimodal analysis")
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
    }

    private var currentCount: Int {
        library.files.reduce(0) { $0 + (store.isCurrent($1) ? 1 : 0) }
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
                Section("Multimodal analysis") {
                    Text(entry.kind).font(.caption).foregroundStyle(.cyan)
                    Text(entry.answer).textSelection(.enabled)
                    Text("Analyzed \(entry.analyzedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
