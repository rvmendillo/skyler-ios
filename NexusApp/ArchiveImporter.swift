import Foundation
import ZIPFoundation
import CryptoKit

struct MetaArchiveImporter {
    func importURL(_ url: URL) throws -> [KnowledgeRecord] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "zip" { return try importZip(url) }
        if url.pathExtension.lowercased() == "json" { return try parseJSON(url, relativePath: url.lastPathComponent) }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return try importDirectory(url) }
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    private func importZip(_ url: URL) throws -> [KnowledgeRecord] {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-meta-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.unzipItem(at: url, to: temp)
        return try importDirectory(temp)
    }

    private func importDirectory(_ root: URL) throws -> [KnowledgeRecord] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var all: [KnowledgeRecord] = []
        for case let file as URL in e where file.pathExtension.lowercased() == "json" {
            all += (try? parseJSON(file, relativePath: file.path.replacingOccurrences(of: root.path, with: ""))) ?? []
        }
        return dedupe(all)
    }

    private func parseJSON(_ file: URL, relativePath: String) throws -> [KnowledgeRecord] {
        let data = try Data(contentsOf: file)
        let obj = try JSONSerialization.jsonObject(with: data)
        var output: [KnowledgeRecord] = []
        walk(obj, path: relativePath, output: &output)
        return output
    }

    private func walk(_ value: Any, path: String, output: inout [KnowledgeRecord]) {
        if let dict = value as? [String:Any] {
            let text = firstString(dict, keys: ["content","text","value","comment","title","name","username","search_query","string_list_data"])
            let timestamp = firstDate(dict)
            let actor = firstString(dict, keys: ["sender_name","author","username","name"])
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
        }
    }

    private func firstString(_ d: [String:Any], keys: [String]) -> String? {
        for k in keys {
            if let s = d[k] as? String, !s.isEmpty { return s }
            if let a = d[k] as? [[String:Any]], let s = a.first?["value"] as? String { return s }
        }
        return nil
    }

    private func firstDate(_ d: [String:Any]) -> Date? {
        for key in ["timestamp_ms","timestamp","creation_timestamp","taken_at_timestamp","time"] {
            if let n = d[key] as? NSNumber {
                var v = n.doubleValue
                if v > 10_000_000_000 { v /= 1000 }
                return Date(timeIntervalSince1970: v)
            }
        }
        return nil
    }

    private func sourceName(_ path: String) -> String {
        let p = path.lowercased()
        if p.contains("instagram") { return "Instagram" }
        if p.contains("messenger") || p.contains("message") { return "Messenger" }
        if p.contains("facebook") { return "Facebook" }
        return "Meta Archive"
    }

    private func decodeMeta(_ s: String) -> String {
        guard let data = s.data(using: .isoLatin1), let decoded = String(data: data, encoding: .utf8), !decoded.contains("�") else { return s }
        return decoded
    }

    private func sha(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func dedupe(_ records: [KnowledgeRecord]) -> [KnowledgeRecord] { Array(Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }).values) }
}
