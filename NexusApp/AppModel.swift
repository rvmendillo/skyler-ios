import Foundation
import SwiftUI

@MainActor
final class NexusModel: ObservableObject {
    @Published var records: [KnowledgeRecord] = []
    @Published var personality = PersonalityProfile()
    @Published var connectors: [ConnectorState] = []
    @Published var activityLog: [String] = []
    @Published var question = ""
    @Published var answer = "Connect data sources or import an archive, then ask NEXUS about patterns in your life."

    private let vaultURL: URL
    private let profileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        vaultURL = base.appendingPathComponent("nexus-vault.json")
        profileURL = base.appendingPathComponent("personality.json")
        connectors = Self.defaultConnectors
        load()
    }

    static var defaultConnectors: [ConnectorState] {
        [
            .init(id: "contacts", name: "Contacts", symbol: "person.2.fill", mode: .native, status: "Not connected", detail: "Relationship graph and contact metadata"),
            .init(id: "calendar", name: "Calendar", symbol: "calendar", mode: .native, status: "Not connected", detail: "Events, routines and time allocation"),
            .init(id: "reminders", name: "Reminders", symbol: "checklist", mode: .native, status: "Not connected", detail: "Goals, tasks and planning patterns"),
            .init(id: "photos", name: "Photos", symbol: "photo.on.rectangle", mode: .native, status: "Not connected", detail: "Photo metadata and life timeline"),
            .init(id: "health", name: "Apple Health", symbol: "heart.fill", mode: .native, status: "Not connected", detail: "Authorized health and activity metrics"),
            .init(id: "location", name: "Location", symbol: "location.fill", mode: .native, status: "Not connected", detail: "Places and travel context while NEXUS is open"),
            .init(id: "music", name: "Music Library", symbol: "music.note.list", mode: .native, status: "Not connected", detail: "Listening-library metadata"),
            .init(id: "instagram", name: "Instagram", symbol: "camera.circle.fill", mode: .archive, status: "Import ZIP/JSON", detail: "Messages, follows, posts, reactions, searches and more"),
            .init(id: "facebook", name: "Facebook / Messenger", symbol: "bubble.left.and.bubble.right.fill", mode: .archive, status: "Import ZIP/JSON", detail: "Meta account archive and Messenger conversations"),
            .init(id: "google", name: "Google Workspace", symbol: "envelope.badge", mode: .oauth, status: "Connector slot", detail: "Gmail, Drive and Calendar via your own OAuth client"),
            .init(id: "github", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", mode: .oauth, status: "Connector slot", detail: "Repositories, commits, issues and pull requests"),
            .init(id: "files", name: "Files / iCloud Drive", symbol: "folder.fill", mode: .archive, status: "Import", detail: "JSON and text-based personal archives")
        ]
    }

    func merge(_ incoming: [KnowledgeRecord], sourceName: String) {
        var map = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        incoming.forEach { map[$0.id] = $0 }
        records = map.values.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        activityLog.insert("Imported \(incoming.count) records from \(sourceName)", at: 0)
        setStatus(id: sourceName.lowercased().contains("instagram") ? "instagram" : sourceName.lowercased().contains("facebook") ? "facebook" : "files", status: "\(incoming.count) records")
        save()
    }

    func setStatus(id: String, status: String) {
        if let idx = connectors.firstIndex(where: { $0.id == id }) { connectors[idx].status = status }
    }

    func saveProfile() { save() }

    func ask() {
        let q = question.lowercased()
        guard !records.isEmpty else { answer = "I need evidence first. Connect phone data or import an Instagram/Facebook archive."; return }
        if q.contains("person") || q.contains("trait") {
            answer = "Your current self-assessment leans highest in conscientiousness and openness. Evidence-backed behavioral estimates will strengthen as more sources are connected."
        } else if q.contains("relationship") || q.contains("people") {
            let messages = records.filter { $0.kind == .message || $0.kind == .contact }
            answer = "I found \(messages.count) relationship-related records across your connected data. Open Insights to inspect the evidence rather than relying on a single score."
        } else if q.contains("interest") || q.contains("topic") {
            let words = keywordSummary()
            answer = words.isEmpty ? "I do not have enough text yet to rank recurring topics." : "Your recurring text signals currently include: \(words.joined(separator: ", "))."
        } else {
            answer = "Across \(records.count) normalized records from \(Set(records.map(\.source)).count) sources, NEXUS can trace patterns by time, source and evidence. Try asking about interests, personality, relationships or routines."
        }
    }

    var insights: [InsightCard] {
        let sources = Set(records.map(\.source))
        let dated = records.compactMap(\.timestamp)
        let messages = records.filter { $0.kind == .message }.count
        let social = records.filter { [.message,.follow,.reaction,.comment,.contact].contains($0.kind) }.count
        return [
            .init(title: "Knowledge coverage", value: "\(sources.count) sources", explanation: "Independent evidence sources currently represented in your vault.", evidence: Array(sources).sorted()),
            .init(title: "Timeline depth", value: dated.isEmpty ? "No dated data" : "\(dated.count) dated records", explanation: "Records that can be placed on your life timeline.", evidence: dated.prefix(3).map { $0.formatted(date: .abbreviated, time: .omitted) }),
            .init(title: "Communication evidence", value: "\(messages) messages", explanation: "Message records available for communication-style analysis.", evidence: records.filter { $0.kind == .message }.prefix(3).map { $0.source + ": " + String($0.text.prefix(80)) }),
            .init(title: "Social graph evidence", value: "\(social) signals", explanation: "Contacts, follows, comments, reactions and messages that can support relationship analysis.", evidence: records.filter { [.message,.follow,.reaction,.comment,.contact].contains($0.kind) }.prefix(3).map(\.title))
        ]
    }

    private func keywordSummary() -> [String] {
        let stop: Set<String> = ["the","and","that","this","with","from","your","you","for","are","was","have","has","not","but","about","http","https","www"]
        var counts: [String:Int] = [:]
        records.prefix(5000).forEach { r in
            (r.title + " " + r.text).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 && !stop.contains($0) }.forEach { counts[$0, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(8).map(\.key)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(records) { try? d.write(to: vaultURL, options: .atomic) }
        if let d = try? JSONEncoder().encode(personality) { try? d.write(to: profileURL, options: .atomic) }
    }

    private func load() {
        if let d = try? Data(contentsOf: vaultURL), let v = try? JSONDecoder().decode([KnowledgeRecord].self, from: d) { records = v }
        if let d = try? Data(contentsOf: profileURL), let v = try? JSONDecoder().decode(PersonalityProfile.self, from: d) { personality = v }
    }
}
