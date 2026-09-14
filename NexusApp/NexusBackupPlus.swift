import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import ZIPFoundation

struct NexusOrganizationBackupState: Codable {
    let favoriteFileIDs: [String]
    let recentFileIDs: [String]
    let tagsByFileID: [String:[String]]
    let compactLibraryRows: Bool
    let hapticsEnabled: Bool
    let confirmDestructiveActions: Bool
}

enum NexusBackupPlusEngine {
    private static let organizationFile = "nexus-organization.json"

    @MainActor
    static func export(model: NexusModel) throws -> URL {
        let fm = FileManager.default
        let baseZip = try NexusV9BackupEngine.export(model: model)
        let extraction = fm.temporaryDirectory.appendingPathComponent("NEXUS-BackupPlus-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: extraction, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: extraction) }
        try fm.unzipItem(at: baseZip, to: extraction)

        guard let manifestURL = findFile(named: "manifest.json", under: extraction) else {
            throw NexusV9BackupError.manifestMissing
        }
        let root = manifestURL.deletingLastPathComponent()
        let favorites = NexusNiceFeaturesStore.shared
        let metadata = NexusFileMetadataStore.shared
        let state = NexusOrganizationBackupState(
            favoriteFileIDs: Array(favorites.favoriteFileIDs),
            recentFileIDs: metadata.recentFileIDs,
            tagsByFileID: metadata.tagsByFileID,
            compactLibraryRows: favorites.compactLibraryRows,
            hapticsEnabled: metadata.hapticsEnabled,
            confirmDestructiveActions: metadata.confirmDestructiveActions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: root.appendingPathComponent(organizationFile), options: .atomic)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let destination = fm.temporaryDirectory.appendingPathComponent("NEXUS-Backup-\(formatter.string(from: Date()))-complete.zip")
        try? fm.removeItem(at: destination)
        try fm.zipItem(at: root, to: destination)
        try? fm.removeItem(at: baseZip)
        return destination
    }

    @MainActor
    static func importBackup(from sourceURL: URL, model: NexusModel) throws -> NexusV9BackupImportResult {
        let fm = FileManager.default
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        let local = fm.temporaryDirectory.appendingPathComponent("NEXUS-RestoreSource-\(UUID().uuidString).zip")
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
            try? fm.removeItem(at: local)
        }
        try? fm.removeItem(at: local)
        try fm.copyItem(at: sourceURL, to: local)

        let inspection = fm.temporaryDirectory.appendingPathComponent("NEXUS-RestoreInspect-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: inspection, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: inspection) }
        try fm.unzipItem(at: local, to: inspection)

        var organization: NexusOrganizationBackupState?
        var manifest: NexusV9BackupManifest?
        if let manifestURL = findFile(named: "manifest.json", under: inspection) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try? decoder.decode(NexusV9BackupManifest.self, from: Data(contentsOf: manifestURL))
            let orgURL = manifestURL.deletingLastPathComponent().appendingPathComponent(organizationFile)
            if fm.fileExists(atPath: orgURL.path) {
                organization = try? JSONDecoder().decode(NexusOrganizationBackupState.self, from: Data(contentsOf: orgURL))
            }
        }

        let result = try NexusV9BackupEngine.importBackup(from: local, model: model)
        guard let organization, let manifest else { return result }

        let idMap = remapFileIDs(manifest: manifest, library: NexusV8FileLibrary.shared)
        let favoriteStore = NexusNiceFeaturesStore.shared
        let metadataStore = NexusFileMetadataStore.shared

        favoriteStore.favoriteFileIDs = Set(organization.favoriteFileIDs.compactMap { old in
            UUID(uuidString: old).flatMap { idMap[$0]?.uuidString } ?? old
        })
        favoriteStore.compactLibraryRows = organization.compactLibraryRows

        metadataStore.recentFileIDs = organization.recentFileIDs.compactMap { old in
            UUID(uuidString: old).flatMap { idMap[$0]?.uuidString } ?? old
        }
        var remappedTags: [String:[String]] = [:]
        for (old, tags) in organization.tagsByFileID {
            let mapped = UUID(uuidString: old).flatMap { idMap[$0]?.uuidString } ?? old
            remappedTags[mapped] = tags
        }
        metadataStore.tagsByFileID = remappedTags
        metadataStore.hapticsEnabled = organization.hapticsEnabled
        metadataStore.confirmDestructiveActions = organization.confirmDestructiveActions

        let validIDs = Set(NexusV8FileLibrary.shared.files.map { $0.id.uuidString })
        favoriteStore.favoriteFileIDs = favoriteStore.favoriteFileIDs.intersection(validIDs)
        metadataStore.prune(validIDs: validIDs)
        return result
    }

