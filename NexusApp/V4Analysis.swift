import Foundation

struct NexusTraitBand: Identifiable, Hashable {
    let id: String
    let name: String
    let estimate: Int?
    let low: Int?
    let high: Int?
    let confidence: Double
    let rationale: String
    let evidence: [String]
}

struct NexusV4Report: Hashable {
    let overall: String
    let qualitySummary: String
    let sections: [AnalysisSection]
    let traits: [NexusTraitBand]
    let limitations: [String]
    let confidence: Double
}

enum ComprehensiveAnalysisEngine {
    private static let stopwords: Set<String> = [
        "the","and","that","this","with","from","your","you","for","are","was","were","have","has","had","not","but","about","http","https","www","com","into","then","than","there","their","they","them","would","could","should","what","when","where","which","while","also","just","more","some","very","been","being","will","shall","can","cant","dont","does","did","its","our","ours","his","her","hers","she","him","who","message","messages","profile","facebook","instagram","messenger","reel","photo","video"]

    private static let domains: [String:Set<String>] = [
        "Software & AI": ["software","programming","code","coding","developer","swift","ios","github","api","python","java","javascript","xcode","ai","machine","model","algorithm","computer","data","automation"],
        "Music & piano": ["music","piano","song","chord","melody","harmony","scale","arpeggio","classical","artist","album","track","rhythm","compose","composition"],
        "Finance & investing": ["finance","money","saving","savings","bank","credit","interest","investment","investing","crypto","bitcoin","ethereum","eth","stock","stocks","budget","salary","cash"],
        "Travel & places": ["travel","trip","flight","hotel","airport","taiwan","japan","boracay","manila","taipei","train","mrt","tour","visa","beach","destination"],
        "Learning & ideas": ["learn","learning","course","study","school","university","math","calculus","algebra","logic","philosophy","psychology","science","book","research","theory","explain"],
        "Games & interactive media": ["game","games","gaming","mlbb","pokemon","monopoly","character","mobile","anime"],
        "Creativity & design": ["design","art","creative","create","writing","poem","story","aesthetic","image","drawing","portfolio","visual","idea","ideas"],
        "Health & wellbeing": ["health","sleep","exercise","workout","food","diet","heart","steps","energy","stress","wellbeing","medicine"],
        "Food & dining": ["food","restaurant","eat","eating","mango","coffee","meal","breakfast","lunch","dinner","recipe","taste"],
        "Relationships & social": ["friend","friends","family","relationship","people","person","social","chat","conversation","team","workmate","colleague"]
    ]

