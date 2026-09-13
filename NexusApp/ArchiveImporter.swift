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

    private func importZip(_ url: URL) throws -> [KnowledgeRecord] {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try FileManager.default.unzipItem(at: url, to: temp)
        } catch {
            throw ImportError.unzip(error.localizedDescription)
        }
        return try importDirectory(temp)
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
        let data = try Data(contentsOf: file)
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
            throw ImportError.invalidJSON(file.lastPathComponent)
        }
    }

    private func parseTextFile(_ file: URL, relativePath: String) throws -> [KnowledgeRecord] {
        let data = try Data(contentsOf: file)
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        if ["html","htm","xml"].contains(file.pathExtension.lowercased()) {
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
        return .init(id: sha("\(path)|\(index)|\(clean)"), source: sourceName(path), kind: .file, timestamp: nil, title: title, text: clean, metadata: ["path": path, "line": "\(index + 1)"])
    }

    private func walk(_ value: Any, path: String, output: inout [KnowledgeRecord]) {
        if let dict = value as? [String:Any] {
            let text = firstString(dict, keys: ["content","text","value","comment","title","name","username","search_query","string_list_data","description","caption"])
            let timestamp = firstDate(dict)
            let actor = firstString(dict, keys: ["sender_name","author","username","name","from"])
            let pathLower = path.lowercased()
            let kind: KnowledgeRecord.Kind = pathLower.contains("message") || dict["sender_name"] != nil ? .message : pathLower.contains("comment") ? .comment : pathLower.contains("like") || pathLower.contains("reaction") ? .reaction : pathLower.contains("follow") ? .follow : pathLower.contains("search") ? .search : pathLower.contains("saved") ? .saved : pathLower.contains("profile") ? .profile : pathLower.contains("media") || pathLower.contains("photo") || pathLower.contains("video") ? .media : pathLower.contains("post") ? .post : .unknown
            if text != nil || timestamp != nil || actor != nil {
                let t = decodeMeta(text ?? "")
                let title = actor.map(decodeMeta) ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let idSeed = [path, title, t, timestamp?.timeIntervalSince1970.description ?? ""].joined(separator: "|")
                output.append(.init(id: sha(idSeed), source: sourceName(path), kind: kind, timestamp: timestamp, title: title, text: t, metadata: ["path":path]))
            }
            dict.forEach { key, child in walk(child, path: path + "/" + key, output: &output) }
        } else if let array = value as? [Any] {
            array.enumerated().forEach { idx, child in walk(child, path: path + "/\(idx)", output: &output) }
        } else if let string = value as? String, string.count > 2 {
            output.append(textRecord(string, path: path, index: output.count))
        }
    }

    private func firstString(_ d: [String:Any], keys: [String]) -> String? {
        for k in keys {
            if let s = d[k] as? String, !s.isEmpty { return s }
            if let a = d[k] as? [[String:Any]], let s = a.first?["value"] as? String { return s }
            if let object = d[k] as? [String:Any], let s = object["value"] as? String { return s }
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
        return nil
    }

    private func sourceName(_ path: String) -> String {
        let p = path.lowercased()
        if p.contains("instagram") { return "Instagram" }
        if p.contains("messenger") || p.contains("message") { return "Messenger" }
        if p.contains("facebook") { return "Facebook" }
        return "Imported Files"
    }

    private func decodeMeta(_ s: String) -> String {
        guard let data = s.data(using: .isoLatin1), let decoded = String(data: data, encoding: .utf8), !decoded.contains("�") else { return s }
        return decoded
    }

    private func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func dedupe(_ records: [KnowledgeRecord]) -> [KnowledgeRecord] { Array(Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }).values) }

    enum ImportError: LocalizedError {
        case unsupported(String)
        case unzip(String)
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext): return "Unsupported file type: \(ext). Use ZIP, JSON, TXT, CSV, HTML, XML, or a folder."
            case .unzip(let message): return "Could not open that ZIP archive: \(message)"
            case .invalidJSON(let name): return "\(name) is not valid JSON and could not be read as text."
            }
        }
    }
}
