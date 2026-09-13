import Foundation

struct NexusCountItem: Identifiable, Hashable {
    let id: String
    let label: String
    let count: Int
}

struct NexusCanonicalSignal: Identifiable, Hashable {
    enum ActionFamily: String, CaseIterable, Hashable {
        case communicate = "Communicate"
        case create = "Create"
        case consume = "Consume"
        case explore = "Explore"
        case save = "Save"
        case connect = "Connect"
        case plan = "Plan"
        case move = "Move"
        case wellbeing = "Wellbeing"
        case organize = "Organize"
        case other = "Other"
    }

    enum Modality: String, CaseIterable, Hashable {
        case text = "Text"
        case visual = "Visual"
        case audio = "Audio"
        case event = "Event"
        case location = "Location"
        case health = "Health"
        case social = "Social"
        case file = "File"
        case other = "Other"
    }

    let id: String
    let recordID: String
    let source: String
    let action: ActionFamily
    let modality: Modality
    let timestamp: Date?
    let subject: String
    let topics: [String]
    let entities: [String]
    let place: String?
    let evidenceWeight: Double
}

struct NexusStandardizedPattern: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Hashable {
        case persistent = "Persistent"
        case crossSource = "Cross-source"
        case recurring = "Recurring"
        case emerging = "Emerging"
        case fading = "Fading"
        case social = "Social"
        case creative = "Creative"
        case exploratory = "Exploratory"
        case planning = "Planning"
    }

    let id: String
    let kind: Kind
    let label: String
    let summary: String
    let score: Double
    let sourceBreadth: Int
    let recordCount: Int
    let timeSpanDays: Int
    let actionLabels: [String]
    let evidence: [String]
}

struct NexusStandardizationReport: Hashable {
    let signalCount: Int
    let sourceCount: Int
    let datedSignalCount: Int
    let dominantActions: [NexusCountItem]
    let dominantModalities: [NexusCountItem]
    let patterns: [NexusStandardizedPattern]
    let universalCharacteristics: [NexusStandardizedPattern]
    let caveats: [String]
}

enum NexusStandardizationEngine {
    private static let stopWords: Set<String> = [
        "this","that","these","those","with","from","have","your","you","they","them","their","there","about","into","than","then","were","been","what","when","where","which","would","could","should","just","also","very","http","https","www","com","message","messages","instagram","facebook","messenger","profile","photo","video","image","file","files","content","shared","sent"
    ]

    static func standardize(_ records: [KnowledgeRecord]) -> [NexusCanonicalSignal] {
        Array(records.prefix(60_000)).map { record in
            let combined = (record.title + " " + record.text).trimmingCharacters(in: .whitespacesAndNewlines)
            return NexusCanonicalSignal(
                id: "signal:\(record.id)",
                recordID: record.id,
                source: canonicalSource(record.source),
                action: actionFamily(record.kind),
                modality: modality(record),
                timestamp: record.timestamp,
                subject: canonicalSubject(record),
                topics: topTerms(combined, limit: 8),
                entities: canonicalEntities(record),
                place: canonicalPlace(record),
                evidenceWeight: evidenceWeight(record)
            )
        }
    }

    static func report(_ records: [KnowledgeRecord]) -> NexusStandardizationReport {
        let signals = standardize(records)
        let sourceCount = Set(signals.map(\.source)).count
        let actions = Dictionary(grouping: signals, by: \.action).mapValues(\.count)
            .sorted { $0.value > $1.value }
            .map { NexusCountItem(id: $0.key.rawValue, label: $0.key.rawValue, count: $0.value) }
        let modalities = Dictionary(grouping: signals, by: \.modality).mapValues(\.count)
            .sorted { $0.value > $1.value }
            .map { NexusCountItem(id: $0.key.rawValue, label: $0.key.rawValue, count: $0.value) }
        let patterns = discoverPatterns(signals)
        let threshold = min(3, max(2, sourceCount))
        let universal = patterns.filter {
            $0.sourceBreadth >= threshold || ($0.timeSpanDays >= 365 && $0.recordCount >= 12)
        }.sorted {
            if $0.sourceBreadth == $1.sourceBreadth { return $0.score > $1.score }
            return $0.sourceBreadth > $1.sourceBreadth
        }

        var caveats = [
            "Standardization preserves the original record and provenance; it only adds a comparable signal layer.",
            "Source breadth matters more than raw count so a large single export cannot dominate by volume alone.",
            "Missing evidence means unknown, not absent in real life."
        ]
        if sourceCount <= 1 { caveats.append("Only one independent source is available, so cross-source conclusions remain provisional.") }
        return NexusStandardizationReport(signalCount: signals.count,
                                          sourceCount: sourceCount,
                                          datedSignalCount: signals.compactMap(\.timestamp).count,
                                          dominantActions: actions,
                                          dominantModalities: modalities,
                                          patterns: patterns,
                                          universalCharacteristics: Array(universal.prefix(16)),
                                          caveats: caveats)
    }