    static func analyze(_ allRecords: [KnowledgeRecord]) -> NexusV4Report {
        guard !allRecords.isEmpty else {
            return NexusV4Report(overall: "NEXUS does not yet have enough behavioral evidence for a realistic analysis.", qualitySummary: "No imported evidence.", sections: [], traits: [], limitations: ["Import at least one archive or device source first."], confidence: 0)
        }

        let records = Array(allRecords.prefix(60_000))
        let sourceCounts = Dictionary(grouping: records, by: \.source).mapValues(\.count)
        let kindCounts = Dictionary(grouping: records, by: \.kind).mapValues(\.count)
        let dated = records.compactMap { r -> (Date, KnowledgeRecord)? in r.timestamp.map { ($0, r) } }
        let sourceCount = sourceCounts.count
        let kindCount = kindCounts.count
        let topSource = sourceCounts.max { $0.value < $1.value }
        let topShare = Double(topSource?.value ?? 0) / Double(max(records.count, 1))
        let datedRatio = Double(dated.count) / Double(max(records.count, 1))
        let oldest = dated.map(\.0).min()
        let newest = dated.map(\.0).max()
        let spanDays: Double = {
            guard let oldest, let newest else { return 0 }
            return max(0, newest.timeIntervalSince(oldest) / 86_400)
        }()

        let sampleFactor = min(1.0, log10(Double(records.count) + 10) / 4.3)
        let sourceFactor = min(1.0, Double(sourceCount) / 5.0)
        let kindFactor = min(1.0, Double(kindCount) / 9.0)
        let timeFactor = min(1.0, spanDays / 365.0)
        let dominancePenalty = max(0, (topShare - 0.55) * 0.55)
        let overallConfidence = clamp01(0.16 + sampleFactor * 0.24 + sourceFactor * 0.24 + kindFactor * 0.17 + timeFactor * 0.13 + datedRatio * 0.08 - dominancePenalty)

        let sourceDescription = topSource.map { "\($0.key) contributes \(Int(topShare * 100))% of current records" } ?? "No dominant source"
        let timeDescription = spanDays >= 1 ? "\(Int(spanDays)) days of dated coverage" : "very limited dated coverage"
        let qualitySummary = "\(records.count) records across \(sourceCount) source\(sourceCount == 1 ? "" : "s") and \(kindCount) activity types; \(Int(datedRatio * 100))% are time-anchored, with \(timeDescription). \(sourceDescription)."

        let domainSignals = analyzeDomains(records)
        let topDomains = domainSignals.prefix(5)
        let interestSummary: String = {
            guard !topDomains.isEmpty else { return "No stable cross-record interest pattern is strong enough yet." }
            let names = topDomains.map(\.name)
            return "The strongest recurring attention domains are \(naturalJoin(names)). Rankings reward repetition across different sources and activity types, rather than raw mention count alone."
        }()

        var sections: [AnalysisSection] = []
        sections.append(.init(title: "Evidence quality & representativeness",
                              summary: qualitySummary,
                              details: qualityDetails(records: records, sourceCounts: sourceCounts, kindCounts: kindCounts, datedRatio: datedRatio, spanDays: spanDays, topShare: topShare),
                              confidence: overallConfidence))

        if !topDomains.isEmpty {
            sections.append(.init(title: "Interests & sustained attention",
                                  summary: interestSummary,
                                  details: topDomains.map { signal in
                                      "\(signal.name): \(signal.matches) matched records • \(signal.sources) sources • \(signal.kinds) activity types • evidence strength \(Int(signal.confidence * 100))%"
                                  },
                                  confidence: min(0.94, topDomains.map(\.confidence).reduce(0,+) / Double(topDomains.count))))
        }

        if let curiosity = curiositySection(records) { sections.append(curiosity) }
        if let communication = communicationSection(records, sourceCount: sourceCount) { sections.append(communication) }
        if let social = socialSection(records) { sections.append(social) }
        if let temporal = temporalSection(dated, total: records.count) { sections.append(temporal) }
        if let change = changeSection(dated, domains: domains) { sections.append(change) }
        if let content = activityMixSection(kindCounts, total: records.count) { sections.append(content) }
        if let place = placeSection(records) { sections.append(place) }

        let contradictions = uncertaintySection(records: records, sourceCounts: sourceCounts, topShare: topShare, datedRatio: datedRatio, spanDays: spanDays)
        sections.append(contradictions)

        let traits = personalityBands(records: records, domainSignals: domainSignals, sourceCount: sourceCount, topShare: topShare, spanDays: spanDays)

        let limitations = limitationList(sourceCount: sourceCount, topSource: topSource, topShare: topShare, datedRatio: datedRatio, spanDays: spanDays, records: records)

        let topNames = topDomains.prefix(3).map(\.name)
        var overall = "Current evidence suggests a profile centered on \(naturalJoin(topNames.isEmpty ? ["a still-developing set of interests"] : topNames)). "
        overall += "This conclusion is based on \(records.count) captured records, not on a fixed personality label. "
        if topShare > 0.70, let topSource {
            overall += "Because \(topSource.key) dominates the dataset, NEXUS treats cross-life conclusions conservatively. "
        }
        if spanDays < 90 {
            overall += "The time span is short, so long-term stability and life-change conclusions remain tentative. "
        } else {
            overall += "The timeline is broad enough to begin separating persistent patterns from short phases. "
        }
        overall += "Overall evidence confidence is \(confidenceWord(overallConfidence)) (\(Int(overallConfidence * 100))%)."

        return NexusV4Report(overall: overall, qualitySummary: qualitySummary, sections: sections, traits: traits, limitations: limitations, confidence: overallConfidence)
    }

