import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import ZIPFoundation

struct NexusV9PortableState: Codable {
    var workspaces: [NexusV9Workspace]
    var activeWorkspaceID: UUID?
    var branches: [NexusV9ConversationBranch]
    var automations: [NexusV9AutomationRule]
    var miniApps: [NexusV9MiniApp]
    var ontology: [String:String]
    var performanceMode: NexusV9PerformanceMode
}

extension NexusV9IntelligenceStore {
    func portableState() -> NexusV9PortableState {
        NexusV9PortableState(
            workspaces: workspaces,
            activeWorkspaceID: activeWorkspaceID,
            branches: branches,
            automations: automations,
            miniApps: miniApps,
            ontology: ontology,
            performanceMode: performanceMode
        )
    }

    func restorePortableState(_ state: NexusV9PortableState, fileIDMap: [UUID:UUID]) {
        let restoredWorkspaces = state.workspaces.map { workspace -> NexusV9Workspace in
            var copy = workspace
            copy.fileIDs = Set(workspace.fileIDs.map { fileIDMap[$0] ?? $0 })
            return copy
        }
        workspaces.removeAll { current in
            restoredWorkspaces.contains { $0.name.caseInsensitiveCompare(current.name) == .orderedSame }
        }
        workspaces.append(contentsOf: restoredWorkspaces)
        activeWorkspaceID = state.activeWorkspaceID

        let restoredBranches = state.branches.map { branch -> NexusV9ConversationBranch in
            var copy = branch
            copy.messages = branch.messages.map { message in
                NexusV9StoredMessage(
                    id: message.id,
                    role: message.role,
                    text: message.text,
                    attachmentIDs: message.attachmentIDs.map { fileIDMap[$0] ?? $0 },
                    createdAt: message.createdAt
                )
            }
            return copy
        }
        var branchMap = Dictionary(uniqueKeysWithValues: branches.map { ($0.id, $0) })
        restoredBranches.forEach { branchMap[$0.id] = $0 }
        branches = branchMap.values.sorted { $0.createdAt > $1.createdAt }

        automations.removeAll { current in
            state.automations.contains { $0.name.caseInsensitiveCompare(current.name) == .orderedSame }
        }
        automations.append(contentsOf: state.automations)

        var miniMap = Dictionary(uniqueKeysWithValues: miniApps.map { ($0.id, $0) })
        state.miniApps.forEach { miniMap[$0.id] = $0 }
        miniApps = miniMap.values.sorted { $0.createdAt > $1.createdAt }

        ontology.merge(state.ontology) { _, restored in restored }
        performanceMode = state.performanceMode
        runAutomations(for: .manual)
    }
}

struct NexusV9BackupChatMessage: Codable {
    let role: String
    let text: String
    let evidence: [String]
    let timestamp: Date
}

struct NexusV9BackupFileEntry: Codable {
    let id: UUID
    let originalName: String
    let archivePath: String
    let typeIdentifier: String
    let size: Int64
    let importedAt: Date
    let sha256: String
}

struct NexusV9BackupManifest: Codable {
    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let appBuild: String
    let recordCount: Int
    let fileCount: Int
    let chatCount: Int
    let includes: [String]
    let files: [NexusV9BackupFileEntry]
}

struct NexusV9BackupPayload: Codable {
    let records: [KnowledgeRecord]
    let personality: PersonalityProfile
    let chat: [NexusV9BackupChatMessage]
    let intelligence: NexusV9PortableState
}

struct NexusV9BackupImportResult {
    let records: Int
    let filesImported: Int
    let filesReused: Int
    let chatMessages: Int
}

enum NexusV9BackupError: LocalizedError {
    case manifestMissing
    case unsupportedFormat
    case corruptPayload
    case unsafePath
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .manifestMissing: return "This ZIP does not contain a NEXUS backup manifest."
        case .unsupportedFormat: return "This backup format is not supported by this NEXUS version."
        case .corruptPayload: return "The NEXUS backup payload is missing or unreadable."
        case .unsafePath: return "The backup contains an unsafe file path and was rejected."
        case .checksumMismatch(let name): return "Integrity check failed for \(name). The backup may be incomplete or modified."
        }
    }
}

