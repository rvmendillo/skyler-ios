import Foundation
import SwiftUI
import UIKit

@MainActor
final class NexusFileMetadataStore: ObservableObject {
    static let shared = NexusFileMetadataStore()

    @Published var recentFileIDs: [String] { didSet { save() } }
    @Published var tagsByFileID: [String:[String]] { didSet { save() } }
    @Published var hapticsEnabled: Bool { didSet { save() } }
    @Published var confirmDestructiveActions: Bool { didSet { save() } }

    private let defaults = UserDefaults.standard

    private init() {
        recentFileIDs = defaults.stringArray(forKey: "nexus.meta.recents") ?? []
        tagsByFileID = defaults.dictionary(forKey: "nexus.meta.tags") as? [String:[String]] ?? [:]
        hapticsEnabled = defaults.object(forKey: "nexus.meta.haptics") as? Bool ?? true
        confirmDestructiveActions = defaults.object(forKey: "nexus.meta.confirmDestructive") as? Bool ?? true
    }

    func markRecent(_ file: NexusV8FileItem) {
        let id = file.id.uuidString
        recentFileIDs.removeAll { $0 == id }
        recentFileIDs.insert(id, at: 0)
        if recentFileIDs.count > 24 { recentFileIDs = Array(recentFileIDs.prefix(24)) }
    }

    func tags(for file: NexusV8FileItem) -> [String] { tagsByFileID[file.id.uuidString] ?? [] }

    func setTags(_ tags: [String], for file: NexusV8FileItem) {
        let clean = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })).sorted()
        if clean.isEmpty { tagsByFileID.removeValue(forKey: file.id.uuidString) }
        else { tagsByFileID[file.id.uuidString] = clean }
    }

    func prune(validIDs: Set<String>) {
        recentFileIDs.removeAll { !validIDs.contains($0) }
        tagsByFileID = tagsByFileID.filter { validIDs.contains($0.key) }
    }

    private func save() {
        defaults.set(recentFileIDs, forKey: "nexus.meta.recents")
        defaults.set(tagsByFileID, forKey: "nexus.meta.tags")
        defaults.set(hapticsEnabled, forKey: "nexus.meta.haptics")
        defaults.set(confirmDestructiveActions, forKey: "nexus.meta.confirmDestructive")
    }
}

struct NexusProductivityHubView: View {
    @EnvironmentObject private var model: NexusModel
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @ObservedObject private var favorites = NexusNiceFeaturesStore.shared
    @ObservedObject private var metadata = NexusFileMetadataStore.shared
    @State private var clipboardStatus = ""

    var body: some View {
        List {
            Section("Organize") {
                NavigationLink { NexusOrganizedLibraryView() } label: { Label("Organized Library", systemImage: "folder.badge.gearshape") }
                NavigationLink { NexusRecentFilesView() } label: { Label("Recent Files", systemImage: "clock.arrow.circlepath") }
                NavigationLink { NexusTagBrowserView() } label: { Label("Tags", systemImage: "tag.fill") }
                LabeledContent("Pinned / Favorites", value: "\(favorites.favoriteFileIDs.count)")
            }

            Section("Quick actions") {
                Button { captureClipboard() } label: { Label("Capture Clipboard to Memory", systemImage: "doc.on.clipboard") }
                if !clipboardStatus.isEmpty { Text(clipboardStatus).font(.caption).foregroundStyle(.secondary) }
                NavigationLink { AskV9View() } label: { Label("Quick Ask", systemImage: "sparkles") }
                NavigationLink { NexusV9GlobalSearchView() } label: { Label("Search Everything", systemImage: "magnifyingglass") }
                Button { Task { await intelligence.index(records: model.records, files: library.files, force: true) } } label: { Label("Rebuild Search Index", systemImage: "arrow.triangle.2.circlepath") }
            }

            Section("Protect & maintain") {
                NavigationLink { NexusV9BackupView() } label: { Label("Backup & Restore", systemImage: "arrow.up.arrow.down.circle") }
                NavigationLink { NexusDuplicateFilesView() } label: { Label("Find Duplicate Files", systemImage: "doc.on.doc") }
                NavigationLink { NexusDataHealthView() } label: { Label("Data Health", systemImage: "checkmark.shield") }
                NavigationLink { NexusSettingsHubView() } label: { Label("Settings & Maintenance", systemImage: "gearshape.fill") }
            }

            Section("Status") {
                LabeledContent("Local files", value: "\(library.files.count)")
                LabeledContent("Searchable chunks", value: "\(intelligence.chunks.count)")
                LabeledContent("Recent files", value: "\(metadata.recentFileIDs.count)")
                Text("Backups are validated before restore and merge without intentionally deleting the current vault. Downloaded model weights remain separately manageable and are not packed into backups.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Productivity Hub")
    }

    private func captureClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            clipboardStatus = "Clipboard has no text to capture."
            return
        }
        let record = KnowledgeRecord(id: "clipboard-\(UUID().uuidString)", source: "Clipboard", kind: .note, timestamp: Date(), title: "Clipboard capture", text: text, metadata: ["capture":"manual"])
        model.merge([record], sourceName: "Clipboard")
        Task { await intelligence.index(records: model.records, files: library.files) }
        clipboardStatus = "Captured to local NEXUS memory."
        if metadata.hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}

struct NexusOrganizedLibraryView: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var favorites = NexusNiceFeaturesStore.shared
    @ObservedObject private var metadata = NexusFileMetadataStore.shared
    @State private var query = ""
    @State private var type = "All"
    @State private var onlyFavorites = false
    @State private var sort = NexusNiceFeaturesStore.SortMode.newest