    private static func discoverPatterns(_ signals: [NexusCanonicalSignal]) -> [NexusStandardizedPattern] {
        guard !signals.isEmpty else { return [] }
        var topicSignals: [String:[NexusCanonicalSignal]] = [:]
        for signal in signals {
            for topic in Set(signal.topics.prefix(6)) { topicSignals[topic, default: []].append(signal) }
        }
        let newest = signals.compactMap(\.timestamp).max() ?? Date()
        let recentStart = Calendar.current.date(byAdding: .day, value: -90, to: newest) ?? newest
        let previousStart = Calendar.current.date(byAdding: .day, value: -180, to: newest) ?? newest

        var out: [NexusStandardizedPattern] = []
        for (topic, values) in topicSignals where values.count >= 3 {
            let sources = Set(values.map(\.source))
            let dates = values.compactMap(\.timestamp).sorted()
            let spanDays: Int
            if let first = dates.first, let last = dates.last {
                spanDays = max(0, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0)
            } else { spanDays = 0 }
            let actionCounts = Dictionary(grouping: values, by: \.action).mapValues(\.count).sorted { $0.value > $1.value }
            let recent = values.filter { ($0.timestamp ?? .distantPast) >= recentStart }.count
            let previous = values.filter { signal in
                let d = signal.timestamp ?? .distantPast
                return d >= previousStart && d < recentStart
            }.count
            let breadth = min(1.0, Double(sources.count) / 4.0)
            let recurrence = min(1.0, log(Double(values.count) + 1) / log(40.0))
            let persistence = min(1.0, Double(spanDays) / 730.0)
            let avgEvidence = values.map(\.evidenceWeight).reduce(0,+) / Double(max(values.count, 1))
            let score = min(1, 0.34 * breadth + 0.30 * recurrence + 0.22 * persistence + 0.14 * avgEvidence)
            let kind: NexusStandardizedPattern.Kind
            if recent >= max(3, previous * 2) { kind = .emerging }
            else if previous >= max(4, recent * 2) { kind = .fading }
            else if sources.count >= 3 { kind = .crossSource }
            else if spanDays >= 365 { kind = .persistent }
            else { kind = .recurring }
            let actions = actionCounts.prefix(4).map { $0.key.rawValue }
            let evidence = values.prefix(6).map { signal in
                let date = signal.timestamp?.formatted(date: .abbreviated, time: .omitted) ?? "undated"
                return "\(date) • \(signal.source) • \(signal.action.rawValue): \(signal.subject)"
            }
            out.append(.init(id: "topic:\(topic)", kind: kind, label: topic.capitalized,
                             summary: "Appears in \(values.count) standardized signals across \(sources.count) source\(sources.count == 1 ? "" : "s") over about \(spanDays) days.",
                             score: score, sourceBreadth: sources.count, recordCount: values.count,
                             timeSpanDays: spanDays, actionLabels: actions, evidence: evidence))
        }

        let actionGroups = Dictionary(grouping: signals, by: \.action)
        for (action, values) in actionGroups where values.count >= 5 {
            let sources = Set(values.map(\.source))
            let dates = values.compactMap(\.timestamp).sorted()
            let span = (dates.first != nil && dates.last != nil) ? max(0, Calendar.current.dateComponents([.day], from: dates.first!, to: dates.last!).day ?? 0) : 0
            let score = min(1, 0.45 * min(1, Double(sources.count) / 4.0) + 0.35 * min(1, log(Double(values.count)+1)/log(80)) + 0.20 * min(1, Double(span)/730))
            let kind: NexusStandardizedPattern.Kind
            switch action {
            case .create: kind = .creative
            case .explore: kind = .exploratory
            case .plan, .organize: kind = .planning
            case .communicate, .connect: kind = .social
            default: kind = .recurring
            }
            out.append(.init(id: "action:\(action.rawValue)", kind: kind, label: action.rawValue,
                             summary: "\(values.count) signals across \(sources.count) sources map to this action family.",
                             score: score, sourceBreadth: sources.count, recordCount: values.count,
                             timeSpanDays: span, actionLabels: [action.rawValue],
                             evidence: values.prefix(5).map { "\($0.source): \($0.subject)" }))
        }
        return out.sorted { $0.score > $1.score }
    }

