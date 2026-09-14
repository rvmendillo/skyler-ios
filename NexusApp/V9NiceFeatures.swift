import Foundation
import SwiftUI
import UIKit
import CryptoKit

@MainActor
final class NexusNiceFeaturesStore: ObservableObject {
    static let shared = NexusNiceFeaturesStore()

    @Published var favoriteFileIDs: Set<String> { didSet { save() } }
    @Published var compactLibraryRows: Bool { didSet { save() } }
    @Published var showOnlyFavorites: Bool = false
    @Published var preferredFileType: String = "All"
    @Published var sortMode: SortMode = .newest
    @Published var searchText: String = ""

    enum SortMode: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case oldest = "Oldest"
        case name = "Name"
        case size = "Size"
        var id: String { rawValue }
    }

    private let defaults = UserDefaults.standard
    private init() {
        favoriteFileIDs = Set(defaults.stringArray(forKey: "nexus.nice.favoriteFileIDs") ?? [])
        compactLibraryRows = defaults.object(forKey: "nexus.nice.compactRows") as? Bool ?? false
    }

    func toggleFavorite(_ file: NexusV8FileItem) {
        let id = file.id.uuidString
        if favoriteFileIDs.contains(id) { favoriteFileIDs.remove(id) }
        else { favoriteFileIDs.insert(id) }
    }

    func isFavorite(_ file: NexusV8FileItem) -> Bool { favoriteFileIDs.contains(file.id.uuidString) }

    private func save() {
        defaults.set(Array(favoriteFileIDs), forKey: "nexus.nice.favoriteFileIDs")
        defaults.set(compactLibraryRows, forKey: "nexus.nice.compactRows")
    }
}

struct NexusNiceFeaturesView: View {
    @EnvironmentObject private var model: NexusModel
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @ObservedObject private var prefs = NexusNiceFeaturesStore.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var captureStatus = ""

    var body: some View {
        List {
            Section("Everyday") {
                NavigationLink { NexusSmartLibraryView() } label: { Label("Smart Library", systemImage: "folder.badge.gearshape") }
                Button { captureClipboard() } label: { Label("Capture Clipboard", systemImage: "doc.on.clipboard") }
                if !captureStatus.isEmpty { Text(captureStatus).font(.caption).foregroundStyle(.secondary) }
                NavigationLink { AskV9View() } label: { Label("Quick Ask", systemImage: "sparkles") }
                NavigationLink { NexusV9GlobalSearchView() } label: { Label("Search Everything", systemImage: "magnifyingglass") }
            }

            Section("Library helpers") {
                NavigationLink { NexusDuplicateFilesView() } label: { Label("Find Duplicate Files", systemImage: "doc.on.doc") }
                NavigationLink { NexusDataHealthView() } label: { Label("Data Health", systemImage: "checkmark.shield") }
                Toggle("Compact library rows", isOn: $prefs.compactLibraryRows)
                HStack { Label("Favorites", systemImage: "star.fill"); Spacer(); Text("\(prefs.favoriteFileIDs.count)").foregroundStyle(.secondary) }
                HStack { Label("Local files", systemImage: "externaldrive.fill"); Spacer(); Text("\(library.files.count)").foregroundStyle(.secondary) }
            }

            Section("Maintenance") {
                Button {
                    Task { await intelligence.index(records: model.records, files: library.files, force: true) }
                } label: { Label("Rebuild Search Index", systemImage: "arrow.triangle.2.circlepath") }
                NavigationLink { NexusV9StorageView() } label: { Label("Storage Manager", systemImage: "internaldrive") }
                NavigationLink { NexusV9PerformanceView() } label: { Label("Performance & Diagnostics", systemImage: "gauge.with.dots.needle.67percent") }
                NavigationLink { NexusV9SecurityView() } label: { Label("Privacy & Security", systemImage: "lock.shield") }
                NavigationLink { NexusPortableBackupView() } label: { Label("Backup & Restore", systemImage: "arrow.up.arrow.down.circle") }
            }

            Section("Discoverability") {
                NavigationLink { NexusWhatsNewView() } label: { Label("What's New & Tips", systemImage: "wand.and.stars") }
                Text("These helpers are local-first and do not upload your vault. Model weights remain separately manageable and are excluded from portable backups.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Quality of Life")
    }

    private func captureClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            captureStatus = "Clipboard does not contain text."
            return
        }
        let record = KnowledgeRecord(
            id: "clipboard-\(UUID().uuidString)",
            source: "Clipboard",
            kind: .note,
            timestamp: Date(),
            title: "Clipboard capture",
            text: text,
            metadata: ["capture": "manual"]
        )
        model.merge([record], sourceName: "Clipboard")
        Task { await intelligence.index(records: model.records, files: library.files) }
        captureStatus = "Captured to NEXUS memory."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct NexusSmartLibraryView: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var prefs = NexusNiceFeaturesStore.shared

    private var fileTypes: [String] {
        let values = Set(library.files.map { $0.ext.uppercased().isEmpty ? "OTHER" : $0.ext.uppercased() })
        return ["All"] + values.sorted()
    }

    private var filtered: [NexusV8FileItem] {
        var items = library.files
        let q = prefs.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { items = items.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.ext.localizedCaseInsensitiveContains(q) || $0.kindLabel.localizedCaseInsensitiveContains(q) } }
        if prefs.showOnlyFavorites { items = items.filter { prefs.isFavorite($0) } }
        if prefs.preferredFileType != "All" { items = items.filter { ($0.ext.uppercased().isEmpty ? "OTHER" : $0.ext.uppercased()) == prefs.preferredFileType } }
        switch prefs.sortMode {
        case .newest: items.sort { $0.importedAt > $1.importedAt }
        case .oldest: items.sort { $0.importedAt < $1.importedAt }
        case .name: items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size: items.sort { $0.size > $1.size }
        }
        return items
    }

