import Foundation

struct KnowledgeRecord: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case message, post, comment, reaction, saved, follow, search, profile, media, event, reminder, contact, health, location, music, file, activity, note, unknown
    }
    let id: String
    let source: String
    let kind: Kind
    let timestamp: Date?
    let title: String
    let text: String
    let metadata: [String: String]
}

struct ConnectorState: Identifiable, Hashable {
    enum Mode: String { case native = "On-device", archive = "Archive", oauth = "OAuth" }
    let id: String
    let name: String
    let symbol: String
    let mode: Mode
    var status: String
    var detail: String
}

struct PersonalityProfile: Codable, Equatable {
    var openness: Double = 70
    var conscientiousness: Double = 75
    var extraversion: Double = 50
    var agreeableness: Double = 65
    var neuroticism: Double = 40
    var mbti: String = ""
}

struct InsightCard: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let value: String
    let explanation: String
    let evidence: [String]
}

struct AnalysisSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let summary: String
    let details: [String]
    let confidence: Double
}

struct ChatMessage: Identifiable, Hashable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    let evidence: [String]
    let timestamp = Date()
}

struct KnowledgeGraphNode: Identifiable, Hashable {
    enum Category: String { case selfNode, interest, person, source, activity, place, theme }
    let id: String
    let label: String
    let category: Category
    let weight: Double
    let detail: String
}

struct KnowledgeGraphEdge: Identifiable, Hashable {
    let id: String
    let from: String
    let to: String
    let weight: Double
    let label: String
}

struct KnowledgeGraph: Hashable {
    let nodes: [KnowledgeGraphNode]
    let edges: [KnowledgeGraphEdge]
}
