import Foundation
import SwiftUI

@MainActor
final class NexusModel: ObservableObject {
    @Published var records: [KnowledgeRecord] = []
    @Published var personality = PersonalityProfile()
    @Published var connectors: [ConnectorState] = []
    @Published var activityLog: [String] = []
    @Published var question = ""
    @Published var importStatus = ""
    @Published var chatMessages: [ChatMessage] = [
        ChatMessage(role: .assistant,
                    text: "I’m NEXUS. I can answer from your local vault, explain the evidence behind patterns, summarize your interests, and analyze relationships, routines, communication, places, media and long-term themes. Import data or connect device sources, then ask naturally.",
                    evidence: [])
    ]

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
            .init(id: "google", name: "Google Workspace", symbol: "envelope.badge", mode: .oauth, status: "Connector slot", detail: "OAuth connector can be added when you provide a Google client configuration"),
            .init(id: "github", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", mode: .oauth, status: "Connector slot", detail: "OAuth connector can be added when you provide a GitHub app configuration"),
            .init(id: "files", name: "Files / iCloud Drive", symbol: "folder.fill", mode: .archive, status: "Import", detail: "ZIP, JSON, TXT, CSV, HTML and XML personal exports")
        ]
    }

    func merge(_ incoming: [KnowledgeRecord], sourceName: String) {
        guard !incoming.isEmpty else {
            importStatus = "No supported records were found in that selection. Try the original ZIP/JSON export instead of a preview or shortcut file."
            activityLog.insert("No importable records found in \(sourceName)", at: 0)
            return
        }
        var map = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        incoming.forEach { map[$0.id] = $0 }
        let before = records.count
        records = map.values.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        let added = max(0, records.count - before)
        importStatus = "Imported \(incoming.count) records (\(added) new) from \(sourceName)."
        activityLog.insert(importStatus, at: 0)
        let lower = sourceName.lowercased()
        let connectorID = lower.contains("instagram") ? "instagram" : (lower.contains("facebook") || lower.contains("messenger")) ? "facebook" : "files"
        setStatus(id: connectorID, status: "\(incoming.count) records")
        save()
    }

    func reportImportError(_ message: String) {
        importStatus = message
        activityLog.insert(message, at: 0)
    }

    func setStatus(id: String, status: String) {
        if let idx = connectors.firstIndex(where: { $0.id == id }) { connectors[idx].status = status }
    }

    func saveProfile() { save() }

    func ask() {
        let raw = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        question = ""
        chatMessages.append(ChatMessage(role: .user, text: raw, evidence: []))
        let response = answerQuestion(raw)
        chatMessages.append(ChatMessage(role: .assistant, text: response.text, evidence: response.evidence))
    }

    func clearChat() {
        chatMessages = [ChatMessage(role: .assistant, text: "Chat cleared. Your vault was not deleted.", evidence: [])]
    }

    var overallSummary: String {
        guard !records.isEmpty else {
            return "NEXUS has not learned enough from imported or connected evidence yet. Your self-assessment is available, but behavioral conclusions will stay separate until data is present."
        }
        let sources = Set(records.map(\.source)).count
        let domains = domainScores.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let strongest = domains.prefix(4).map(\.key)
        let peopleCount = peopleFrequency.count
        let dated = records.compactMap(\.timestamp).count
        var sentence = "NEXUS currently models \(records.count) records across \(sources) sources, with \(dated) time-anchored observations"
        if peopleCount > 0 { sentence += " and \(peopleCount) recurring people/contact labels" }
        sentence += "."
        if !strongest.isEmpty { sentence += " The strongest recurring interest domains are \(naturalJoin(strongest))." }
        let emerging = topKeywords(limit: 5).map(\.0)
        if !emerging.isEmpty { sentence += " High-frequency specific signals include \(naturalJoin(emerging))." }
        sentence += " These are evidence patterns, not fixed traits; confidence rises when independent sources agree."
        return sentence
    }

    var analysisSections: [AnalysisSection] {
        var out: [AnalysisSection] = []
        let sourceCount = Set(records.map(\.source)).count
        let coverageConfidence = min(1.0, Double(sourceCount) / 6.0 + min(Double(records.count) / 20_000.0, 0.35))
        out.append(.init(title: "Overall model",
                         summary: overallSummary,
                         details: ["\(records.count) normalized records", "\(sourceCount) independent sources", "\(records.compactMap(\.timestamp).count) dated observations"],
                         confidence: coverageConfidence))

        let domains = domainScores.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        if !domains.isEmpty {
            let maxScore = Double(domains.first?.value ?? 1)
            let details = domains.prefix(10).map { "\($0.key): \($0.value) matched signals" }
            out.append(.init(title: "Interests & recurring domains",
                             summary: "Your strongest repeated domains are \(naturalJoin(domains.prefix(5).map(\.key))). This combines explicit words, searches, posts, messages, saved items, media titles and activity labels.",
                             details: details,
                             confidence: min(0.95, 0.45 + maxScore / 80.0)))
        }

        let topPeople = peopleFrequency.prefix(8)
        if !topPeople.isEmpty {
            out.append(.init(title: "People & social attention",
                             summary: "The vault contains recurring social evidence around \(naturalJoin(topPeople.prefix(5).map { $0.0 })). Frequency means presence in your data, not relationship quality.",
                             details: topPeople.map { "\($0.0): \($0.1) signals" },
                             confidence: min(0.92, 0.45 + Double(topPeople.first?.1 ?? 0) / 100.0)))
        }

        let kindCounts = Dictionary(grouping: records, by: \.kind).mapValues(\.count).sorted { $0.value > $1.value }
        if !kindCounts.isEmpty {
            out.append(.init(title: "Behavioral footprint",
                             summary: "The largest observable activity types are \(naturalJoin(kindCounts.prefix(5).map { $0.key.rawValue })). This describes what the current dataset captures most strongly.",
                             details: kindCounts.prefix(12).map { "\($0.key.rawValue.capitalized): \($0.value)" },
                             confidence: min(0.9, 0.4 + Double(records.count) / 10_000.0)))
        }

        let messages = records.filter { $0.kind == .message }
        if !messages.isEmpty {
            let averageLength = messages.map { $0.text.count }.reduce(0,+) / max(messages.count, 1)
            let questionRate = Double(messages.filter { $0.text.contains("?") }.count) / Double(messages.count)
            let exclaimRate = Double(messages.filter { $0.text.contains("!") }.count) / Double(messages.count)
            out.append(.init(title: "Communication style",
                             summary: "Across \(messages.count) message records, your available conversation corpus averages about \(averageLength) characters per captured message. Question and emphasis markers provide a rough signal of conversational style.",
                             details: ["Question-marker rate: \(Int(questionRate * 100))%", "Exclamation-marker rate: \(Int(exclaimRate * 100))%", "Average captured message length: \(averageLength) characters"],
                             confidence: min(0.9, 0.35 + Double(messages.count) / 5000.0)))
        }

        let dated = records.compactMap { r -> (Date, KnowledgeRecord)? in r.timestamp.map { ($0, r) } }
        if !dated.isEmpty {
            let calendar = Calendar.current
            let byHour = Dictionary(grouping: dated, by: { calendar.component(.hour, from: $0.0) }).mapValues(\.count)
            let peak = byHour.max(by: { $0.value < $1.value })
            let byWeekday = Dictionary(grouping: dated, by: { calendar.component(.weekday, from: $0.0) }).mapValues(\.count)
            let peakDay = byWeekday.max(by: { $0.value < $1.value })
            let dayName = peakDay.map { calendar.weekdaySymbols[$0.key - 1] } ?? "Unknown"
            out.append(.init(title: "Temporal patterns",
                             summary: "Your current evidence is most concentrated around \(peak.map { String(format: "%02d:00", $0.key) } ?? "unknown time") and \(dayName). This may reflect export coverage as much as true behavior.",
                             details: ["Peak hour: \(peak.map { String(format: "%02d:00 (%d records)", $0.key, $0.value) } ?? "Unknown")", "Peak weekday: \(dayName)"],
                             confidence: min(0.85, 0.3 + Double(dated.count) / 8000.0)))
        }

        let places = locationLabels
        if !places.isEmpty {
            out.append(.init(title: "Places & mobility",
                             summary: "Location-related evidence currently contains \(places.count) distinct place or coordinate labels.",
                             details: Array(places.prefix(10)),
                             confidence: min(0.85, 0.35 + Double(places.count) / 40.0)))
        }

        let novel = topKeywords(limit: 12).map { "\($0.0): \($0.1) mentions" }
        if !novel.isEmpty {
            out.append(.init(title: "Emerging specific themes",
                             summary: "These repeated terms are not limited to predefined categories and help NEXUS discover unexpected interests, projects, names or recurring concepts.",
                             details: novel,
                             confidence: min(0.9, 0.35 + Double(records.count) / 12_000.0)))
        }
        return out
    }

    var insights: [InsightCard] {
        let sources = Set(records.map(\.source))
        let dated = records.compactMap(\.timestamp)
        let messages = records.filter { $0.kind == .message }.count
        let social = records.filter { [.message,.follow,.reaction,.comment,.contact].contains($0.kind) }.count
        let interests = domainScores.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(5)
        return [
            .init(title: "Knowledge coverage", value: "\(sources.count) sources", explanation: "Independent evidence sources represented in your vault.", evidence: Array(sources).sorted()),
            .init(title: "Timeline depth", value: dated.isEmpty ? "No dated data" : "\(dated.count) dated", explanation: "Records that can be placed on your life timeline.", evidence: dated.prefix(5).map { $0.formatted(date: .abbreviated, time: .omitted) }),
            .init(title: "Communication evidence", value: "\(messages) messages", explanation: "Message records available for communication and relationship analysis.", evidence: records.filter { $0.kind == .message }.prefix(5).map { $0.source + ": " + String($0.text.prefix(120)) }),
            .init(title: "Social graph evidence", value: "\(social) signals", explanation: "Contacts, follows, comments, reactions and messages supporting relationship analysis.", evidence: records.filter { [.message,.follow,.reaction,.comment,.contact].contains($0.kind) }.prefix(5).map(\.title)),
            .init(title: "Interest model", value: interests.first?.key ?? "Learning", explanation: "Top evidence-weighted recurring domains detected across text and activity records.", evidence: interests.map { "\($0.key): \($0.value) signals" })
        ]
    }

    var knowledgeGraph: KnowledgeGraph {
        var nodes: [KnowledgeGraphNode] = [
            .init(id: "self", label: "You", category: .selfNode, weight: 1.0, detail: "Central personal model")
        ]
        var edges: [KnowledgeGraphEdge] = []

        let sources = Dictionary(grouping: records, by: \.source).mapValues(\.count).sorted { $0.value > $1.value }.prefix(8)
        for (name, count) in sources {
            let id = "source:\(name)"
            nodes.append(.init(id: id, label: name, category: .source, weight: normalizedWeight(count), detail: "\(count) records"))
            edges.append(.init(id: "self>\(id)", from: "self", to: id, weight: normalizedWeight(count), label: "source"))
        }

        let interests = domainScores.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(9)
        for (name, score) in interests {
            let id = "interest:\(name)"
            nodes.append(.init(id: id, label: name, category: .interest, weight: normalizedWeight(score), detail: "\(score) matched signals"))
            edges.append(.init(id: "self>\(id)", from: "self", to: id, weight: normalizedWeight(score), label: "interest"))
            for (sourceName, sourceCount) in sources.prefix(5) {
                let co = domainScore(name, in: records.filter { $0.source == sourceName })
                if co > 0 {
                    edges.append(.init(id: "source:\(sourceName)>\(id)", from: "source:\(sourceName)", to: id, weight: min(1, Double(co) / Double(max(sourceCount,1))), label: "evidence"))
                }
            }
        }

        for (name, count) in peopleFrequency.prefix(8) {
            let id = "person:\(name)"
            nodes.append(.init(id: id, label: name, category: .person, weight: normalizedWeight(count), detail: "\(count) social signals"))
            edges.append(.init(id: "self>\(id)", from: "self", to: id, weight: normalizedWeight(count), label: "person"))
        }

        let kinds = Dictionary(grouping: records, by: \.kind).mapValues(\.count).sorted { $0.value > $1.value }.prefix(6)
        for (kind, count) in kinds {
            let id = "activity:\(kind.rawValue)"
            nodes.append(.init(id: id, label: kind.rawValue.capitalized, category: .activity, weight: normalizedWeight(count), detail: "\(count) records"))
            edges.append(.init(id: "self>\(id)", from: "self", to: id, weight: normalizedWeight(count), label: "activity"))
        }
        return KnowledgeGraph(nodes: nodes, edges: edges)
    }

    private func answerQuestion(_ raw: String) -> (text: String, evidence: [String]) {
        let lower = raw.lowercased()
        if records.isEmpty {
            if lower.contains("personality") || lower.contains("trait") || lower.contains("mbti") {
                let mbti = personality.mbti.isEmpty ? "No MBTI label is saved" : "Saved MBTI: \(personality.mbti.uppercased())"
                return ("I only have your self-assessment right now. Openness \(Int(personality.openness)), conscientiousness \(Int(personality.conscientiousness)), extraversion \(Int(personality.extraversion)), agreeableness \(Int(personality.agreeableness)), emotional sensitivity \(Int(personality.neuroticism)). \(mbti). Import behavioral data before treating any inference as evidence-backed.", [])
            }
            return ("I can chat now, but your vault is empty. Ask me how NEXUS works, edit your self-assessment in Analysis, or import a Meta archive / files / device data. Once data is present I’ll answer from matching evidence and show the supporting records.", [])
        }

        if lower.contains("overall") || lower.contains("who am i") || lower.contains("analyze me") || lower.contains("analysis") {
            return (overallSummary + " Open Analysis for the detailed breakdown and confidence by domain.", analysisSections.prefix(3).flatMap { $0.details.prefix(2) })
        }
        if lower.contains("interest") || lower.contains("hobby") || lower.contains("topic") || lower.contains("like") {
            let domains = domainScores.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(7)
            let terms = topKeywords(limit: 8)
            let text = "Your strongest recurring interest domains are \(naturalJoin(domains.map(\.key))). More specific repeated signals include \(naturalJoin(terms.map(\.0))). The ranking uses repetition across your imported text/activity, so it changes as the vault grows."
            return (text, domains.map { "\($0.key): \($0.value) domain signals" } + terms.map { "\($0.0): \($0.1) mentions" })
        }
        if lower.contains("people") || lower.contains("relationship") || lower.contains("friend") || lower.contains("social") || lower.contains("person") {
            let people = peopleFrequency.prefix(8)
            guard !people.isEmpty else { return ("I have social records, but not enough stable person labels to rank recurring people yet.", []) }
            return ("The most recurrent people/contact labels in the current vault are \(naturalJoin(people.map { $0.0 })). This measures visibility in the data—not closeness, sentiment or relationship quality.", people.map { "\($0.0): \($0.1) signals" })
        }
        if lower.contains("communication") || lower.contains("chat style") || lower.contains("message") {
            if let section = analysisSections.first(where: { $0.title == "Communication style" }) { return (section.summary, section.details) }
        }
        if lower.contains("routine") || lower.contains("time") || lower.contains("active") || lower.contains("schedule") {
            if let section = analysisSections.first(where: { $0.title == "Temporal patterns" }) { return (section.summary, section.details) }
        }
        if lower.contains("source") || lower.contains("data") || lower.contains("coverage") {
            let counts = Dictionary(grouping: records, by: \.source).mapValues(\.count).sorted { $0.value > $1.value }
            return ("Your vault contains \(records.count) records from \(counts.count) sources. The largest sources are \(naturalJoin(counts.prefix(6).map { $0.key })).", counts.prefix(10).map { "\($0.key): \($0.value)" })
        }

        let queryTerms = tokenize(raw).filter { !Self.stopwords.contains($0) }
        let ranked = records.compactMap { record -> (KnowledgeRecord, Int)? in
            let hay = tokenize(record.title + " " + record.text + " " + record.source).reduce(into: [:]) { (d: inout [String:Int], word) in d[word, default: 0] += 1 }
            let score = queryTerms.reduce(0) { $0 + (hay[$1] ?? 0) * 3 } + (queryTerms.contains(record.kind.rawValue) ? 2 : 0)
            return score > 0 ? (record, score) : nil
        }.sorted { $0.1 > $1.1 }.prefix(8)

        if ranked.isEmpty {
            return ("I couldn’t find strong direct evidence for that wording. I can still analyze your overall model, interests, people, communication style, routines, sources and recurring themes. Try naming a topic or person exactly as it appears in your data.", [])
        }
        let evidence = ranked.map { item in
            let r = item.0
            let body = r.text.isEmpty ? r.title : r.text
            return "\(r.source) • \(r.kind.rawValue): \(String(body.prefix(180)))"
        }
        let sourceNames = Array(Set(ranked.map { $0.0.source })).sorted()
        let kinds = Array(Set(ranked.map { $0.0.kind.rawValue })).sorted()
        let summaryTerms = frequentTerms(in: ranked.map { $0.0 }, limit: 6).map(\.0)
        var text = "I found \(ranked.count) strongly matching records across \(naturalJoin(sourceNames)). They are mostly \(naturalJoin(kinds))."
        if !summaryTerms.isEmpty { text += " Recurring terms around this question include \(naturalJoin(summaryTerms))." }
        text += " The evidence below is the basis for this answer."
        return (text, evidence)
    }

    private var domainScores: [String:Int] {
        var out: [String:Int] = [:]
        for domain in Self.domainLexicon.keys { out[domain] = domainScore(domain, in: records) }
        return out
    }

    private func domainScore(_ domain: String, in records: [KnowledgeRecord]) -> Int {
        guard let terms = Self.domainLexicon[domain] else { return 0 }
        var score = 0
        for r in records.prefix(30_000) {
            let words = Set(tokenize(r.title + " " + r.text))
            for term in terms where words.contains(term) { score += 1 }
        }
        return score
    }

    private var peopleFrequency: [(String, Int)] {
        var counts: [String:Int] = [:]
        for r in records where [.message,.contact,.follow,.comment,.reaction].contains(r.kind) {
            let name = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.count >= 2 && name.count <= 80 && !name.lowercased().contains("message") && !name.lowercased().contains("profile") {
                counts[name, default: 0] += 1
            }
        }
        return counts.sorted { a, b in a.value == b.value ? a.key < b.key : a.value > b.value }
    }

    private var locationLabels: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in records where r.kind == .location {
            let label = r.text.isEmpty ? r.title : r.text
            if !label.isEmpty && seen.insert(label).inserted { out.append(label) }
        }
        return out
    }

    private func topKeywords(limit: Int) -> [(String, Int)] { frequentTerms(in: Array(records.prefix(20_000)), limit: limit) }

    private func frequentTerms(in input: [KnowledgeRecord], limit: Int) -> [(String, Int)] {
        var counts: [String:Int] = [:]
        for r in input {
            for word in tokenize(r.title + " " + r.text) where word.count > 3 && !Self.stopwords.contains(word) {
                counts[word, default: 0] += 1
            }
        }
        return Array(counts.sorted { a, b in a.value == b.value ? a.key < b.key : a.value > b.value }.prefix(limit))
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private func normalizedWeight(_ count: Int) -> Double {
        min(1.0, 0.25 + log10(Double(max(count, 1)) + 1.0) / 4.0)
    }

    private func naturalJoin<S: Sequence>(_ sequence: S) -> String where S.Element == String {
        let items = Array(sequence)
        if items.isEmpty { return "none yet" }
        if items.count == 1 { return items[0] }
        if items.count == 2 { return items[0] + " and " + items[1] }
        return items.dropLast().joined(separator: ", ") + ", and " + items.last!
    }

    private func save() {
        if let d = try? JSONEncoder().encode(records) { try? d.write(to: vaultURL, options: .atomic) }
        if let d = try? JSONEncoder().encode(personality) { try? d.write(to: profileURL, options: .atomic) }
    }

    private func load() {
        if let d = try? Data(contentsOf: vaultURL), let v = try? JSONDecoder().decode([KnowledgeRecord].self, from: d) { records = v }
        if let d = try? Data(contentsOf: profileURL), let v = try? JSONDecoder().decode(PersonalityProfile.self, from: d) { personality = v }
    }

    private static let stopwords: Set<String> = [
        "the","and","that","this","with","from","your","you","for","are","was","were","have","has","had","not","but","about","http","https","www","com","into","then","than","there","their","they","them","would","could","should","what","when","where","which","while","also","just","more","some","very","been","being","will","shall","can","cant","dont","does","did","its","our","ours","his","her","hers","she","him","who","why","how","message","messages","profile","facebook","instagram","messenger"
    ]

    private static let domainLexicon: [String:Set<String>] = [
        "Software & technology": ["software","programming","code","coding","developer","swift","ios","github","api","python","java","javascript","xcode","ai","machine","model","algorithm","app","apps","computer","data"],
        "Music & piano": ["music","piano","song","songs","chord","chords","melody","harmony","scale","arpeggio","classical","spotify","artist","album","track","rhythm"],
        "Finance & investing": ["finance","money","saving","savings","bank","credit","card","interest","investment","investing","crypto","bitcoin","ethereum","eth","stock","stocks","budget","salary","cash"],
        "Travel & places": ["travel","trip","flight","hotel","airport","taiwan","japan","boracay","manila","taipei","train","mrt","tour","visa","beach","destination"],
        "Learning & ideas": ["learn","learning","course","study","school","university","math","calculus","algebra","logic","philosophy","psychology","science","book","research","theory"],
        "Games & interactive media": ["game","games","gaming","mlbb","pokemon","monopoly","character","build","mobile","anime"],
        "Creativity & design": ["design","art","creative","create","writing","poem","story","aesthetic","image","drawing","portfolio","visual","idea","ideas"],
        "Health & wellbeing": ["health","sleep","exercise","workout","food","diet","heart","steps","energy","stress","wellbeing","medicine"],
        "Food & dining": ["food","restaurant","eat","eating","mango","coffee","meal","breakfast","lunch","dinner","recipe","taste"],
        "Relationships & social life": ["friend","friends","family","relationship","people","person","social","chat","conversation","team","workmate","colleague"]
    ]
}
