import Foundation

struct NexusLifeDimension: Identifiable, Hashable {
    let id: String
    let name: String
    let score: Double
    let confidence: Double
    let sourceBreadth: Int
    let evidenceCount: Int
    let trend: String
    let evidence: [String]
}

struct NexusLifeFinding: Identifiable, Hashable {
    enum Kind: String, Hashable { case strength, constraint, goal, direction, tension, blindSpot }
    let id: String
    let kind: Kind
    let title: String
    let summary: String
    let confidence: Double
    let rationale: [String]
    let alternatives: [String]
}

struct NexusLifeAnalysisReport: Hashable {
    let overall: String
    let evidenceQuality: Double
    let dimensions: [NexusLifeDimension]
    let strengths: [NexusLifeFinding]
    let weaknesses: [NexusLifeFinding]
    let inferredGoals: [NexusLifeFinding]
    let recommendedDirections: [NexusLifeFinding]
    let tensions: [NexusLifeFinding]
    let blindSpots: [NexusLifeFinding]
    let principles: [String]
}

enum NexusLifeAnalysisEngine {
    private struct DomainSpec {
        let id: String
        let name: String
        let words: [String]
        let preferredActions: Set<NexusCanonicalSignal.ActionFamily>
    }

    private static let domains: [DomainSpec] = [
        .init(id: "learning", name: "Learning & intellectual growth", words: ["learn","learning","course","study","research","why","how","book","read","science","math","philosophy","history","language","certification","school","university"], preferredActions: [.explore,.save,.organize]),
        .init(id: "career", name: "Career & craft", words: ["work","career","job","software","developer","engineer","coding","code","programming","project","portfolio","github","interview","skills","technical","build"], preferredActions: [.create,.plan,.organize,.explore]),
        .init(id: "creativity", name: "Creativity & expression", words: ["music","piano","compose","composition","art","design","creative","drawing","write","writing","story","photo","video","aesthetic","song"], preferredActions: [.create,.explore,.save]),
        .init(id: "relationships", name: "Relationships & community", words: ["friend","friends","family","relationship","people","team","social","birthday","together","message","conversation","contact"], preferredActions: [.communicate,.connect]),
        .init(id: "finance", name: "Financial security & optionality", words: ["money","saving","savings","invest","investment","budget","salary","interest","bank","credit","crypto","eth","finance","cash","income","million"], preferredActions: [.plan,.save,.explore,.organize]),
        .init(id: "health", name: "Health & physical wellbeing", words: ["health","sleep","exercise","walk","run","steps","fitness","food","diet","doctor","heart","activity","wellbeing"], preferredActions: [.wellbeing,.plan]),
        .init(id: "travel", name: "Travel & experience", words: ["travel","trip","flight","hotel","airport","tour","taiwan","japan","boracay","vacation","journey","visa","destination"], preferredActions: [.explore,.plan,.move,.save]),
        .init(id: "organization", name: "Structure & execution", words: ["plan","schedule","calendar","reminder","task","todo","organize","routine","goal","deadline","finish","complete","checklist"], preferredActions: [.plan,.organize]),
        .init(id: "technology", name: "Technology & experimentation", words: ["ai","app","ios","iphone","software","code","github","automation","api","model","local","widget","ipa","developer","programming"], preferredActions: [.create,.explore,.organize]),
        .init(id: "meaning", name: "Meaning & self-understanding", words: ["meaning","purpose","life","philosophy","personality","values","belief","mind","psychology","identity","happiness","satisfaction","goal"], preferredActions: [.explore,.save,.create])
    ]