    private struct DomainSignal {
        let name: String
        let matches: Int
        let sources: Int
        let kinds: Int
        let confidence: Double
        let weighted: Double
    }

    private static func analyzeDomains(_ records: [KnowledgeRecord]) -> [DomainSignal] {
        var results: [DomainSignal] = []
        for (name, lexicon) in domains {
            var matches = 0
            var sourceSet = Set<String>()
            var kindSet = Set<KnowledgeRecord.Kind>()
            var sourceCounts: [String:Int] = [:]
            for r in records {
                let words = Set(tokens(r.title + " " + r.text))
                guard !words.isDisjoint(with: lexicon) else { continue }
                matches += 1
                sourceSet.insert(r.source)
                kindSet.insert(r.kind)
                sourceCounts[r.source, default: 0] += 1
            }
            guard matches > 0 else { continue }
            let dominant = Double(sourceCounts.values.max() ?? 0) / Double(matches)
            let breadth = min(1.0, Double(sourceSet.count) / 3.0) * 0.55 + min(1.0, Double(kindSet.count) / 5.0) * 0.25
            let volume = min(1.0, log10(Double(matches) + 1) / 2.3) * 0.30
            let confidence = clamp01(0.18 + breadth + volume - max(0, dominant - 0.75) * 0.35)
            let weighted = log(Double(matches) + 1) * (1 + Double(max(sourceSet.count - 1, 0)) * 0.32) * (1 + Double(max(kindSet.count - 1, 0)) * 0.10) * (1.15 - min(0.55, dominant * 0.35))
            results.append(.init(name: name, matches: matches, sources: sourceSet.count, kinds: kindSet.count, confidence: confidence, weighted: weighted))
        }
        return results.sorted { $0.weighted > $1.weighted }
    }

    private static func qualityDetails(records: [KnowledgeRecord], sourceCounts: [String:Int], kindCounts: [KnowledgeRecord.Kind:Int], datedRatio: Double, spanDays: Double, topShare: Double) -> [String] {
        var details = sourceCounts.sorted { $0.value > $1.value }.prefix(6).map { "Source \($0.key): \($0.value) records" }
        details.append("Dated coverage: \(Int(datedRatio * 100))%")
        details.append("Timeline span: \(Int(spanDays)) days")
        details.append("Largest-source concentration: \(Int(topShare * 100))%")
        details.append("Activity types represented: \(kindCounts.count)")
        details.append("Confidence is reduced when one app dominates or when timestamps are sparse.")
        return details
    }

    private static func curiositySection(_ records: [KnowledgeRecord]) -> AnalysisSection? {
        let userActionKinds: Set<KnowledgeRecord.Kind> = [.search,.saved,.post,.comment,.follow,.event,.reminder,.note,.music]
        let actions = records.filter { userActionKinds.contains($0.kind) }
        guard actions.count >= 8 else { return nil }
        let searchCount = actions.filter { $0.kind == .search }.count
        let savedCount = actions.filter { $0.kind == .saved }.count
        let questionCount = actions.filter { ($0.title + " " + $0.text).contains("?") }.count
        let learningTerms = ["learn","research","course","study","how","why","compare","difference","explain","theory","tutorial"]
        let learningHits = actions.filter { r in
            let t = (r.title + " " + r.text).lowercased()
            return learningTerms.contains { t.contains($0) }
        }.count
        let sources = Set(actions.map(\.source)).count
        let confidence = clamp01(0.25 + min(0.35, Double(actions.count) / 900.0) + min(0.25, Double(sources) / 4.0))
        let summary = "NEXUS sees \(searchCount) search records, \(savedCount) saved-item records, and \(learningHits) explicit learning/explanation signals among user-action-like records. This is a better curiosity indicator than counting every message in the archive."
        return .init(title: "Curiosity & learning behavior", summary: summary,
                     details: ["Search records: \(searchCount)", "Saved-item records: \(savedCount)", "Question-bearing user-action records: \(questionCount)", "Learning/explanation signals: \(learningHits)", "Contributing sources: \(sources)"], confidence: confidence)
    }