enum NexusV9BackupEngine {
    private static let format = "com.rey.nexus.backup"
    private static let schemaVersion = 1

    @MainActor
    static func export(model: NexusModel) throws -> URL {
        let fm = FileManager.default
        let library = NexusV8FileLibrary.shared
        let intelligence = NexusV9IntelligenceStore.shared
        let root = fm.temporaryDirectory.appendingPathComponent("NEXUS-Backup-\(UUID().uuidString)", isDirectory: true)
        let filesFolder = root.appendingPathComponent("Files", isDirectory: true)
        try fm.createDirectory(at: filesFolder, withIntermediateDirectories: true)

        var entries: [NexusV9BackupFileEntry] = []
        for item in library.files where fm.fileExists(atPath: item.path) {
            let safeName = safeFileName(item.name)
            let archiveName = "\(item.id.uuidString)-\(safeName)"
            let destination = filesFolder.appendingPathComponent(archiveName)
            try fm.copyItem(at: item.url, to: destination)
            let size = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            entries.append(NexusV9BackupFileEntry(
                id: item.id,
                originalName: item.name,
                archivePath: "Files/\(archiveName)",
                typeIdentifier: item.typeIdentifier,
                size: size,
                importedAt: item.importedAt,
                sha256: sha256(destination)
            ))
        }

        let chat = model.chatMessages.map {
            NexusV9BackupChatMessage(role: $0.role.rawValue, text: $0.text, evidence: $0.evidence, timestamp: $0.timestamp)
        }
        let payload = NexusV9BackupPayload(
            records: model.records,
            personality: model.personality,
            chat: chat,
            intelligence: intelligence.portableState()
        )
        let payloadData = try encoder().encode(payload)
        try payloadData.write(to: root.appendingPathComponent("nexus-data.json"), options: .atomic)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let manifest = NexusV9BackupManifest(
            format: format,
            schemaVersion: schemaVersion,
            exportedAt: Date(),
            appVersion: version,
            appBuild: build,
            recordCount: model.records.count,
            fileCount: entries.count,
            chatCount: chat.count,
            includes: ["records", "personality", "chat", "files", "workspaces", "conversation branches", "automations", "mini apps", "ontology", "performance preference"],
            files: entries
        )
        try encoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let zip = fm.temporaryDirectory.appendingPathComponent("NEXUS-Backup-\(formatter.string(from: Date())).zip")
        try? fm.removeItem(at: zip)
        try fm.zipItem(at: root, to: zip)
        return zip
    }

