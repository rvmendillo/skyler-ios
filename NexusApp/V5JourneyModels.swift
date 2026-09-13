import Foundation
import AVFoundation

// MARK: - Journey models

enum JourneyStoryMode: String, CaseIterable, Identifiable {
    case journey = "My Journey"
    case interests = "Interests"
    case people = "People"
    case places = "Places"
    case surprises = "Surprises"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .journey: return "book.closed.fill"
        case .interests: return "sparkles"
        case .people: return "person.3.fill"
        case .places: return "map.fill"
        case .surprises: return "wand.and.stars"
        }
    }
}

struct NexusStoryPage: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let body: String
    let evidence: [String]
    let symbol: String
    let accentIndex: Int
}

struct NexusTimelineBucket: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let records: [KnowledgeRecord]
}

struct NexusYearSnapshot: Identifiable, Hashable {
    var id: Int { year }
    let year: Int
    let recordCount: Int
    let datedCount: Int
    let sourceCount: Int
    let topKinds: [(String, Int)]
    let topTerms: [(String, Int)]

    static func == (lhs: NexusYearSnapshot, rhs: NexusYearSnapshot) -> Bool {
        lhs.year == rhs.year && lhs.recordCount == rhs.recordCount && lhs.topKinds.map(\.0) == rhs.topKinds.map(\.0) && lhs.topTerms.map(\.0) == rhs.topTerms.map(\.0)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(recordCount)
        hasher.combine(sourceCount)
    }
}

struct NexusTimeMachineResult: Hashable {
    let first: NexusYearSnapshot
    let second: NexusYearSnapshot
    let summary: String
    let details: [String]
}

// MARK: - Journey analytics

extension NexusModel {
    var journeyYears: [Int] {
        let calendar = Calendar.current
        return Array(Set(records.compactMap { $0.timestamp.map { calendar.component(.year, from: $0) } })).sorted(by: >)
    }