    private static func communicationSection(_ records: [KnowledgeRecord], sourceCount: Int) -> AnalysisSection? {
        let messages = records.filter { $0.kind == .message && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard messages.count >= 20 else { return nil }
        let wordLengths = messages.map { tokens($0.text).count }
        let avg = wordLengths.reduce(0,+) / max(1, wordLengths.count)
        let median = medianInt(wordLengths)
        let questionRate = Double(messages.filter { $0.text.contains("?") }.count) / Double(messages.count)
        let emojiLikeRate = Double(messages.filter { $0.text.unicodeScalars.contains { $0.value > 0x1F000 } }.count) / Double(messages.count)
        let senders = Set(messages.map(\.title).filter { !$0.isEmpty })
        let confidence = clamp01(0.25 + min(0.38, Double(messages.count) / 3500.0) + min(0.15, Double(sourceCount) / 5.0))
        let summary = "The imported conversation corpus contains \(messages.count) non-empty messages, with a median of \(median) words per captured message. Because Meta exports include messages from both you and other participants, NEXUS treats this as a conversation-corpus description unless self-authorship can be identified reliably."
        return .init(title: "Communication corpus", summary: summary,
                     details: ["Median message length: \(median) words", "Mean message length: \(avg) words", "Messages containing a question mark: \(Int(questionRate * 100))%", "Messages containing emoji-range characters: \(Int(emojiLikeRate * 100))%", "Distinct sender labels: \(senders.count)", "Not automatically interpreted as your personal writing style."], confidence: confidence)
    }

    private static func socialSection(_ records: [KnowledgeRecord]) -> AnalysisSection? {
        let socialKinds: Set<KnowledgeRecord.Kind> = [.message,.follow,.reaction,.comment,.contact]
        let social = records.filter { socialKinds.contains($0.kind) }
        guard social.count >= 10 else { return nil }
        let people = Dictionary(grouping: social.filter { !$0.title.isEmpty }, by: \.title).mapValues(\.count).sorted { $0.value > $1.value }
        let totalLabeled = people.map(\.value).reduce(0,+)
        let topShare = Double(people.first?.value ?? 0) / Double(max(totalLabeled,1))
        let summary = "Social evidence spans \(people.count) recurring labels. The most visible label accounts for \(Int(topShare * 100))% of labeled social records. Visibility reflects archive presence, not closeness, affection, trust, or relationship quality."
        return .init(title: "Social landscape", summary: summary,
                     details: people.prefix(10).map { "\($0.key): \($0.value) captured social signals" } + ["Top-label concentration: \(Int(topShare * 100))%"],
                     confidence: clamp01(0.28 + min(0.48, Double(social.count) / 2500.0) + min(0.16, Double(people.count) / 80.0)))
    }

    private static func temporalSection(_ dated: [(Date, KnowledgeRecord)], total: Int) -> AnalysisSection? {
        guard dated.count >= 30 else { return nil }
        let cal = Calendar.current
        let hours = Dictionary(grouping: dated, by: { cal.component(.hour, from: $0.0) }).mapValues(\.count)
        let weekdays = Dictionary(grouping: dated, by: { cal.component(.weekday, from: $0.0) }).mapValues(\.count)
        guard let peakHour = hours.max(by: { $0.value < $1.value }), let peakDay = weekdays.max(by: { $0.value < $1.value }) else { return nil }
        let night = dated.filter { let h = cal.component(.hour, from: $0.0); return h >= 0 && h < 6 }.count
        let nightRate = Double(night) / Double(dated.count)
        let weekdayName = cal.weekdaySymbols[peakDay.key - 1]
        let summary = "Dated records are most concentrated around \(String(format: "%02d:00", peakHour.key)) and on \(weekdayName). These are activity-timestamp patterns, not necessarily waking hours or productivity peaks; some platforms timestamp automated or received events too."
        return .init(title: "Time & routine patterns", summary: summary,
                     details: ["Peak captured hour: \(String(format: "%02d:00", peakHour.key)) (\(peakHour.value) records)", "Peak captured weekday: \(weekdayName) (\(peakDay.value) records)", "00:00–05:59 share: \(Int(nightRate * 100))%", "Timestamp coverage: \(dated.count) of \(total) records"],
                     confidence: clamp01(0.24 + min(0.52, Double(dated.count) / 5000.0)))
    }

    private static func changeSection(_ dated: [(Date, KnowledgeRecord)], domains: [String:Set<String>]) -> AnalysisSection? {
        guard dated.count >= 80, let newest = dated.map(\.0).max() else { return nil }
        let cal = Calendar.current
        let recentStart = cal.date(byAdding: .day, value: -90, to: newest) ?? newest
        let previousStart = cal.date(byAdding: .day, value: -180, to: newest) ?? newest
        let recent = dated.filter { $0.0 >= recentStart }.map(\.1)
        let previous = dated.filter { $0.0 >= previousStart && $0.0 < recentStart }.map(\.1)
        guard recent.count >= 20, previous.count >= 20 else { return nil }

        var changes: [(String, Double, Int, Int)] = []
        for (name, lexicon) in domains {
            let r = recent.filter { !Set(tokens($0.title + " " + $0.text)).isDisjoint(with: lexicon) }.count
            let p = previous.filter { !Set(tokens($0.title + " " + $0.text)).isDisjoint(with: lexicon) }.count
            let rr = Double(r) / Double(recent.count)
            let pr = Double(p) / Double(previous.count)
            let delta = rr - pr
            if abs(delta) >= 0.01 { changes.append((name, delta, r, p)) }
        }
        changes.sort { abs($0.1) > abs($1.1) }
        guard !changes.isEmpty else { return nil }
        let leader = changes[0]
        let direction = leader.1 > 0 ? "increased" : "decreased"
        let summary = "After normalizing for different record volumes, \(leader.0) \(direction) the most in the latest 90-day window versus the preceding 90 days. This is a change in captured attention, not proof of a permanent preference shift."
        let details = changes.prefix(6).map { name, delta, r, p in
            "\(name): \(delta >= 0 ? "+" : "")\(Int(delta * 100)) percentage points • recent \(r), previous \(p) matches"
        }
        return .init(title: "Change over time", summary: summary, details: details, confidence: clamp01(0.35 + min(0.35, Double(min(recent.count, previous.count)) / 800.0)))
    }

    private static func activityMixSection(_ kinds: [KnowledgeRecord.Kind:Int], total: Int) -> AnalysisSection? {
        guard total > 0 else { return nil }
        let sorted = kinds.sorted { $0.value > $1.value }
        let top = sorted.prefix(8)
        let summary = "The dataset is primarily composed of \(naturalJoin(top.prefix(4).map { $0.key.rawValue })). This matters because the archive's composition determines which parts of your life NEXUS can observe well."
        return .init(title: "What the dataset actually observes", summary: summary,
                     details: top.map { "\($0.key.rawValue.capitalized): \($0.value) (\(Int(Double($0.value) / Double(total) * 100))%)" }, confidence: 0.98)
    }

    private static func placeSection(_ records: [KnowledgeRecord]) -> AnalysisSection? {
        let places = records.filter { $0.kind == .location }
        guard !places.isEmpty else { return nil }
        let labels = Dictionary(grouping: places.map { $0.text.isEmpty ? $0.title : $0.text }.filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
        guard !labels.isEmpty else { return nil }
        return .init(title: "Places & mobility evidence", summary: "NEXUS has \(labels.count) distinct location labels. Repetition can indicate frequently captured places, but passive location records should not automatically be interpreted as preference.", details: labels.prefix(10).map { "\($0.key): \($0.value) records" }, confidence: clamp01(0.35 + min(0.45, Double(places.count) / 500.0)))
    }

    private static func uncertaintySection(records: [KnowledgeRecord], sourceCounts: [String:Int], topShare: Double, datedRatio: Double, spanDays: Double) -> AnalysisSection {
        var details: [String] = []
        if topShare > 0.70 { details.append("One source contributes \(Int(topShare * 100))% of records, so app-specific behavior may look like whole-life behavior.") }
        if datedRatio < 0.40 { details.append("Only \(Int(datedRatio * 100))% of records have usable timestamps, limiting trend analysis.") }
        if spanDays < 90 { details.append("The dated timeline spans under 90 days, so long-term stability cannot be established.") }
        if sourceCounts.count < 2 { details.append("Only one source is represented; cross-source confirmation is impossible.") }
        let messageShare = Double(records.filter { $0.kind == .message }.count) / Double(max(records.count,1))
        if messageShare > 0.60 { details.append("Messages dominate the dataset; conversation partners' text may be present and must not be treated as your own personality evidence.") }
        if details.isEmpty { details.append("No major representativeness warning crossed NEXUS's current thresholds, but missing apps and unexported offline life remain unobserved.") }
        return .init(title: "Bias, contradictions & uncertainty", summary: "NEXUS explicitly tracks what could make an apparently strong pattern misleading. These warnings reduce confidence instead of being hidden behind a single score.", details: details, confidence: 0.99)
    }

    private static func personalityBands(records: [KnowledgeRecord], domainSignals: [DomainSignal], sourceCount: Int, topShare: Double, spanDays: Double) -> [NexusTraitBand] {
        let selfKinds: Set<KnowledgeRecord.Kind> = [.search,.saved,.post,.comment,.follow,.event,.reminder,.note,.music,.activity]
        let selfEvidence = records.filter { selfKinds.contains($0.kind) }
        let sourceBreadth = Set(selfEvidence.map(\.source)).count
        let base = clamp01(0.15 + min(0.30, Double(selfEvidence.count) / 1500.0) + min(0.22, Double(sourceBreadth) / 4.0) + min(0.13, spanDays / 365.0) - max(0, topShare - 0.75) * 0.25)

        let topDomainCount = domainSignals.filter { $0.confidence >= 0.45 }.count
        let searches = selfEvidence.filter { $0.kind == .search }.count
        let saves = selfEvidence.filter { $0.kind == .saved }.count
        let structured = selfEvidence.filter { [.event,.reminder].contains($0.kind) }.count
        let socialActions = selfEvidence.filter { [.follow,.comment].contains($0.kind) }.count

        let opennessEstimate = clampInt(48 + min(30, topDomainCount * 4 + min(searches, 12) + min(saves / 3, 10)))
        let conscientiousEstimate = clampInt(48 + min(30, structured / 2))
        let socialEstimate = clampInt(48 + min(24, socialActions / 4))

        func band(_ estimate: Int, confidence: Double) -> (Int, Int) {
            let width = Int(round(30 - confidence * 20))
            return (max(5, estimate - width), min(95, estimate + width))
        }

        let openConf = min(0.82, base + min(0.18, Double(topDomainCount) / 20.0))
        let conConf = min(0.78, base + min(0.18, Double(structured) / 120.0))
        let socialConf = min(0.66, base + min(0.12, Double(socialActions) / 200.0))
        let ob = band(opennessEstimate, confidence: openConf)
        let cb = band(conscientiousEstimate, confidence: conConf)
        let sb = band(socialEstimate, confidence: socialConf)

        return [
            .init(id: "openness", name: "Openness / curiosity", estimate: opennessEstimate, low: ob.0, high: ob.1, confidence: openConf,
                  rationale: "Estimated mostly from breadth of sustained interests, searches, saves, learning-oriented actions and creative/technical exploration—not from other people's message text.",
                  evidence: ["\(topDomainCount) reasonably supported interest domains", "\(searches) search records", "\(saves) saved-item records", "\(sourceBreadth) self-action evidence sources"]),
            .init(id: "conscientiousness", name: "Conscientiousness / structure", estimate: structured >= 5 ? conscientiousEstimate : nil, low: structured >= 5 ? cb.0 : nil, high: structured >= 5 ? cb.1 : nil, confidence: structured >= 5 ? conConf : 0.18,
                  rationale: structured >= 5 ? "Estimated from reminders, calendar events and other structured planning evidence." : "There is not enough planning/task evidence to make a realistic estimate.",
                  evidence: ["\(structured) event/reminder records"]),
            .init(id: "extraversion", name: "Social orientation", estimate: socialActions >= 10 ? socialEstimate : nil, low: socialActions >= 10 ? sb.0 : nil, high: socialActions >= 10 ? sb.1 : nil, confidence: socialActions >= 10 ? socialConf : 0.16,
                  rationale: socialActions >= 10 ? "A cautious estimate from your observable social actions. Message volume alone is not treated as extraversion." : "Current data does not separate your social behavior from the archive's conversation volume well enough.",
                  evidence: ["\(socialActions) follow/comment actions", "\(sourceCount) total sources"]),
            .init(id: "agreeableness", name: "Agreeableness / cooperative style", estimate: nil, low: nil, high: nil, confidence: 0.12,
                  rationale: "NEXUS will not infer this from mixed Messenger/Instagram conversations because much of the language may belong to other people. Self-authored text identification is required first.", evidence: ["Mixed-participant message archives excluded from this trait"]),
            .init(id: "emotional", name: "Emotional stability / sensitivity", estimate: nil, low: nil, high: nil, confidence: 0.10,
                  rationale: "A realistic estimate would require reliably identified self-authored language across time. NEXUS avoids turning general archive text into a mental-health-like conclusion.", evidence: ["Insufficient self-authored longitudinal evidence"])
        ]
    }

    private static func limitationList(sourceCount: Int, topSource: (key: String, value: Int)?, topShare: Double, datedRatio: Double, spanDays: Double, records: [KnowledgeRecord]) -> [String] {
        var out: [String] = []
        if sourceCount < 3 { out.append("Cross-source confidence is limited because fewer than three independent sources are represented.") }
        if let topSource, topShare > 0.65 { out.append("\(topSource.key) dominates the vault, so some conclusions may describe that app more than your whole life.") }
        if datedRatio < 0.5 { out.append("Sparse timestamps reduce confidence in trends and routines.") }
        if spanDays < 180 { out.append("A longer timeline would better distinguish stable traits from temporary phases.") }
        if records.contains(where: { $0.kind == .message }) { out.append("Conversation archives contain other people's messages; NEXUS does not assume all message text was written by you.") }
        out.append("Offline behavior, deleted content, private apps and anything not exported remain outside the model.")
        return out
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !stopwords.contains($0) }
    }

    private static func medianInt(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        if s.count % 2 == 1 { return s[s.count / 2] }
        return (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private static func naturalJoin<S: Sequence>(_ values: S) -> String where S.Element == String {
        let v = Array(values)
        if v.isEmpty { return "none yet" }
        if v.count == 1 { return v[0] }
        if v.count == 2 { return v[0] + " and " + v[1] }
        return v.dropLast().joined(separator: ", ") + ", and " + v.last!
    }

    private static func confidenceWord(_ value: Double) -> String {
        switch value {
        case 0..<0.35: return "low"
        case 0.35..<0.60: return "moderate"
        case 0.60..<0.80: return "good"
        default: return "high"
        }
    }

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func clampInt(_ x: Int) -> Int { min(95, max(5, x)) }
}

extension NexusModel {
    var comprehensiveReport: NexusV4Report { ComprehensiveAnalysisEngine.analyze(records) }
}