    @MainActor
    static func importBackup(from url: URL, model: NexusModel) throws -> NexusV9BackupImportResult {
        let fm = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let extraction = fm.temporaryDirectory.appendingPathComponent("NEXUS-Restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: extraction, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: extraction) }
        try fm.unzipItem(at: url, to: extraction)

        guard let manifestURL = findFile(named: "manifest.json", under: extraction) else { throw NexusV9BackupError.manifestMissing }
        let root = manifestURL.deletingLastPathComponent()
        let manifest = try decoder().decode(NexusV9BackupManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == format, manifest.schemaVersion == schemaVersion else { throw NexusV9BackupError.unsupportedFormat }
        let payloadURL = root.appendingPathComponent("nexus-data.json")
        guard fm.fileExists(atPath: payloadURL.path),
              let payload = try? decoder().decode(NexusV9BackupPayload.self, from: Data(contentsOf: payloadURL)) else {
            throw NexusV9BackupError.corruptPayload
        }
        guard payload.records.count == manifest.recordCount else { throw NexusV9BackupError.corruptPayload }

        let library = NexusV8FileLibrary.shared
        var fileIDMap: [UUID:UUID] = [:]
        var filesImported = 0
        var filesReused = 0

        for entry in manifest.files {
            guard isSafeRelativePath(entry.archivePath) else { throw NexusV9BackupError.unsafePath }
            let source = root.appendingPathComponent(entry.archivePath).standardizedFileURL
            let rootPath = root.standardizedFileURL.path + "/"
            guard source.path.hasPrefix(rootPath), fm.fileExists(atPath: source.path) else { throw NexusV9BackupError.unsafePath }
            let actualSize = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
            guard actualSize == entry.size, sha256(source) == entry.sha256 else { throw NexusV9BackupError.checksumMismatch(entry.originalName) }

            if let existing = library.files.first(where: { candidate in
                guard candidate.name == entry.originalName, candidate.size == entry.size, fm.fileExists(atPath: candidate.path) else { return false }
                return sha256(candidate.url) == entry.sha256
            }) {
                fileIDMap[entry.id] = existing.id
                filesReused += 1
                continue
            }

            let stagingDir = extraction.appendingPathComponent("Stage-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            let stagedName = safeFileName(entry.originalName)
            let stagedURL = stagingDir.appendingPathComponent(stagedName)
            try fm.copyItem(at: source, to: stagedURL)
            let imported = try library.importURLs([stagedURL])
            if let item = imported.first {
                fileIDMap[entry.id] = item.id
                filesImported += 1
            }
        }

        model.merge(payload.records, sourceName: "NEXUS Backup")
        model.personality = payload.personality
        model.saveProfile()

        var existingChatKeys = Set(model.chatMessages.map { "\($0.role.rawValue)|\($0.text)|\($0.evidence.joined(separator: "|"))" })
        var restoredChat = 0
        for saved in payload.chat {
            guard let role = ChatMessage.Role(rawValue: saved.role) else { continue }
            let key = "\(saved.role)|\(saved.text)|\(saved.evidence.joined(separator: "|"))"
            guard existingChatKeys.insert(key).inserted else { continue }
            model.chatMessages.append(ChatMessage(role: role, text: saved.text, evidence: saved.evidence))
            restoredChat += 1
        }

        let intelligence = NexusV9IntelligenceStore.shared
        intelligence.restorePortableState(payload.intelligence, fileIDMap: fileIDMap)
        return NexusV9BackupImportResult(records: payload.records.count, filesImported: filesImported, filesReused: filesReused, chatMessages: restoredChat)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func safeFileName(_ value: String) -> String {
        let last = URL(fileURLWithPath: value).lastPathComponent
        let cleaned = last.replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "file" : cleaned
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("..") && path.hasPrefix("Files/")
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

struct NexusV9BackupView: View {
    @EnvironmentObject private var model: NexusModel
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var busy = false
    @State private var status = ""

    var body: some View {
        List {
            Section("Portable NEXUS backup") {
                LabeledContent("Records", value: "\(model.records.count)")
                LabeledContent("Imported files", value: "\(library.files.count)")
                LabeledContent("Chat messages", value: "\(model.chatMessages.count)")
                Text("Backups include personal records, personality, chat, imported file copies, workspaces, branches, automations, mini apps, ontology and the performance preference. Downloaded AI model weights and derived search indexes are excluded; models can be downloaded again and indexes are rebuilt after restore.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Export") {
                Button {
                    busy = true
                    do {
                        exportURL = try NexusV9BackupEngine.export(model: model)
                        status = "Backup created and integrity metadata written."
                    } catch {
                        status = error.localizedDescription
                    }
                    busy = false
                } label: {
                    Label("Create NEXUS Backup", systemImage: "externaldrive.badge.plus")
                }.disabled(busy)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Save / Share Backup", systemImage: "square.and.arrow.up")
                    }
                    Text(exportURL.lastPathComponent).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section("Import / Restore") {
                Button { importing = true } label: {
                    Label("Import NEXUS Backup", systemImage: "externaldrive.badge.checkmark")
                }.disabled(busy)
                Text("Restore is non-destructive: records are merged by record ID, duplicate files are reused by filename + size + SHA-256, and portable workspace/app state is merged. The package is validated before data is accepted.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if busy { Section { ProgressView("Working…") } }
            if !status.isEmpty { Section("Status") { Text(status).textSelection(.enabled) } }
        }
        .navigationTitle("Backup & Restore")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                busy = true
                let restored = try NexusV9BackupEngine.importBackup(from: url, model: model)
                status = "Restored \(restored.records) records, imported \(restored.filesImported) file(s), reused \(restored.filesReused) existing file(s), and restored \(restored.chatMessages) new chat message(s). Rebuilding the semantic index…"
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