    var journeyDatedRecords: [KnowledgeRecord] {
        records.filter { $0.timestamp != nil }.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

    func journeyTimelineRecords(year: Int?, query: String, kind: KnowledgeRecord.Kind?) -> [KnowledgeRecord] {
        let calendar = Calendar.current
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return journeyDatedRecords.lazy.filter { record in
            if let year, let date = record.timestamp, calendar.component(.year, from: date) != year { return false }
            if let kind, record.kind != kind { return false }
            if !q.isEmpty {
                let hay = (record.title + " " + record.text + " " + record.source + " " + record.kind.rawValue).lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }.prefix(6000).map { $0 }
    }

    func journeyTimelineBuckets(year: Int?, query: String, kind: KnowledgeRecord.Kind?) -> [NexusTimelineBucket] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let filtered = journeyTimelineRecords(year: year, query: query, kind: kind)
        let grouped = Dictionary(grouping: filtered) { record -> String in
            guard let date = record.timestamp else { return "unknown" }
            let comps = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        }
        return grouped.keys.sorted(by: >).compactMap { key in
            guard let values = grouped[key], let date = values.first?.timestamp else { return nil }
            let sources = Set(values.map(\.source)).count
            return NexusTimelineBucket(id: key,
                                       title: formatter.string(from: date),
                                       subtitle: "\(values.count) records • \(sources) source\(sources == 1 ? "" : "s")",
                                       records: values.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) })
        }
    }

    var journeyYearSnapshots: [NexusYearSnapshot] {
        journeyYears.compactMap { snapshot(for: $0) }
    }

    func snapshot(for year: Int) -> NexusYearSnapshot? {
        let calendar = Calendar.current
        let yearRecords = records.filter { record in
            guard let date = record.timestamp else { return false }
            return calendar.component(.year, from: date) == year
        }
        guard !yearRecords.isEmpty else { return nil }
        let kindCounts = Dictionary(grouping: yearRecords, by: { $0.kind.rawValue }).mapValues(\.count)
            .sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        return NexusYearSnapshot(year: year,
                                 recordCount: yearRecords.count,
                                 datedCount: yearRecords.compactMap(\.timestamp).count,
                                 sourceCount: Set(yearRecords.map(\.source)).count,
                                 topKinds: kindCounts,
                                 topTerms: journeyTopTerms(in: yearRecords, limit: 7))
    }

    func compareYears(_ firstYear: Int, _ secondYear: Int) -> NexusTimeMachineResult? {
        guard let a = snapshot(for: firstYear), let b = snapshot(for: secondYear) else { return nil }
        let delta = b.recordCount - a.recordCount
        let common = Set(a.topTerms.map(\.0)).intersection(Set(b.topTerms.map(\.0))).sorted()
        let newTerms = b.topTerms.map(\.0).filter { !Set(a.topTerms.map(\.0)).contains($0) }
        let summary: String
        if delta == 0 {
            summary = "\(firstYear) and \(secondYear) contain similar captured activity volume, but the mix of topics and activity types may still differ."
        } else {
            summary = "The vault contains \(abs(delta)) \(delta > 0 ? "more" : "fewer") dated records in \(secondYear) than \(firstYear). Treat this as captured-data volume, not automatically as a real-life activity change."
        }
        var details = [
            "\(firstYear): \(a.recordCount) records across \(a.sourceCount) sources",
            "\(secondYear): \(b.recordCount) records across \(b.sourceCount) sources"
        ]
        if !common.isEmpty { details.append("Recurring in both periods: " + common.prefix(6).joined(separator: ", ")) }
        if !newTerms.isEmpty { details.append("More distinctive in \(secondYear): " + newTerms.prefix(6).joined(separator: ", ")) }
        return NexusTimeMachineResult(first: a, second: b, summary: summary, details: details)
    }

    var journeyOnThisDay: [KnowledgeRecord] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        return journeyDatedRecords.filter { record in
            guard let date = record.timestamp else { return false }
            return calendar.component(.month, from: date) == month && calendar.component(.day, from: date) == day && !calendar.isDate(date, inSameDayAs: now)
        }
    }

    var journeyMemoryDeck: [KnowledgeRecord] {
        let useful = records.filter { record in
            let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return record.timestamp != nil && (!text.isEmpty || !record.title.isEmpty) && record.kind != .health
        }
        return useful.sorted { journeyStableRank($0.id) < journeyStableRank($1.id) }.prefix(120).map { $0 }
    }

    func storyPages(mode: JourneyStoryMode) -> [NexusStoryPage] {
        guard !records.isEmpty else {
            return [NexusStoryPage(id: "empty", title: "Your story is waiting", subtitle: "Add some memories", body: "Import or connect data and NEXUS will turn real evidence from your vault into a browsable storybook.", evidence: [], symbol: "book.closed", accentIndex: 0)]
        }
        switch mode {
        case .journey: return journeyStoryPages()
        case .interests: return interestStoryPages()
        case .people: return peopleStoryPages()
        case .places: return placeStoryPages()
        case .surprises: return surpriseStoryPages()
        }
    }

    private func journeyStoryPages() -> [NexusStoryPage] {
        var pages: [NexusStoryPage] = []
        for (index, snap) in journeyYearSnapshots.prefix(14).enumerated() {
            let recordsForYear = journeyTimelineRecords(year: snap.year, query: "", kind: nil)
            let kinds = snap.topKinds.prefix(3).map { $0.0.capitalized }.joined(separator: ", ")
            let terms = snap.topTerms.prefix(5).map(\.0).joined(separator: ", ")
            let body = "In \(snap.year), NEXUS can see \(snap.recordCount) dated pieces of evidence across \(snap.sourceCount) sources. The archive is especially rich in \(kinds.isEmpty ? "mixed activity" : kinds). Repeated terms include \(terms.isEmpty ? "no stable keywords yet" : terms). This page describes what the vault captured, not every part of that year."
            pages.append(NexusStoryPage(id: "journey-\(snap.year)", title: "A chapter from \(snap.year)", subtitle: "\(snap.recordCount) traces in the vault", body: body, evidence: journeyEvidence(recordsForYear), symbol: "calendar.circle.fill", accentIndex: index))
        }
        return pages.isEmpty ? storyFallback() : pages
    }

    private func interestStoryPages() -> [NexusStoryPage] {
        let terms = journeyTopTerms(in: records, limit: 14)
        return terms.enumerated().compactMap { index, pair in
            let term = pair.0
            let matches = records.filter { ($0.title + " " + $0.text).lowercased().contains(term) }
            guard !matches.isEmpty else { return nil }
            let dated = matches.compactMap(\.timestamp).sorted()
            let span: String
            if let first = dated.first, let last = dated.last, !Calendar.current.isDate(first, inSameDayAs: last) {
                span = "Evidence stretches from \(first.formatted(date: .abbreviated, time: .omitted)) to \(last.formatted(date: .abbreviated, time: .omitted))."
            } else { span = "The current evidence is concentrated in a narrower period." }
            return NexusStoryPage(id: "interest-\(term)", title: "The trail of “\(term)”", subtitle: "\(matches.count) matching traces", body: "This theme keeps reappearing across the vault. \(span) Repetition can mean an interest, project, person, place or recurring context, so NEXUS keeps the interpretation cautious until several sources agree.", evidence: journeyEvidence(matches), symbol: "sparkles", accentIndex: index)
        }
    }

    private func peopleStoryPages() -> [NexusStoryPage] {
        let social = records.filter { [.message, .contact, .follow, .comment, .reaction].contains($0.kind) }
        let groups = Dictionary(grouping: social) { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.key.isEmpty && $0.key.count < 90 }
            .sorted { $0.value.count > $1.value.count }
        return groups.prefix(12).enumerated().map { index, item in
            let name = item.key
            let values = item.value
            let kinds = Set(values.map { $0.kind.rawValue }).sorted().joined(separator: ", ")
            return NexusStoryPage(id: "person-\(name)", title: name, subtitle: "A recurring social thread", body: "\(name) appears in \(values.count) captured social signals spanning \(kinds). Visibility in an export does not by itself prove closeness, sentiment or relationship quality, but it does show that this label is structurally important in the current social graph.", evidence: journeyEvidence(values), symbol: "person.crop.circle.fill", accentIndex: index)
        }
    }

    private func placeStoryPages() -> [NexusStoryPage] {
        let placeRecords = records.filter { $0.kind == .location || ($0.title + " " + $0.text).lowercased().contains("travel") || ($0.title + " " + $0.text).lowercased().contains("hotel") || ($0.title + " " + $0.text).lowercased().contains("airport") }
        let terms = journeyTopTerms(in: placeRecords, limit: 10)
        return terms.enumerated().map { index, pair in
            let matches = placeRecords.filter { ($0.title + " " + $0.text).lowercased().contains(pair.0) }
            return NexusStoryPage(id: "place-\(pair.0)", title: pair.0.capitalized, subtitle: "A place-shaped thread", body: "This place-related term appears \(matches.count) times in the available travel/location evidence. Open the evidence to see exactly which records made it part of your map.", evidence: journeyEvidence(matches), symbol: "mappin.and.ellipse", accentIndex: index)
        }
    }

    private func surpriseStoryPages() -> [NexusStoryPage] {
        let deck = journeyMemoryDeck.prefix(16)
        return deck.enumerated().map { index, record in
            let dateText = record.timestamp?.formatted(date: .long, time: .shortened) ?? "Undated"
            let bodyText = record.text.isEmpty ? record.title : record.text
            return NexusStoryPage(id: "surprise-\(record.id)", title: "A little time capsule", subtitle: dateText, body: String(bodyText.prefix(700)), evidence: ["\(record.source) • \(record.kind.rawValue)", "Original title: \(record.title)"], symbol: "gift.fill", accentIndex: index)
        }
    }

    private func storyFallback() -> [NexusStoryPage] {
        [NexusStoryPage(id: "fallback", title: "A story is forming", subtitle: "More dated data will add chapters", body: "NEXUS has records, but not enough time-anchored evidence to build a chronological chapter yet. Try the Interests or Surprises story modes in the meantime.", evidence: [], symbol: "clock.badge.questionmark", accentIndex: 0)]
    }

    private func journeyEvidence(_ input: [KnowledgeRecord]) -> [String] {
        input.prefix(6).map { record in
            let body = record.text.isEmpty ? record.title : record.text
            let date = record.timestamp?.formatted(date: .abbreviated, time: .omitted) ?? "undated"
            return "\(date) • \(record.source) • \(record.kind.rawValue): \(String(body.prefix(150)))"
        }
    }

    private func journeyTopTerms(in input: [KnowledgeRecord], limit: Int) -> [(String, Int)] {
        let stop: Set<String> = ["this","that","with","from","have","your","about","there","their","they","them","were","been","when","what","where","which","would","could","should","into","than","then","just","also","very","https","http","www","com","message","messages","instagram","facebook","messenger","profile","photo","video"]
        var counts: [String:Int] = [:]
        for record in input.prefix(30_000) {
            let text = (record.title + " " + record.text).lowercased()
            let words = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            var seen = Set<String>()
            for word in words where word.count > 3 && !stop.contains(word) {
                if seen.insert(word).inserted { counts[word, default: 0] += 1 }
            }
        }
        return Array(counts.sorted { a, b in a.value == b.value ? a.key < b.key : a.value > b.value }.prefix(limit))
    }

    private func journeyStableRank(_ value: String) -> Int {
        value.unicodeScalars.reduce(17) { (($0 &* 31) &+ Int($1.value)) & 0x7fffffff }
    }
}

// MARK: - Read aloud

final class NexusStoryNarrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.05
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US") ?? AVSpeechSynthesisVoice(language: "en-US")
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { isSpeaking = false }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { isSpeaking = false }
}
