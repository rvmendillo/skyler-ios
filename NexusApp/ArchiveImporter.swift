import Foundation
import ZIPFoundation
import CryptoKit

struct MetaArchiveImporter {
    func importURL(_ url: URL) throws -> [KnowledgeRecord] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return try importDirectory(url)
        }

        switch url.pathExtension.lowercased() {
        case "zip": return try importZip(url)
        case "json": return try parseJSON(url, relativePath: url.lastPathComponent)
        case "txt", "md", "csv", "tsv", "html", "htm", "xml": return try parseTextFile(url, relativePath: url.lastPathComponent)
        default: throw ImportError.unsupported(url.pathExtension.isEmpty ? url.lastPathComponent : url.pathExtension)
        }
    }

    /// Reads only supported text/JSON entries directly from the archive. Meta exports can be
    /// hundreds of MB because of photos and videos; extracting those files first is unnecessary,
    /// slow and can exhaust temporary storage on iOS.
    private func importZip(_ url: URL) throws -> [KnowledgeRecord] {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ImportError.unzip(error.localizedDescription)
        }

        let supported = Set(["json", "txt", "md", "csv", "tsv", "html", "htm", "xml"])
        var all: [KnowledgeRecord] = []
        var readableEntries = 0
        var parseFailures = 0

        for entry in archive {
            guard entry.type == .file else { continue }
            let path = entry.path
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard supported.contains(ext) else { continue }

            // Individual Meta JSON files are normally small. This prevents one malformed entry
            // from consuming excessive memory while still allowing very large activity files.
            guard entry.uncompressedSize <= 64 * 1024 * 1024 else {
                parseFailures += 1
                continue
            }

            var data = Data()
            data.reserveCapacity(Int(min(entry.uncompressedSize, 8 * 1024 * 1024)))
            do {
                try archive.extract(entry, bufferSize: 64 * 1024, skipCRC32: false) { chunk in
                    data.append(chunk)
                }
                readableEntries += 1
                if ext == "json" {
                    all.append(contentsOf: try parseJSONData(data, relativePath: path))
                } else {
                    all.append(contentsOf: parseTextData(data, relativePath: path, extension: ext))
                }
            } catch {
                parseFailures += 1
            }
        }

        guard readableEntries > 0 else {
            throw ImportError.noReadableEntries
        }
        let result = dedupe(all)
        if result.isEmpty && parseFailures > 0 {
            throw ImportError.noUsableRecords
        }
        return result
    }

    private func importDirectory(_ root: URL) throws -> [KnowledgeRecord] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var all: [KnowledgeRecord] = []
        for case let file as URL in e {
            let ext = file.pathExtension.lowercased()
            let relative = file.path.replacingOccurrences(of: root.path, with: "")
            if ext == "json" {
                all += (try? parseJSON(file, relativePath: relative)) ?? []
            } else if ["txt","md","csv","tsv","html","htm","xml"].contains(ext) {
                all += (try? parseTextFile(file, relativePath: relative)) ?? []
            }
        }
        return dedupe(all)
    }

    private func parseJSON(_ file: URL, relativePath: String) throws -> [KnowledgeRecord] {
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        return try parseJSONData(data, relativePath: relativePath)
    }

    private func parseJSONData(_ data: Data, relativePath: String) throws -> [KnowledgeRecord] {
        guard !data.isEmpty else { return [] }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            var output: [KnowledgeRecord] = []
            walk(obj, path: relativePath, output: &output)
            if output.isEmpty, let raw = String(data: data, encoding: .utf8), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(textRecord(raw, path: relativePath, index: 0))
            }
            return output
        } catch {
            if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                return [textRecord(raw, path: relativePath, index: 0)]
            }
            throw ImportError.invalidJSON(URL(fileURLWithPath: relativePath).lastPathComponent)
        }
    }

    private func parseTextFile(_ file: URL, relativePath: String) throws -> [KnowledgeRecord] {
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        return parseTextData(data, relativePath: relativePath, extension: file.pathExtension.lowercased())
    }

    private func parseTextData(_ data: Data, relativePath: String, extension ext: String) -> [KnowledgeRecord] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        if ["html","htm","xml"].contains(ext) {
            text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if lines.count <= 1 { return [textRecord(text, path: relativePath, index: 0)] }
        return lines.prefix(20_000).enumerated().map { idx, line in textRecord(line, path: relativePath, index: idx) }
    }

    private func textRecord(_ text: String, path: String, index: Int) -> KnowledgeRecord {
        let clean = decodeMeta(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return .init(id: sha("\(path)|\(index)|\(clean)"), source: sourceName(path), kind: kindForPath(path), timestamp: nil, title: title, text: clean, metadata: ["path": path, "line": "\(index + 1)"])
    }

    private func walk(_ value: Any, path: String, output: inout [KnowledgeRecord]) {
        if let dict = value as? [String:Any] {
            // Instagram/Facebook message exports use one thread object with a messages array.
            // Parse each message exactly once instead of recursively indexing every nested URI,
            // reaction label and media field as a separate record.
            if let messages = dict["messages"] as? [[String:Any]], path.lowercased().contains("message") {
                let threadTitle = decodeMeta((dict["title"] as? String) ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                for (index, message) in messages.enumerated() {
                    appendMessage(message, threadTitle: threadTitle, path: path, index: index, output: &output)
                }
                return
            }

            let text = firstString(dict, keys: ["content","text","value","comment","title","name","username","search_query","string_list_data","description","caption"])
            let timestamp = firstDate(dict)
            let actor = firstString(dict, keys: ["sender_name","author","username","name","from"])
            if text != nil || timestamp != nil || actor != nil {
                let t = decodeMeta(text ?? "")
                let title = actor.map(decodeMeta) ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let idSeed = [path, title, t, timestamp?.timeIntervalSince1970.description ?? ""].joined(separator: "|")
                output.append(.init(id: sha(idSeed), source: sourceName(path), kind: kindForPath(path), timestamp: timestamp, title: title, text: t, metadata: ["path":path]))
            }

            // Recurse into containers only. Scalar leaf strings are deliberately not emitted as
            // standalone records; doing so turns normal Instagram exports into >100k noisy rows.
            for (key, child) in dict {
                if child is [String:Any] || child is [Any] {
                    walk(child, path: path + "/" + key, output: &output)
                }
            }
        } else if let array = value as? [Any] {
            for (idx, child) in array.enumerated() {
                if child is [String:Any] || child is [Any] {
                    walk(child, path: path + "/\(idx)", output: &output)
                }
            }
        }
    }

    private func appendMessage(_ message: [String:Any], threadTitle: String, path: String, index: Int, output: inout [KnowledgeRecord]) {
        let sender = decodeMeta((message["sender_name"] as? String) ?? threadTitle)
        let timestamp = firstDate(message)
        let text = decodeMeta(messageText(message))
        guard !sender.isEmpty || !text.isEmpty || timestamp != nil else { return }

        let seed = [path, "message", "\(index)", sender, text, timestamp?.timeIntervalSince1970.description ?? ""].joined(separator: "|")
        output.append(.init(
            id: sha(seed),
            source: "Instagram",
            kind: .message,
            timestamp: timestamp,
            title: sender.isEmpty ? threadTitle : sender,
            text: text,
            metadata: ["path": path, "thread": threadTitle, "message_index": "\(index)"]
        ))
    }

    private func messageText(_ message: [String:Any]) -> String {
        if let content = message["content"] as? String, !content.isEmpty { return content }
        if let share = message["share"] as? [String:Any] {
            if let link = share["link"] as? String, !link.isEmpty { return "Shared: \(link)" }
            if let text = share["share_text"] as? String, !text.isEmpty { return text }
        }
        if let photos = message["photos"] as? [Any], !photos.isEmpty { return "[\(photos.count) photo\(photos.count == 1 ? "" : "s")]" }
        if let videos = message["videos"] as? [Any], !videos.isEmpty { return "[\(videos.count) video\(videos.count == 1 ? "" : "s")]" }
        if let audio = message["audio_files"] as? [Any], !audio.isEmpty { return "[\(audio.count) audio message\(audio.count == 1 ? "" : "s")]" }
        if let gifs = message["gifs"] as? [Any], !gifs.isEmpty { return "[GIF]" }
        if message["sticker"] != nil { return "[Sticker]" }
        return ""
    }

    private func firstString(_ d: [String:Any], keys: [String]) -> String? {
        for k in keys {
            if let s = d[k] as? String, !s.isEmpty { return s }
            if let a = d[k] as? [[String:Any]] {
                for item in a {
                    if let s = item["value"] as? String, !s.isEmpty { return s }
                    if let s = item["name"] as? String, !s.isEmpty { return s }
                    if let s = item["text"] as? String, !s.isEmpty { return s }
                }
            }
            if let object = d[k] as? [String:Any] {
                if let s = object["value"] as? String, !s.isEmpty { return s }
                if let s = object["name"] as? String, !s.isEmpty { return s }
            }
        }
        return nil
    }

    private func firstDate(_ d: [String:Any]) -> Date? {
        for key in ["timestamp_ms","timestamp","creation_timestamp","taken_at_timestamp","time","created_at"] {
            if let n = d[key] as? NSNumber {
                var v = n.doubleValue
                if v > 10_000_000_000 { v /= 1000 }
                return Date(timeIntervalSince1970: v)
            }
            if let s = d[key] as? String {
                if let numeric = Double(s) {
                    var v = numeric
                    if v > 10_000_000_000 { v /= 1000 }
                    return Date(timeIntervalSince1970: v)
                }
                if let iso = ISO8601DateFormatter().date(from: s) { return iso }
            }
        }
        if let nested = d["string_list_data"] as? [[String:Any]] {
            for item in nested {
                if let date = firstDate(item) { return date }
            }
        }
        return nil
    }

    private func kindForPath(_ path: String) -> KnowledgeRecord.Kind {
        let p = path.lowercased()
        if p.contains("message") { return .message }
        if p.contains("comment") { return .comment }
        if p.contains("like") || p.contains("reaction") { return .reaction }
        if p.contains("follow") { return .follow }
        if p.contains("search") { return .search }
        if p.contains("saved") { return .saved }
        if p.contains("profile") { return .profile }
        if p.contains("media") || p.contains("photo") || p.contains("video") || p.contains("stor") || p.contains("reel") { return .media }
        if p.contains("post") { return .post }
        return .unknown
    }

    private func sourceName(_ path: String) -> String {
        let p = path.lowercased()
        if p.contains("instagram") || p.contains("your_instagram_activity") || p.contains("ads_information") || p.contains("connections/") || p.contains("logged_information/") || p.contains("preferences/") || p.contains("personal_information/") { return "Instagram" }
        if p.contains("messenger") { return "Messenger" }
        if p.contains("facebook") { return "Facebook" }
        return "Imported Files"
    }

    private func decodeMeta(_ s: String) -> String {
        guard let data = s.data(using: .isoLatin1), let decoded = String(data: data, encoding: .utf8), !decoded.contains("�") else { return s }
        return decoded
    }

    private func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

    private func dedupe(_ records: [KnowledgeRecord]) -> [KnowledgeRecord] {
        var seen = Set<String>()
        var result: [KnowledgeRecord] = []
        result.reserveCapacity(records.count)
        for record in records where seen.insert(record.id).inserted {
            result.append(record)
        }
        return result
    }

    enum ImportError: LocalizedError {
        case unsupported(String)
        case unzip(String)
        case invalidJSON(String)
        case noReadableEntries
        case noUsableRecords

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "Unsupported file type: \(ext). Use ZIP, JSON, TXT, CSV, HTML, XML, or a folder."
            case .unzip(let message): return "Could not open that ZIP archive: \(message)"
            case .invalidJSON(let name): return "\(name) is not valid JSON and could not be read as text."
            case .noReadableEntries: return "The ZIP opened, but NEXUS could not find readable JSON or text files inside it."
            case .noUsableRecords: return "The ZIP opened, but its supported files did not contain usable Instagram/Meta records."
            }
        }
    }
}
