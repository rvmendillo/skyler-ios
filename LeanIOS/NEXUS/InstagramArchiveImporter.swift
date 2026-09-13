import Foundation
import ZipArchive

struct NexusArchiveRecord: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case message, post, comment, like, saved, follow, search, profile, media, story, reaction, activity, unknown
    }

    let id: String
    let source: String
    let kind: Kind
    let timestamp: Date?
    let actor: String?
    let title: String?
    let text: String?
    let sourcePath: String
    let metadata: [String: String]
}

struct NexusArchiveImportResult {
    let records: [NexusArchiveRecord]
    let filesScanned: Int
    let warnings: [String]
}

final class InstagramArchiveImporter {
    enum ImportError: LocalizedError {
        case unsupportedFile
        case unzipFailed
        case unreadableArchive

        var errorDescription: String? {
            switch self {
            case .unsupportedFile: return "Choose an Instagram .zip export, a JSON file, or an extracted export folder."
            case .unzipFailed: return "The Instagram export could not be unzipped."
            case .unreadableArchive: return "The Instagram archive could not be read."
            }
        }
    }

    private let fileManager = FileManager.default

    func importArchive(from url: URL) throws -> NexusArchiveImportResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var cleanupURL: URL?
        let root: URL

        if url.pathExtension.lowercased() == "zip" {
            let destination = fileManager.temporaryDirectory
                .appendingPathComponent("nexus-instagram-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            guard SSZipArchive.unzipFile(atPath: url.path, toDestination: destination.path) else {
                try? fileManager.removeItem(at: destination)
                throw ImportError.unzipFailed
            }
            root = destination
            cleanupURL = destination
        } else {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ImportError.unreadableArchive
            }
            if isDirectory.boolValue || url.pathExtension.lowercased() == "json" {
                root = url
            } else {
                throw ImportError.unsupportedFile
            }
        }

        defer { if let cleanupURL { try? fileManager.removeItem(at: cleanupURL) } }

        let jsonFiles = collectJSONFiles(root: root)
        var records: [NexusArchiveRecord] = []
        var warnings: [String] = []

        for file in jsonFiles {
            do {
                let data = try Data(contentsOf: file)
                let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                let relativePath = relativePath(of: file, under: root)
                parse(node: object, path: relativePath, inheritedTitle: nil, into: &records)
            } catch {
                warnings.append("Skipped \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        let unique = Dictionary(grouping: records, by: \.id).compactMap { $0.value.first }
        return NexusArchiveImportResult(
            records: unique.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) },
            filesScanned: jsonFiles.count,
            warnings: warnings
        )
    }

    private func collectJSONFiles(root: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            return root.pathExtension.lowercased() == "json" ? [root] : []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var output: [URL] = []
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "json" {
            output.append(file)
        }
        return output
    }

    private func parse(node: Any, path: String, inheritedTitle: String?, into records: inout [NexusArchiveRecord]) {
        if let dictionary = node as? [String: Any] {
            let title = clean(dictionary["title"] as? String) ?? inheritedTitle

            if let messages = dictionary["messages"] as? [[String: Any]] {
                for message in messages { parseMessage(message, path: path, threadTitle: title, into: &records) }
            }

            if let stringList = dictionary["string_list_data"] as? [[String: Any]], !stringList.isEmpty {
                for item in stringList {
                    let value = clean(item["value"] as? String)
                    let timestamp = date(from: item["timestamp"] ?? item["timestamp_ms"])
                    append(kind: classify(path: path, dictionary: dictionary), path: path, timestamp: timestamp,
                           actor: value, title: title, text: value, metadata: scalarMetadata(item), into: &records)
                }
                return
            }

            if let mapData = dictionary["string_map_data"] as? [String: Any], !mapData.isEmpty {
                let flattened = flattenStringMap(mapData)
                let timestamp = firstDate(in: mapData)
                append(kind: classify(path: path, dictionary: dictionary), path: path, timestamp: timestamp,
                       actor: flattened["Media Owner"] ?? flattened["Author"] ?? flattened["Name"],
                       title: title, text: flattened["Comment"] ?? flattened["Query"] ?? flattened["Value"],
                       metadata: flattened, into: &records)
                return
            }

            if looksLikeStandaloneActivity(dictionary, path: path) {
                append(kind: classify(path: path, dictionary: dictionary), path: path,
                       timestamp: firstDate(in: dictionary), actor: firstString(dictionary, keys: ["sender_name", "username", "name", "author"]),
                       title: title, text: firstString(dictionary, keys: ["content", "text", "caption", "query", "value"]),
                       metadata: scalarMetadata(dictionary), into: &records)
            }

            for (_, value) in dictionary {
                parse(node: value, path: path, inheritedTitle: title, into: &records)
            }
        } else if let array = node as? [Any] {
            for value in array { parse(node: value, path: path, inheritedTitle: inheritedTitle, into: &records) }
        }
    }

    private func parseMessage(_ message: [String: Any], path: String, threadTitle: String?, into records: inout [NexusArchiveRecord]) {
        let timestamp = date(from: message["timestamp_ms"] ?? message["timestamp"])
        let sender = clean(message["sender_name"] as? String)
        let content = clean(message["content"] as? String)
        let share = ((message["share"] as? [String: Any])?["link"] as? String)
        let reactionText: String? = {
            guard let reactions = message["reactions"] as? [[String: Any]], !reactions.isEmpty else { return nil }
            return reactions.compactMap { reaction in
                let actor = clean(reaction["actor"] as? String) ?? "Someone"
                let reaction = clean(reaction["reaction"] as? String) ?? "reaction"
                return "\(actor): \(reaction)"
            }.joined(separator: ", ")
        }()

        var metadata = scalarMetadata(message)
        if let share { metadata["share"] = share }
        if let reactionText { metadata["reactions"] = reactionText }

        append(kind: .message, path: path, timestamp: timestamp, actor: sender,
               title: threadTitle, text: content ?? share, metadata: metadata, into: &records)
    }

    private func classify(path: String, dictionary: [String: Any]) -> NexusArchiveRecord.Kind {
        let value = path.lowercased()
        if value.contains("message") || dictionary["sender_name"] != nil { return .message }
        if value.contains("comment") { return .comment }
        if value.contains("like") { return .like }
        if value.contains("saved") { return .saved }
        if value.contains("follow") || value.contains("followers") || value.contains("following") { return .follow }
        if value.contains("search") { return .search }
        if value.contains("story") { return .story }
        if value.contains("post") || value.contains("media") || value.contains("content") { return .post }
        if value.contains("profile") || value.contains("personal_information") { return .profile }
        if value.contains("reaction") { return .reaction }
        return .activity
    }

    private func looksLikeStandaloneActivity(_ dictionary: [String: Any], path: String) -> Bool {
        let activityKeys = ["timestamp", "timestamp_ms", "content", "caption", "query", "value", "username", "sender_name"]
        return activityKeys.contains { dictionary[$0] != nil } || path.lowercased().contains("activity")
    }

    private func append(kind: NexusArchiveRecord.Kind, path: String, timestamp: Date?, actor: String?, title: String?, text: String?, metadata: [String: String], into records: inout [NexusArchiveRecord]) {
        let normalizedActor = clean(actor)
        let normalizedTitle = clean(title)
        let normalizedText = clean(text)
        guard normalizedActor != nil || normalizedTitle != nil || normalizedText != nil || !metadata.isEmpty else { return }

        let fingerprintSource = [
            "instagram", kind.rawValue, path,
            timestamp.map { String(Int($0.timeIntervalSince1970)) } ?? "",
            normalizedActor ?? "", normalizedTitle ?? "", normalizedText ?? "",
            metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
        ].joined(separator: "¦")

        records.append(NexusArchiveRecord(
            id: stableFingerprint(fingerprintSource),
            source: "instagram",
            kind: kind,
            timestamp: timestamp,
            actor: normalizedActor,
            title: normalizedTitle,
            text: normalizedText,
            sourcePath: path,
            metadata: metadata
        ))
    }

    private func scalarMetadata(_ dictionary: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in dictionary.prefix(40) {
            if let string = value as? String { result[key] = clean(string) }
            else if let number = value as? NSNumber { result[key] = number.stringValue }
        }
        return result
    }

    private func flattenStringMap(_ map: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, raw) in map {
            if let object = raw as? [String: Any] {
                if let value = clean(object["value"] as? String) { result[key] = value }
                else if let href = clean(object["href"] as? String) { result[key] = href }
                if let timestamp = object["timestamp"] as? NSNumber { result["\(key) Timestamp"] = timestamp.stringValue }
            } else if let value = clean(raw as? String) {
                result[key] = value
            }
        }
        return result
    }

    private func firstString(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys { if let value = clean(dictionary[key] as? String) { return value } }
        return nil
    }

    private func firstDate(in dictionary: [String: Any]) -> Date? {
        for key in ["timestamp_ms", "timestamp", "time", "created_at", "creation_timestamp"] {
            if let value = dictionary[key], let date = date(from: value) { return date }
        }
        for value in dictionary.values {
            if let child = value as? [String: Any], let date = firstDate(in: child) { return date }
        }
        return nil
    }

    private func date(from raw: Any?) -> Date? {
        if let number = raw as? NSNumber {
            let value = number.doubleValue
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        if let string = raw as? String {
            if let numeric = Double(string) { return Date(timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1000 : numeric) }
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: string)
        }
        return nil
    }

    private func clean(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        // Some older Meta exports represent UTF-8 bytes as Latin-1 characters.
        if value.contains("Ã") || value.contains("ð") || value.contains("â") {
            if let bytes = value.data(using: .isoLatin1), let repaired = String(data: bytes, encoding: .utf8) {
                value = repaired
            }
        }
        return value
    }

    private func relativePath(of file: URL, under root: URL) -> String {
        let base = root.standardizedFileURL.path
        let full = file.standardizedFileURL.path
        return full.hasPrefix(base) ? String(full.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : file.lastPathComponent
    }

    private func stableFingerprint(_ string: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