    var body: some View {
        List {
            Section {
                TextField("Search name, type, extension", text: $prefs.searchText)
                    .textInputAutocapitalization(.never)
                Picker("Type", selection: $prefs.preferredFileType) { ForEach(fileTypes, id: \.self) { Text($0) } }
                Picker("Sort", selection: $prefs.sortMode) { ForEach(NexusNiceFeaturesStore.SortMode.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Favorites only", isOn: $prefs.showOnlyFavorites)
            }

            Section("\(filtered.count) files") {
                if filtered.isEmpty {
                    ContentUnavailableView("No matching files", systemImage: "folder", description: Text("Change the filters or import more files."))
                }
                ForEach(filtered) { file in
                    NavigationLink { NexusV9FileIntelligenceView(item: file) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: file)).foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: prefs.compactLibraryRows ? 1 : 4) {
                                Text(file.name).font(.headline).lineLimit(1)
                                Text("\(file.kindLabel) • \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { prefs.toggleFavorite(file) } label: {
                                Image(systemName: prefs.isFavorite(file) ? "star.fill" : "star")
                            }.buttonStyle(.plain).foregroundStyle(prefs.isFavorite(file) ? .yellow : .secondary)
                        }
                        .padding(.vertical, prefs.compactLibraryRows ? 0 : 2)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { prefs.toggleFavorite(file) } label: { Label(prefs.isFavorite(file) ? "Unfavorite" : "Favorite", systemImage: "star") }.tint(.yellow)
                    }
                    .contextMenu {
                        Button { prefs.toggleFavorite(file) } label: { Label(prefs.isFavorite(file) ? "Remove Favorite" : "Add Favorite", systemImage: "star") }
                        ShareLink(item: file.url) { Label("Share File", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
        .navigationTitle("Smart Library")
    }

    private func icon(for file: NexusV8FileItem) -> String {
        if NexusV8FileSupport.imageExtensions.contains(file.ext) { return "photo.fill" }
        if file.ext == "pdf" { return "doc.richtext.fill" }
        if ["csv", "tsv"].contains(file.ext) { return "tablecells.fill" }
        return "doc.fill"
    }
}

struct NexusDuplicateFilesView: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var groups: [[NexusV8FileItem]] = []
    @State private var scanning = false
    @State private var status = "Not scanned"

    var body: some View {
        List {
            Section {
                Button { Task { await scan() } } label: { Label(scanning ? "Scanning…" : "Scan for Duplicates", systemImage: "doc.on.doc") }.disabled(scanning)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                Section("Duplicate group • \(group.count)") {
                    ForEach(group) { file in
                        HStack { VStack(alignment: .leading) { Text(file.name); Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }; Spacer(); ShareLink(item: file.url) { Image(systemName: "square.and.arrow.up") } }
                    }
                }
            }
        }
        .navigationTitle("Duplicates")
    }

    private func scan() async {
        scanning = true; status = "Hashing local files…"
        var map: [String:[NexusV8FileItem]] = [:]
        for file in library.files {
            if let digest = sha256(file.url) { map[digest, default: []].append(file) }
            await Task.yield()
        }
        groups = map.values.filter { $0.count > 1 }.sorted { $0.count > $1.count }
        let duplicateCopies = groups.reduce(0) { $0 + max(0, $1.count - 1) }
        status = duplicateCopies == 0 ? "No duplicate file contents found." : "Found \(duplicateCopies) duplicate copies in \(groups.count) groups."
        scanning = false
    }

    private func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let data = try? handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct NexusDataHealthView: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @ObservedObject private var prefs = NexusNiceFeaturesStore.shared

    private var missingFiles: Int { library.files.filter { !FileManager.default.fileExists(atPath: $0.url.path) }.count }
    private var indexedFileIDs: Set<String> { Set(intelligence.chunks.filter { $0.kind == .file }.map(\.sourceID)) }
    private var unindexedFiles: Int { library.files.filter { !indexedFileIDs.contains($0.id.uuidString) }.count }
    private var staleFavorites: Int { prefs.favoriteFileIDs.filter { id in !library.files.contains(where: { $0.id.uuidString == id }) }.count }

    var body: some View {
        List {
            Section("Checks") {
                healthRow("Missing local file copies", value: missingFiles, symbol: "exclamationmark.triangle")
                healthRow("Files not yet indexed", value: unindexedFiles, symbol: "magnifyingglass")
                healthRow("Stale favorite references", value: staleFavorites, symbol: "star.slash")
                HStack { Label("Search index", systemImage: "square.stack.3d.up"); Spacer(); Text("\(intelligence.chunks.count) chunks").foregroundStyle(.secondary) }
            }
            Section("Actions") {
                Button { Task { await intelligence.index(records: [], files: library.files, force: true) } } label: { Label("Rebuild file index", systemImage: "arrow.clockwise") }
                Button { cleanFavorites() } label: { Label("Clean stale favorites", systemImage: "sparkles") }.disabled(staleFavorites == 0)
                NavigationLink { NexusPortableBackupView() } label: { Label("Create a backup", systemImage: "archivebox") }
            }
            Section { Text("A healthy vault has no missing local copies and all current files represented in the search index. Backups provide portability but intentionally exclude downloadable model weights.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Data Health")
    }

    @ViewBuilder private func healthRow(_ title: String, value: Int, symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol); Spacer(); Text(value == 0 ? "OK" : "\(value)").foregroundStyle(value == 0 ? .green : .orange) }
    }

    private func cleanFavorites() {
        let valid = Set(library.files.map { $0.id.uuidString })
        prefs.favoriteFileIDs = prefs.favoriteFileIDs.intersection(valid)
    }
}

struct NexusWhatsNewView: View {
    var body: some View {
        List {
            Section("Latest additions") {
                feature("Portable backup + restore", "Export records, imported files, organization metadata and portable intelligence state; restore with validation and deduplication.", "arrow.up.arrow.down.circle")
                feature("Safe model management", "Downloaded language and vision models are detected before download and can be deleted explicitly to reclaim space.", "cpu")
                feature("Smart Library", "Search, filter, sort, favorite and share local files without leaving NEXUS.", "folder.badge.gearshape")
                feature("Clipboard Capture", "Turn copied text into a local memory record in one tap.", "doc.on.clipboard")
                feature("Duplicate Finder", "Content-hash local files to identify exact duplicate copies.", "doc.on.doc")
                feature("Data Health", "Check missing files, indexing coverage and stale favorite references.", "checkmark.shield")
            }
            Section("Useful shortcuts") {
                Text("• Use Battery Saver before long sessions away from power.\n• Favorite frequently used files in Organized Library.\n• Rebuild the index after large imports if search results feel incomplete.\n• Export a backup before deleting a large source or resetting the app.\n• Delete model downloads you are not actively using; they can be downloaded again later.")
                    .font(.subheadline)
            }
        }.navigationTitle("What's New")
    }

    @ViewBuilder private func feature(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) { Image(systemName: symbol).foregroundStyle(.cyan).frame(width: 28); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) } }
    }
}