    private var types: [String] {
        ["All"] + Set(library.files.map { $0.ext.isEmpty ? "OTHER" : $0.ext.uppercased() }).sorted()
    }

    private var files: [NexusV8FileItem] {
        var result = library.files
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter { file in
                let tags = metadata.tags(for: file).joined(separator: " ")
                return (file.name + " " + file.ext + " " + file.kindLabel + " " + tags).lowercased().contains(q)
            }
        }
        if type != "All" { result = result.filter { ($0.ext.isEmpty ? "OTHER" : $0.ext.uppercased()) == type } }
        if onlyFavorites { result = result.filter { favorites.isFavorite($0) } }
        switch sort {
        case .newest: result.sort { $0.importedAt > $1.importedAt }
        case .oldest: result.sort { $0.importedAt < $1.importedAt }
        case .name: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size: result.sort { $0.size > $1.size }
        }
        return result
    }

    var body: some View {
        List {
            Section {
                TextField("Search files and tags", text: $query).textInputAutocapitalization(.never)
                Picker("Type", selection: $type) { ForEach(types, id: \.self) { Text($0) } }
                Picker("Sort", selection: $sort) { ForEach(NexusNiceFeaturesStore.SortMode.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Favorites only", isOn: $onlyFavorites)
            }

            Section("\(files.count) files") {
                if files.isEmpty {
                    ContentUnavailableView("No matching files", systemImage: "folder", description: Text("Try another search, tag, type, or favorite filter."))
                }
                ForEach(files) { file in
                    NavigationLink {
                        NexusSmartFileDetailView(file: file).onAppear { metadata.markRecent(file) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: fileIcon(file)).foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.name).font(.headline).lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(file.kindLabel)
                                    Text("•")
                                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                }.font(.caption).foregroundStyle(.secondary)
                                if !metadata.tags(for: file).isEmpty {
                                    Text(metadata.tags(for: file).map { "#\($0)" }.joined(separator: "  ")).font(.caption2).foregroundStyle(.mint).lineLimit(1)
                                }
                            }
                            Spacer()
                            if favorites.isFavorite(file) { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { favorites.toggleFavorite(file) } label: { Label(favorites.isFavorite(file) ? "Unpin" : "Pin", systemImage: "star") }.tint(.yellow)
                    }
                }
            }
        }
        .navigationTitle("Organized Library")
    }

    private func fileIcon(_ file: NexusV8FileItem) -> String {
        if NexusV8FileSupport.imageExtensions.contains(file.ext) { return "photo.fill" }
        if file.ext == "pdf" { return "doc.richtext.fill" }
        if ["csv","tsv"].contains(file.ext) { return "tablecells.fill" }
        return "doc.fill"
    }
}

struct NexusSmartFileDetailView: View {
    let file: NexusV8FileItem
    @ObservedObject private var favorites = NexusNiceFeaturesStore.shared
    @ObservedObject private var metadata = NexusFileMetadataStore.shared