    static func analyze(_ records: [KnowledgeRecord]) -> NexusLifeAnalysisReport {
        guard !records.isEmpty else {
            return NexusLifeAnalysisReport(overall: "NEXUS needs more evidence before making life-level recommendations.", evidenceQuality: 0, dimensions: [], strengths: [], weaknesses: [], inferredGoals: [], recommendedDirections: [], tensions: [], blindSpots: [], principles: ["No recommendation without evidence."])
        }

        let signals = NexusStandardizationEngine.standardize(records)
        let std = NexusStandardizationEngine.report(records)
        let newest = signals.compactMap(\.timestamp).max() ?? Date()
        let recentStart = Calendar.current.date(byAdding: .day, value: -120, to: newest) ?? newest
        let sourceCount = Set(signals.map(\.source)).count
        let datedRatio = Double(signals.compactMap(\.timestamp).count) / Double(max(signals.count, 1))
        let evidenceQuality = min(0.96, 0.18 + min(0.34, Double(sourceCount) * 0.07) + min(0.24, Double(signals.count) / 20_000.0) + min(0.20, datedRatio * 0.30))

        let dimensions = domains.map { domainScore($0, signals: signals, recentStart: recentStart) }.sorted { $0.score > $1.score }
        let strengths = buildStrengths(dimensions: dimensions, report: std)
        let weaknesses = buildConstraints(dimensions: dimensions, report: std, sourceCount: sourceCount)
        let goals = buildGoals(dimensions: dimensions)
        let directions = buildDirections(dimensions: dimensions, strengths: strengths, constraints: weaknesses, report: std)
        let tensions = buildTensions(dimensions: dimensions)
        let blindSpots = buildBlindSpots(dimensions: dimensions, signals: signals, sourceCount: sourceCount)

        let top = dimensions.prefix(3).map(\.name)
        let overall = "The strongest evidence-backed life domains are \(join(Array(top))). NEXUS treats these as current priorities or recurring attention, not as permanent identity. Recommendations are weighted by source diversity, persistence and recent momentum rather than raw record volume."

        return NexusLifeAnalysisReport(overall: overall,
                                       evidenceQuality: evidenceQuality,
                                       dimensions: dimensions,
                                       strengths: strengths,
                                       weaknesses: weaknesses,
                                       inferredGoals: goals,
                                       recommendedDirections: directions,
                                       tensions: tensions,
                                       blindSpots: blindSpots,
                                       principles: [
                                        "Observed behavior outranks self-description when the two conflict, but neither is treated as absolute truth.",
                                        "Independent sources outrank repeated records from one app.",
                                        "Long-term persistence outranks short spikes unless the spike is recent and broad across sources.",
                                        "Recommendations optimize for fit and optionality, not for a single imagined destiny.",
                                        "Weakness means a constraint, imbalance or under-supported area in the data—not a character judgment."
                                       ])
    }

    private static func domainScore(_ domain: DomainSpec, signals: [NexusCanonicalSignal], recentStart: Date) -> NexusLifeDimension {
        var matches: [NexusCanonicalSignal] = []
        for signal in signals {
            let hay = ([signal.subject] + signal.topics + signal.entities).joined(separator: " ").lowercased()
            let wordHit = domain.words.contains { hay.contains($0) }
            let actionHit = domain.preferredActions.contains(signal.action)
            if wordHit || (actionHit && signal.topics.contains(where: { domain.words.contains($0) })) { matches.append(signal) }
        }
        let sources = Set(matches.map(\.source))
        let dates = matches.compactMap(\.timestamp).sorted()
        let spanDays: Int
        if let first = dates.first, let last = dates.last { spanDays = max(0, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0) }
        else { spanDays = 0 }
        let recent = matches.filter { ($0.timestamp ?? .distantPast) >= recentStart }.count
        let older = max(0, matches.count - recent)
        let breadth = min(1.0, Double(sources.count) / 4.0)
        let recurrence = min(1.0, log(Double(matches.count) + 1) / log(70.0))
        let persistence = min(1.0, Double(spanDays) / 900.0)
        let recency = min(1.0, Double(recent) / Double(max(8, recent + older / 3)))
        let score = min(1.0, 0.34 * breadth + 0.30 * recurrence + 0.20 * persistence + 0.16 * recency)
        let confidence = min(0.94, 0.18 + 0.34 * breadth + 0.22 * recurrence + 0.18 * persistence + min(0.08, Double(matches.count)/500.0))
        let trend: String
        if recent >= max(4, older / 3) { trend = "rising/recent" }
        else if spanDays >= 365 { trend = "persistent" }
        else if matches.count >= 8 { trend = "recurring" }
        else { trend = "limited evidence" }
        let evidence = matches.prefix(6).map { signal in
            let date = signal.timestamp?.formatted(date: .abbreviated, time: .omitted) ?? "undated"
            return "\(date) • \(signal.source) • \(signal.action.rawValue): \(signal.subject)"
        }
        return NexusLifeDimension(id: domain.id, name: domain.name, score: score, confidence: confidence, sourceBreadth: sources.count, evidenceCount: matches.count, trend: trend, evidence: evidence)
    }