    private static func remapFileIDs(manifest: NexusV9BackupManifest, library: NexusV8FileLibrary) -> [UUID:UUID] {
        var output: [UUID:UUID] = [:]
        var digestCache: [String:String] = [:]
        for entry in manifest.files {
            if let candidate = library.files.first(where: { file in
                guard file.name == entry.originalName, file.size == entry.size else { return false }
                let digest: String
                if let cached = digestCache[file.path] { digest = cached }
                else {
                    digest = sha256(file.url)
                    digestCache[file.path] = digest
                }
                return digest == entry.sha256
            }) {
                output[entry.id] = candidate.id
            }
        }
        return output
    }

    private static func findFile(named name: String, under root: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in e where url.lastPathComponent == name { return url }
        return nil
    }

    private static func sha256(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = (try? handle.read(upToCount: 2 * 1_048_576)) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct NexusPortableBackupView: View {
    @EnvironmentObject private var model: NexusModel
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @ObservedObject private var favorites = NexusNiceFeaturesStore.shared
    @ObservedObject private var metadata = NexusFileMetadataStore.shared
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var showRestoreConfirmation = false
    @State private var busy = false
    @State private var status = ""

    var body: some View {
        List {
            Section("Complete portable backup") {
                LabeledContent("Records", value: "\(model.records.count)")
                LabeledContent("Imported files", value: "\(library.files.count)")
                LabeledContent("Chat messages", value: "\(model.chatMessages.count)")
                LabeledContent("Pinned files", value: "\(favorites.favoriteFileIDs.count)")
                LabeledContent("Tagged files", value: "\(metadata.tagsByFileID.count)")
                Text("Includes records, personality, chat, imported file copies, projects/workspaces, branches, automations, mini apps, ontology, performance preference, favorites, recents, tags, and organization settings. Downloadable AI model weights and derived search indexes stay excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Export") {
                Button {
                    busy = true
                    do {
                        exportURL = try NexusBackupPlusEngine.export(model: model)
                        status = "Complete backup created with file-integrity metadata and organization state."
                    } catch {
                        status = error.localizedDescription
                    }
                    busy = false
                } label: { Label("Create Complete Backup", systemImage: "externaldrive.badge.plus") }
                .disabled(busy)

                if let exportURL {
                    ShareLink(item: exportURL) { Label("Save / Share Backup", systemImage: "square.and.arrow.up") }
                    Text(exportURL.lastPathComponent).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section("Restore") {
                Button { showRestoreConfirmation = true } label: { Label("Restore from NEXUS Backup", systemImage: "externaldrive.badge.checkmark") }
                    .disabled(busy)
                Text("Restore validates the NEXUS package and imported-file checksums before merging. Existing records are not intentionally erased; duplicate files are reused. Favorites, recents and tags are remapped to restored file IDs.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if busy { Section { ProgressView("Working…") } }
            if !status.isEmpty { Section("Status") { Text(status).textSelection(.enabled) } }
        }
        .navigationTitle("Backup & Restore")
        .confirmationDialog("Restore a NEXUS backup?", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
            Button("Choose Backup and Merge") { importing = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The selected backup will be validated first. Valid data is merged into the current vault; this is not a replace/reset operation.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                busy = true
                let restored = try NexusBackupPlusEngine.importBackup(from: url, model: model)
                status = "Restored \(restored.records) records, imported \(restored.filesImported) file(s), reused \(restored.filesReused), and restored \(restored.chatMessages) chat message(s). Rebuilding search…"
                Task {
                    await intelligence.index(records: model.records, files: library.files, force: true)
                    await MainActor.run {
                        busy = false
                        status += " Done."
                    }
                }
            } catch {
                busy = false
                status = error.localizedDescription
            }
        }
    }
}