    var body: some View {
        List {
            Section("File") {
                LabeledContent("Name", value: file.name)
                LabeledContent("Type", value: file.kindLabel)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                Toggle("Pinned / Favorite", isOn: Binding(get: { favorites.isFavorite(file) }, set: { _ in favorites.toggleFavorite(file) }))
            }
            Section("Tags") {
                NavigationLink { NexusTagEditorView(file: file) } label: { Label("Edit Tags", systemImage: "tag") }
                if metadata.tags(for: file).isEmpty { Text("No tags yet").foregroundStyle(.secondary) }
                else { Text(metadata.tags(for: file).map { "#\($0)" }.joined(separator: "  ")).foregroundStyle(.mint) }
            }
            Section("Open") {
                NavigationLink { NexusV9FileIntelligenceView(item: file) } label: { Label("Open File Intelligence", systemImage: "sparkles.rectangle.stack") }
                ShareLink(item: file.url) { Label("Share File", systemImage: "square.and.arrow.up") }
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NexusTagEditorView: View {
    let file: NexusV8FileItem
    @ObservedObject private var metadata = NexusFileMetadataStore.shared
    @State private var text = ""

    var body: some View {
        Form {
            Section("Tags") {
                TextField("work, finance, travel", text: $text)
                    .textInputAutocapitalization(.never)
                Text("Separate tags with commas. Tags are stored locally and become searchable in Organized Library.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Save Tags") {
                    metadata.setTags(text.split(separator: ",").map(String.init), for: file)
                }
                Button("Clear Tags", role: .destructive) {
                    metadata.setTags([], for: file); text = ""
                }
            }
        }
        .navigationTitle("Edit Tags")
        .onAppear { text = metadata.tags(for: file).joined(separator: ", ") }
    }
}

struct NexusRecentFilesView: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var metadata = NexusFileMetadataStore.shared

    private var recent: [NexusV8FileItem] {
        metadata.recentFileIDs.compactMap { id in library.files.first { $0.id.uuidString == id } }
    }

    var body: some View {
        List {
            if recent.isEmpty {
                ContentUnavailableView("No recent files", systemImage: "clock", description: Text("Files you open from Organized Library will appear here."))
            }
            ForEach(recent) { file in
                NavigationLink { NexusSmartFileDetailView(file: file).onAppear { metadata.markRecent(file) } } label: {
                    VStack(alignment: .leading) { Text(file.name); Text(file.kindLabel).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("Recent Files")
    }
}

struct NexusTagBrowserView: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var metadata = NexusFileMetadataStore.shared

    private var tags: [String] { Array(Set(metadata.tagsByFileID.values.flatMap { $0 })).sorted() }

    var body: some View {
        List {
            if tags.isEmpty {
                ContentUnavailableView("No tags yet", systemImage: "tag", description: Text("Add tags from any file in Organized Library."))
            }
            ForEach(tags, id: \.self) { tag in
                NavigationLink {
                    NexusTagFilesView(tag: tag)
                } label: {
                    HStack { Label(tag, systemImage: "tag.fill"); Spacer(); Text("\(count(tag))").foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("Tags")
    }

    private func count(_ tag: String) -> Int {
        library.files.filter { metadata.tags(for: $0).contains(tag) }.count
    }
}

struct NexusTagFilesView: View {
    let tag: String
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var metadata = NexusFileMetadataStore.shared

    private var files: [NexusV8FileItem] { library.files.filter { metadata.tags(for: $0).contains(tag) } }

    var body: some View {
        List(files) { file in
            NavigationLink { NexusSmartFileDetailView(file: file).onAppear { metadata.markRecent(file) } } label: { Text(file.name) }
        }.navigationTitle("#\(tag)")
    }
}

struct NexusSettingsHubView: View {
    @EnvironmentObject private var model: NexusModel
    @ObservedObject private var metadata = NexusFileMetadataStore.shared
    @ObservedObject private var favorites = NexusNiceFeaturesStore.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared

    var body: some View {
        Form {
            Section("Interface") {
                Toggle("Haptic feedback", isOn: $metadata.hapticsEnabled)
                Toggle("Compact library rows", isOn: $favorites.compactLibraryRows)
            }
            Section("Safety") {
                Toggle("Confirm destructive actions", isOn: $metadata.confirmDestructiveActions)
                NavigationLink { NexusV9BackupView() } label: { Label("Backup & Restore", systemImage: "archivebox") }
                Text("Restore validates the NEXUS manifest and imported-file checksums before merging data.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Maintenance") {
                Button { Task { await intelligence.index(records: model.records, files: library.files, force: true) } } label: { Label("Rebuild Search Index", systemImage: "arrow.clockwise") }
                Button { pruneMetadata() } label: { Label("Clean Stale Favorites / Recents / Tags", systemImage: "sparkles") }
                NavigationLink { NexusV9StorageView() } label: { Label("Storage Manager", systemImage: "internaldrive") }
                NavigationLink { NexusV9PerformanceView() } label: { Label("Performance & Diagnostics", systemImage: "gauge.with.dots.needle.67percent") }
            }
            Section("Privacy") {
                NavigationLink { NexusV9SecurityView() } label: { Label("Privacy & Security", systemImage: "lock.shield") }
                Text("Organization metadata such as favorites, recents and tags stays on device.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
    }

    private func pruneMetadata() {
        let valid = Set(library.files.map { $0.id.uuidString })
        favorites.favoriteFileIDs = favorites.favoriteFileIDs.intersection(valid)
        metadata.prune(validIDs: valid)
    }
}