    private static func buildStrengths(dimensions: [NexusLifeDimension], report: NexusStandardizationReport) -> [NexusLifeFinding] {
        var out: [NexusLifeFinding] = []
        for d in dimensions.prefix(4) where d.confidence >= 0.40 {
            out.append(.init(id: "strength:\(d.id)", kind: .strength, title: d.name,
                             summary: "This domain is supported by repeated evidence across \(d.sourceBreadth) source\(d.sourceBreadth == 1 ? "" : "s") with a \(d.trend) pattern.",
                             confidence: d.confidence,
                             rationale: ["\(d.evidenceCount) matched standardized signals", "Evidence strength \(Int(d.score * 100))%"] + d.evidence.prefix(3),
                             alternatives: ["High activity can reflect data availability rather than skill; NEXUS therefore treats this as an evidence-backed strength or sustained orientation, not proof of ability."]))
        }
        if let cross = report.universalCharacteristics.first(where: { $0.kind == .crossSource && $0.score > 0.45 }) {
            out.append(.init(id: "strength:cross:\(cross.id)", kind: .strength, title: "Cross-context consistency",
                             summary: "“\(cross.label)” recurs across multiple independent sources, suggesting it is not confined to one app or one moment.", confidence: cross.score,
                             rationale: ["\(cross.sourceBreadth) sources", "\(cross.recordCount) signals", "~\(cross.timeSpanDays) day span"],
                             alternatives: ["The same topic may be imported into several apps, so provenance still matters."]))
        }
        return Array(out.prefix(6))
    }

    private static func buildConstraints(dimensions: [NexusLifeDimension], report: NexusStandardizationReport, sourceCount: Int) -> [NexusLifeFinding] {
        var out: [NexusLifeFinding] = []
        if sourceCount < 3 {
            out.append(.init(id: "constraint:coverage", kind: .constraint, title: "Narrow evidence coverage",
                             summary: "The vault does not yet represent enough independent parts of life for highly confident overall conclusions.", confidence: 0.92,
                             rationale: ["Only \(sourceCount) independent standardized sources"], alternatives: ["This is a data limitation, not a personal weakness."]))
        }
        let top = dimensions.first?.score ?? 0
        if top > 0.55, let low = dimensions.last, low.score < 0.18 {
            out.append(.init(id: "constraint:imbalance:\(low.id)", kind: .constraint, title: "Underrepresented: \(low.name)",
                             summary: "This area has much less observable support than your strongest domains. That may be a real imbalance or simply missing data.", confidence: min(0.75, 0.35 + top - low.score),
                             rationale: ["Observed score \(Int(low.score * 100))% vs strongest \(Int(top * 100))%", "Only \(low.evidenceCount) matched signals"],
                             alternatives: ["You may value this area privately or offline and simply not have connected a source that captures it."]))
        }
        let actions = report.dominantActions
        if let first = actions.first, first.count > max(20, report.signalCount / 2) {
            out.append(.init(id: "constraint:action-dominance", kind: .constraint, title: "One behavior dominates the dataset",
                             summary: "\(first.label) accounts for a large share of standardized activity, which can distort interpretation.", confidence: 0.88,
                             rationale: ["\(first.count) of \(report.signalCount) standardized signals"], alternatives: ["This may be an export artifact rather than a behavioral imbalance."]))
        }
        return Array(out.prefix(6))
    }

    private static func buildGoals(dimensions: [NexusLifeDimension]) -> [NexusLifeFinding] {
        dimensions.prefix(5).enumerated().map { index, d in
            let strength = index == 0 ? "primary" : index < 3 ? "strong" : "secondary"
            return NexusLifeFinding(id: "goal:\(d.id)", kind: .goal, title: d.name,
                                    summary: "Inferred as a \(strength) current goal/priority because attention to this domain is \(d.trend) and supported by \(d.evidenceCount) signals.",
                                    confidence: min(0.90, d.confidence), rationale: d.evidence.prefix(4),
                                    alternatives: ["Repeated attention may represent a problem to solve, obligation or curiosity rather than a desired goal. Treat this as a hypothesis to confirm, not a command."])
        }
    }

    private static func buildDirections(dimensions: [NexusLifeDimension], strengths: [NexusLifeFinding], constraints: [NexusLifeFinding], report: NexusStandardizationReport) -> [NexusLifeFinding] {
        guard let first = dimensions.first else { return [] }
        var out: [NexusLifeFinding] = []
        let second = dimensions.dropFirst().first
        if let second {
            out.append(.init(id: "direction:intersection", kind: .direction, title: "Build at the intersection of \(first.name) and \(second.name)",
                             summary: "The safest high-fit direction is usually where two independently strong domains overlap, because that preserves optionality and reduces dependence on a single interest spike.",
                             confidence: min(first.confidence, second.confidence),
                             rationale: ["\(first.name): \(Int(first.score*100))% evidence strength", "\(second.name): \(Int(second.score*100))% evidence strength"],
                             alternatives: ["If either domain is obligation-driven rather than intrinsically chosen, prefer the stronger voluntary domain instead."]))
        }
        if report.universalCharacteristics.contains(where: { $0.kind == .exploratory || $0.label == "Explore" }) {
            out.append(.init(id: "direction:experiments", kind: .direction, title: "Use small experiments before major commitments",
                             summary: "Your standardized data contains recurring exploratory behavior. Short projects, trials and prototypes are therefore a rational way to test directions while preserving flexibility.", confidence: 0.72,
                             rationale: ["Exploration appears as a recurring standardized action family"], alternatives: ["If external constraints require commitment, use explicit review checkpoints instead of endless exploration."]))
        }
        if constraints.contains(where: { $0.id.contains("coverage") }) {
            out.append(.init(id: "direction:data", kind: .direction, title: "Improve the evidence before optimizing your life around the model",
                             summary: "Connect more independent sources first. A recommendation engine is only as balanced as the life areas it can observe.", confidence: 0.94,
                             rationale: ["Current source coverage is below the preferred cross-source threshold"], alternatives: []))
        }
        return Array(out.prefix(5))
    }