    private static func actionFamily(_ kind: KnowledgeRecord.Kind) -> NexusCanonicalSignal.ActionFamily {
        switch kind {
        case .message, .comment, .reaction: return .communicate
        case .post, .media, .note: return .create
        case .search: return .explore
        case .saved: return .save
        case .follow, .contact: return .connect
        case .event, .reminder: return .plan
        case .location: return .move
        case .health: return .wellbeing
        case .file, .profile: return .organize
        case .music: return .consume
        case .activity: return .organize
        case .unknown: return .other
        }
    }

    private static func modality(_ record: KnowledgeRecord) -> NexusCanonicalSignal.Modality {
        switch record.kind {
        case .message, .comment, .search, .note, .post: return .text
        case .media: return .visual
        case .music: return .audio
        case .event, .reminder: return .event
        case .location: return .location
        case .health: return .health
        case .contact, .follow, .reaction: return .social
        case .file, .profile, .saved, .activity, .unknown: return .file
        }
    }

    private static func canonicalSource(_ source: String) -> String {
        let s = source.lowercased()
        if s.contains("instagram") { return "Instagram" }
        if s.contains("messenger") { return "Messenger" }
        if s.contains("facebook") || s == "meta" || s.contains("meta archive") { return "Facebook" }
        if s.contains("calendar") { return "Calendar" }
        if s.contains("contact") { return "Contacts" }
        if s.contains("reminder") { return "Reminders" }
        if s.contains("health") { return "Apple Health" }
        if s.contains("photo") { return "Photos" }
        if s.contains("music") { return "Music" }
        return source.isEmpty ? "Unknown" : source
    }

    private static func canonicalSubject(_ record: KnowledgeRecord) -> String {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return String(title.prefix(140)) }
        let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return String(text.prefix(140)) }
        return record.kind.rawValue.capitalized
    }

    private static func canonicalEntities(_ record: KnowledgeRecord) -> [String] {
        var out: [String] = []
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if [.message,.comment,.contact,.follow,.reaction].contains(record.kind), !title.isEmpty, title.count < 100 { out.append(title) }
        for key in ["participant","sender","author","artist","location","place","organization"] {
            if let value = record.metadata[key], !value.isEmpty { out.append(value) }
        }
        return Array(Set(out)).prefix(8).map { $0 }
    }

    private static func canonicalPlace(_ record: KnowledgeRecord) -> String? {
        if record.kind == .location { return canonicalSubject(record) }
        for key in ["location","place","city","address"] {
            if let value = record.metadata[key], !value.isEmpty { return value }
        }
        return nil
    }

    private static func evidenceWeight(_ record: KnowledgeRecord) -> Double {
        var score = 0.35
        if record.timestamp != nil { score += 0.18 }
        if !record.text.isEmpty { score += 0.17 }
        if !record.title.isEmpty { score += 0.08 }
        if !record.metadata.isEmpty { score += 0.08 }
        switch record.kind {
        case .event, .reminder, .contact, .health, .location: score += 0.10
        default: break
        }
        return min(1, score)
    }

    private static func topTerms(_ text: String, limit: Int) -> [String] {
        var counts: [String:Int] = [:]
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for word in words where word.count >= 4 && !stopWords.contains(word) { counts[word, default: 0] += 1 }
        return counts.sorted { a, b in a.value == b.value ? a.key < b.key : a.value > b.value }.prefix(limit).map(\.key)
    }
}

extension NexusModel {
    var standardizedReport: NexusStandardizationReport { NexusStandardizationEngine.report(records) }
}