    private static func buildTensions(dimensions: [NexusLifeDimension]) -> [NexusLifeFinding] {
        guard dimensions.count >= 2 else { return [] }
        var out: [NexusLifeFinding] = []
        let map = Dictionary(uniqueKeysWithValues: dimensions.map { ($0.id, $0) })
        if let career = map["career"], let travel = map["travel"], career.score > 0.35, travel.score > 0.35 {
            out.append(.init(id: "tension:career-travel", kind: .tension, title: "Stability vs experience",
                             summary: "Career/craft and travel/experience both receive meaningful attention. The practical tension is how to expand experience without weakening long-term craft or financial optionality.", confidence: min(career.confidence, travel.confidence),
                             rationale: ["Career \(Int(career.score*100))%", "Travel \(Int(travel.score*100))%"], alternatives: ["These domains can be complementary if work flexibility or remote options are available."]))
        }
        if let finance = map["finance"], let creativity = map["creativity"], finance.score > 0.35, creativity.score > 0.35 {
            out.append(.init(id: "tension:security-expression", kind: .tension, title: "Security vs creative freedom",
                             summary: "Both financial security and creative expression recur. A rational strategy is to protect a financial floor while giving creative work a bounded but real allocation of time/resources.", confidence: min(finance.confidence, creativity.confidence),
                             rationale: ["Finance \(Int(finance.score*100))%", "Creativity \(Int(creativity.score*100))%"], alternatives: ["If creative activity already contributes to career value, the tension may be smaller than it appears."]))
        }
        return out
    }

    private static func buildBlindSpots(dimensions: [NexusLifeDimension], signals: [NexusCanonicalSignal], sourceCount: Int) -> [NexusLifeFinding] {
        var out: [NexusLifeFinding] = []
        let undated = signals.filter { $0.timestamp == nil }.count
        if Double(undated) / Double(max(signals.count,1)) > 0.55 {
            out.append(.init(id: "blind:time", kind: .blindSpot, title: "Weak time context",
                             summary: "A large share of evidence lacks timestamps, so NEXUS cannot reliably distinguish enduring traits from temporary phases.", confidence: 0.95,
                             rationale: ["\(undated) of \(signals.count) standardized signals are undated"], alternatives: []))
        }
        let shallow = dimensions.filter { $0.sourceBreadth <= 1 && $0.evidenceCount > 0 }
        if !shallow.isEmpty {
            out.append(.init(id: "blind:single-source", kind: .blindSpot, title: "Single-source life domains",
                             summary: "Some inferred priorities appear in only one source. They should not be generalized to your whole life yet.", confidence: 0.90,
                             rationale: shallow.prefix(5).map { "\($0.name): \($0.evidenceCount) signals from \($0.sourceBreadth) source" }, alternatives: []))
        }
        if sourceCount >= 3 && dimensions.filter({ $0.score > 0.25 }).count <= 2 {
            out.append(.init(id: "blind:narrow", kind: .blindSpot, title: "Possible narrow-data lens",
                             summary: "Even with several sources, most evidence clusters into very few domains. This can be genuine specialization or a sign that connected apps capture only a subset of life.", confidence: 0.72,
                             rationale: ["Only \(dimensions.filter { $0.score > 0.25 }.count) domains exceed the moderate-evidence threshold"], alternatives: ["Strong specialization can be real and beneficial."]))
        }
        return out
    }

    private static func join(_ values: [String]) -> String {
        guard let last = values.last else { return "" }
        if values.count == 1 { return last }
        return values.dropLast().joined(separator: ", ") + " and " + last
    }
}

extension NexusModel {
    var lifeAnalysis: NexusLifeAnalysisReport { NexusLifeAnalysisEngine.analyze(records) }
}
