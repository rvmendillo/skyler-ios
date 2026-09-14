import Foundation
import SwiftUI

struct NexusSynthesisDomainScore: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let evidenceCount: Int
    let sourceCount: Int
    let recentCount: Int
    let strength: Double
}

enum NexusSynthesisClaimKind: String, CaseIterable, Identifiable, Hashable {
    case observed = "Observed"
    case derived = "Derived"
    case inferred = "Inferred"
    case hypothesis = "Hypothesis"
    case prediction = "Prediction"
    var id: String { rawValue }
}

struct NexusSynthesisFinding: Identifiable, Hashable {
    let id: UUID
    let title: String
    let summary: String
    let kind: NexusSynthesisClaimKind
    let confidence: Double
    let domains: [String]
    let evidence: [NexusV9Citation]
}

@MainActor
final class NexusSynthesisStore: ObservableObject {
    static let shared = NexusSynthesisStore()

    @Published private(set) var domainScores: [NexusSynthesisDomainScore] = []
    @Published private(set) var findings: [NexusSynthesisFinding] = []
    @Published private(set) var sourceCount = 0
    @Published private(set) var evidenceCount = 0
    @Published private(set) var datedEvidenceCount = 0
    @Published private(set) var timeSpanDays = 0
    @Published private(set) var lastGenerated: Date?
    @Published var narrative = ""
    @Published var narrativeEvidence: [String] = []
    @Published var status = "Ready to synthesize"
    @Published var generating = false

    private struct DomainDefinition {
        let name: String
        let symbol: String
        let keywords: Set<String>
    }

    private let definitions: [DomainDefinition] = [
        .init(name: "Career & Work", symbol: "briefcase.fill", keywords: ["work","career","job","role","project","client","company","github","code","software","developer","engineer","build","business","interview","resume","linkedin"]),
        .init(name: "Finance", symbol: "banknote.fill", keywords: ["bank","payment","expense","budget","money","transaction","spend","income","salary","finance","investment","invest","saving","savings","credit","crypto","eth","cash"]),
        .init(name: "Learning", symbol: "book.fill", keywords: ["learn","learning","course","study","school","research","notes","practice","skill","certification","training","exam","knowledge","read","reading"]),
        .init(name: "Health & Wellness", symbol: "heart.fill", keywords: ["health","sleep","workout","fitness","exercise","steps","calorie","medical","medicine","symptom","doctor","wellness","diet","rest"]),
        .init(name: "Travel", symbol: "airplane", keywords: ["travel","trip","flight","hotel","booking","airport","vacation","visa","tour","train","mrt","airline","destination","transfer"]),
        .init(name: "Relationships & Social", symbol: "person.2.fill", keywords: ["family","friend","friends","message","conversation","relationship","contact","people","social","team","parent","partner","colleague","coworker"]),
        .init(name: "Creative Life", symbol: "paintpalette.fill", keywords: ["music","piano","photo","video","design","art","writing","creative","compose","composition","film","movie","aesthetic","story","poem"]),
        .init(name: "Goals & Productivity", symbol: "target", keywords: ["task","calendar","meeting","deadline","plan","goal","goals","routine","productivity","todo","schedule","priority","milestone","habit","decision"]),
        .init(name: "Technology & AI", symbol: "cpu.fill", keywords: ["ai","model","software","code","github","app","ios","nexus","automation","tool","llm","swift","xcode","api","data","computer","programming"]),
        .init(name: "Lifestyle & Interests", symbol: "sparkles", keywords: ["food","restaurant","home","shopping","daily","hobby","weekend","game","games","fashion","clothes","coffee","meal","entertainment"])
    ]

    private init() {}

    func rebuild(from intelligence: NexusV9IntelligenceStore) {
        let chunks = intelligence.chunks
        evidenceCount = chunks.count
        sourceCount = Set(chunks.map(\.sourceID)).count
        let dates = chunks.compactMap(\.timestamp).sorted()
        datedEvidenceCount = dates.count
        if let first = dates.first, let last = dates.last {
            timeSpanDays = max(0, Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0)
        } else { timeSpanDays = 0 }

        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        var scores: [NexusSynthesisDomainScore] = []
        var chunkDomains: [String:Set<String>] = [:]

        for definition in definitions {
            var matched = 0
            var recent = 0
            var sources = Set<String>()
            for chunk in chunks {
                let words = tokenSet(chunk.title + " " + chunk.text)
                let hits = words.intersection(definition.keywords).count
                guard hits > 0 else { continue }
                matched += min(3, hits)
                sources.insert(chunk.sourceID)
                if let date = chunk.timestamp, date >= cutoff { recent += min(3, hits) }
                chunkDomains[chunk.id, default: []].insert(definition.name)
            }
            guard matched > 0 else { continue }
            let breadth = min(1.0, Double(sources.count) / 12.0)
            let recurrence = min(1.0, log(Double(matched) + 1.0) / log(80.0))
            scores.append(.init(id: definition.name, name: definition.name, symbol: definition.symbol, evidenceCount: matched, sourceCount: sources.count, recentCount: recent, strength: 0.55 * recurrence + 0.45 * breadth))
        }
        domainScores = scores.sorted { $0.strength > $1.strength }
        findings = buildFindings(chunks: chunks, scores: domainScores, chunkDomains: chunkDomains)
        status = chunks.isEmpty ? "Import or connect data to build your synthesis" : "Synthesis model updated from \(chunks.count) indexed evidence chunks"
    }

    func generateNarrative(records: [KnowledgeRecord]) async {
        let intelligence = NexusV9IntelligenceStore.shared
        rebuild(from: intelligence)
        guard !intelligence.chunks.isEmpty else { return }
        generating = true
        status = "Building deep whole-person synthesis…"
        defer { generating = false }

        let context = assistantContext(intelligence: intelligence, includeEvidence: true)
        let question = """
        Create a holistic synthesis of all the supplied NEXUS personal evidence. This is not a list of dashboards. Explain what the evidence collectively suggests across domains and across time.

        Organize the answer under: Whole-Person Model, Current Chapter, Core Patterns, Emerging Patterns, Connections Across Domains, Tensions & Contradictions, Trajectory, Drivers, Strengths, Constraints, Opportunities, and Unknowns.

        For important claims, explicitly label the epistemic status as Observed, Derived, Inferred, Hypothesis, or Prediction. Keep predictions tentative. Do not diagnose medical or mental-health conditions, do not infer protected traits, and do not invent facts. If evidence is sparse or conflicting, say so. Prefer patterns supported by multiple independent sources and different time periods.
        """
        let answer = await NexusV9Assistant.shared.answer(question: question, records: records, extraContext: context)
        narrative = answer.text
        narrativeEvidence = answer.evidence
        lastGenerated = Date()
        status = "Deep synthesis ready"
    }

    func assistantContextIfNeeded(for question: String, intelligence: NexusV9IntelligenceStore) -> String {
        let q = question.lowercased()
        let triggers = ["synthesis","synthesize","all my data","across my data","across everything","collectively","overall pattern","biggest pattern","whole person","whole-person","what changed most","contradiction","contradictions","trajectory","who am i","model of me","current chapter","connect the dots","holistic"]
        guard triggers.contains(where: { q.contains($0) }) else { return "" }
        rebuild(from: intelligence)
        return assistantContext(intelligence: intelligence, includeEvidence: true)
    }

    func assistantContext(intelligence: NexusV9IntelligenceStore, includeEvidence: Bool) -> String {
        if domainScores.isEmpty && !intelligence.chunks.isEmpty { rebuild(from: intelligence) }
        var lines: [String] = []
        lines.append("NEXUS WHOLE-PERSON SYNTHESIS MODEL")
        lines.append("Coverage: \(evidenceCount) indexed evidence chunks, \(sourceCount) source records/items, \(datedEvidenceCount) dated items, \(timeSpanDays)-day observed span.")
        if !domainScores.isEmpty {
            lines.append("Domain signals: " + domainScores.prefix(8).map { "\($0.name)=\(Int($0.strength * 100))% strength / \($0.sourceCount) sources / \($0.recentCount) recent signals" }.joined(separator: "; "))
        }
        for finding in findings.prefix(8) {
            lines.append("[\(finding.kind.rawValue) • \(Int(finding.confidence * 100))%] \(finding.title): \(finding.summary)")
        }
        guard includeEvidence else { return lines.joined(separator: "\n") }
        lines.append("REPRESENTATIVE CROSS-SOURCE / CROSS-TIME EVIDENCE:")
        for chunk in representativeChunks(from: intelligence.chunks, limit: 28) {
            let stamp = chunk.timestamp?.formatted(date: .abbreviated, time: .omitted) ?? "undated"
            lines.append("[\(chunk.sourceName) • \(chunk.location) • \(stamp)] \(String(chunk.text.replacingOccurrences(of: "\n", with: " ").prefix(520)))")
        }
        return String(lines.joined(separator: "\n\n").prefix(17_000))
    }

    private func buildFindings(chunks: [NexusV9Chunk], scores: [NexusSynthesisDomainScore], chunkDomains: [String:Set<String>]) -> [NexusSynthesisFinding] {
        guard !chunks.isEmpty else { return [] }
        var output: [NexusSynthesisFinding] = []

        if !scores.isEmpty {
            let top = Array(scores.prefix(3))
            let names = top.map(\.name)
            let cites = citations(for: names, chunks: chunks, chunkDomains: chunkDomains, limit: 6)
            let breadth = min(1.0, Double(Set(cites.map(\.sourceID)).count) / 5.0)
            output.append(.init(id: UUID(), title: "Strongest recurring themes", summary: "The highest recurring evidence clusters are \(names.joined(separator: ", ")). This describes where the indexed record is densest, not necessarily what matters most to you.", kind: .derived, confidence: min(0.96, 0.62 + 0.30 * breadth), domains: names, evidence: cites))
        }

        let cutoff60 = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let recentScores = scores.filter { $0.recentCount > 0 }.sorted { $0.recentCount > $1.recentCount }
        if let first = recentScores.first {
            let second = recentScores.dropFirst().first
            let names = [first.name] + (second.map { [$0.name] } ?? [])
            let cites = citations(for: names, chunks: chunks.filter { ($0.timestamp ?? .distantPast) >= cutoff60 }, chunkDomains: chunkDomains, limit: 5)
            output.append(.init(id: UUID(), title: "Current chapter", summary: "In the most recent 60-day evidence, \(names.joined(separator: " and ")) account for the strongest activity signals. Treat this as a description of the current data window rather than a permanent identity.", kind: .observed, confidence: confidence(evidence: cites, base: 0.64), domains: names, evidence: cites))
        }

        let totalRecent = max(1, scores.reduce(0) { $0 + $1.recentCount })
        let totalAll = max(1, scores.reduce(0) { $0 + $1.evidenceCount })
        let trajectory = scores.map { score -> (NexusSynthesisDomainScore, Double) in
            let recentShare = Double(score.recentCount) / Double(totalRecent)
            let overallShare = Double(score.evidenceCount) / Double(totalAll)
            return (score, recentShare - overallShare)
        }.sorted { $0.1 > $1.1 }
        if let rising = trajectory.first, rising.1 > 0.035 {
            let cites = citations(for: [rising.0.name], chunks: chunks, chunkDomains: chunkDomains, limit: 5)
            output.append(.init(id: UUID(), title: "Rising signal", summary: "\(rising.0.name) occupies a larger share of recent evidence than of the longer-term record, suggesting increased recent attention or activity.", kind: .inferred, confidence: confidence(evidence: cites, base: 0.56), domains: [rising.0.name], evidence: cites))
        }

        var pairCounts: [String:(Int,Set<String>)] = [:]
        for chunk in chunks {
            let domains = Array(chunkDomains[chunk.id, default: []]).sorted()
            guard domains.count >= 2 else { continue }
            for i in 0..<(domains.count - 1) {
                for j in (i + 1)..<domains.count {
                    let key = domains[i] + "|||" + domains[j]
                    var value = pairCounts[key, default: (0, [])]
                    value.0 += 1; value.1.insert(chunk.sourceID); pairCounts[key] = value
                }
            }
        }
        if let best = pairCounts.filter({ $0.value.1.count >= 2 }).max(by: { $0.value.0 < $1.value.0 }) {
            let names = best.key.components(separatedBy: "|||")
            let cites = citations(for: names, chunks: chunks.filter { Set(chunkDomains[$0.id, default: []]).isSuperset(of: Set(names)) }, chunkDomains: chunkDomains, limit: 6)
            output.append(.init(id: UUID(), title: "Cross-domain connection", summary: "\(names.joined(separator: " + ")) repeatedly appear in the same evidence. That co-occurrence is a useful candidate for a deeper common driver or shared project context.", kind: .inferred, confidence: min(0.90, 0.52 + Double(best.value.1.count) * 0.06), domains: names, evidence: cites))
        }

        for score in scores.prefix(5) {
            let relevant = chunks.filter { chunkDomains[$0.id, default: []].contains(score.name) }
            let dates = relevant.compactMap(\.timestamp).sorted()
            guard let first = dates.first, let last = dates.last else { continue }
            let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
            if span >= 180 && score.sourceCount >= 3 {
                let cites = citations(for: [score.name], chunks: relevant, chunkDomains: chunkDomains, limit: 5)
                output.append(.init(id: UUID(), title: "Persistent pattern", summary: "\(score.name) recurs across at least \(span) days and multiple sources, making it more likely to be a durable pattern than a short-lived spike.", kind: .derived, confidence: min(0.95, 0.66 + Double(score.sourceCount) * 0.035), domains: [score.name], evidence: cites))
                break
            }
        }

        if sourceCount < 4 || scores.count < 4 {
            output.append(.init(id: UUID(), title: "Important unknowns remain", summary: "The current model has limited source or domain breadth. Nexus should avoid treating missing data as evidence that a life area is unimportant or absent.", kind: .observed, confidence: 0.98, domains: [], evidence: Array(chunks.prefix(3).map(citation))))
        } else {
            let missing = definitions.map(\.name).filter { name in !scores.contains(where: { $0.name == name }) }
            if !missing.isEmpty {
                output.append(.init(id: UUID(), title: "Coverage gaps", summary: "There is little or no indexed evidence for \(missing.prefix(3).joined(separator: ", ")). Nexus treats these as unknowns rather than negative conclusions.", kind: .observed, confidence: 0.96, domains: Array(missing.prefix(3)), evidence: []))
            }
        }
        return output
    }

    private func citations(for domains: [String], chunks: [NexusV9Chunk], chunkDomains: [String:Set<String>], limit: Int) -> [NexusV9Citation] {
        let wanted = Set(domains)
        var chosen: [NexusV9Chunk] = []
        var seenSources = Set<String>()
        let ranked = chunks.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        for chunk in ranked where !wanted.isDisjoint(with: chunkDomains[chunk.id, default: []]) {
            if seenSources.insert(chunk.sourceID).inserted { chosen.append(chunk) }
            if chosen.count >= limit { break }
        }
        if chosen.count < limit {
            for chunk in ranked where !wanted.isDisjoint(with: chunkDomains[chunk.id, default: []]) && !chosen.contains(where: { $0.id == chunk.id }) {
                chosen.append(chunk)
                if chosen.count >= limit { break }
            }
        }
        return chosen.map(citation)
    }

    private func representativeChunks(from chunks: [NexusV9Chunk], limit: Int) -> [NexusV9Chunk] {
        let sorted = chunks.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        var selected: [NexusV9Chunk] = []
        var seenSources = Set<String>()
        for chunk in sorted {
            if seenSources.insert(chunk.sourceID).inserted { selected.append(chunk) }
            if selected.count >= limit / 2 { break }
        }
        if selected.count < limit {
            let stride = max(1, sorted.count / max(1, limit - selected.count))
            var i = 0
            while i < sorted.count && selected.count < limit {
                let chunk = sorted[i]
                if !selected.contains(where: { $0.id == chunk.id }) { selected.append(chunk) }
                i += stride
            }
        }
        return selected
    }

    private func citation(_ chunk: NexusV9Chunk) -> NexusV9Citation {
        NexusV9Citation(kind: chunk.kind, sourceID: chunk.sourceID, sourceName: chunk.sourceName, location: chunk.location, excerpt: String(chunk.text.prefix(420)), filePath: chunk.filePath)
    }

    private func confidence(evidence: [NexusV9Citation], base: Double) -> Double {
        min(0.95, base + Double(Set(evidence.map(\.sourceID)).count) * 0.045)
    }

    private func tokenSet(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 })
    }
}

struct NexusSynthesisView: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var synthesis = NexusSynthesisStore.shared
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                coverage
                if !synthesis.domainScores.isEmpty { domainMap }
                modelCard
                findings
                NavigationLink { NexusV9InsightInboxView() } label: {
                    Label("Open evidence-level Insight Inbox", systemImage: "lightbulb.max.fill")
                        .frame(maxWidth: .infinity, alignment: .leading).v7Panel()
                }.buttonStyle(.plain)
            }.padding()
        }
        .navigationTitle("Synthesis")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if intelligence.chunks.isEmpty && (!model.records.isEmpty || !NexusV8FileLibrary.shared.files.isEmpty) {
                await intelligence.index(records: model.records, files: NexusV8FileLibrary.shared.files)
            }
            synthesis.rebuild(from: intelligence)
        }
        .refreshable {
            await intelligence.index(records: model.records, files: NexusV8FileLibrary.shared.files, force: true)
            synthesis.rebuild(from: intelligence)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("MODEL OF ME", systemImage: "point.3.connected.trianglepath.dotted").font(.caption.bold()).foregroundStyle(.cyan)
            Text("What does everything Nexus knows collectively suggest?").font(.title2.weight(.bold))
            Text("A living, evidence-backed model across identity-relevant patterns, current state, trajectory, domains, connections and uncertainty. Missing data stays unknown.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button {
                    Task { await synthesis.generateNarrative(records: model.records) }
                } label: {
                    Label(synthesis.generating ? "Synthesizing…" : (synthesis.narrative.isEmpty ? "Generate deep synthesis" : "Refresh deep synthesis"), systemImage: "brain.head.profile.fill")
                }.buttonStyle(.borderedProminent).disabled(synthesis.generating || intelligence.chunks.isEmpty)
                if let date = synthesis.lastGenerated { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
            }
            Text(synthesis.status).font(.caption).foregroundStyle(.secondary)
        }.v7Panel()
    }

    private var coverage: some View {
        HStack(spacing: 8) {
            metric("Evidence", "\(synthesis.evidenceCount)", "square.stack.3d.up.fill")
            metric("Sources", "\(synthesis.sourceCount)", "tray.full.fill")
            metric("Domains", "\(synthesis.domainScores.count)", "circle.grid.3x3.fill")
            metric("Span", synthesis.timeSpanDays > 0 ? "\(synthesis.timeSpanDays)d" : "—", "calendar")
        }
    }

    private var domainMap: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Life-domain signal map").font(.headline)
            Text("Relative evidence strength, not a score of your worth or importance.").font(.caption).foregroundStyle(.secondary)
            ForEach(synthesis.domainScores.prefix(8)) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Label(item.name, systemImage: item.symbol).font(.subheadline.weight(.semibold)); Spacer(); Text("\(Int(item.strength * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    ProgressView(value: item.strength).tint(.cyan)
                    Text("\(item.sourceCount) sources • \(item.evidenceCount) total signals • \(item.recentCount) recent").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.v7Panel()
    }

    @ViewBuilder private var modelCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text("Whole-Person Model").font(.headline); Spacer(); if synthesis.generating { ProgressView() } }
            if synthesis.narrative.isEmpty {
                Text("The structural model above and findings below are computed locally from the full index. Generate the deep synthesis to turn those signals into one connected narrative with explicit uncertainty.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(synthesis.narrative).textSelection(.enabled)
                if !synthesis.narrativeEvidence.isEmpty {
                    DisclosureGroup("Narrative evidence") {
                        VStack(alignment: .leading, spacing: 5) { ForEach(synthesis.narrativeEvidence, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) } }
                    }.font(.caption.bold())
                }
            }
        }.v7Panel()
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Evidence-backed synthesis").font(.headline)
            ForEach(synthesis.findings) { finding in findingCard(finding) }
        }
    }

    private func findingCard(_ finding: NexusSynthesisFinding) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(finding.title).font(.headline)
                Spacer()
                Text("\(finding.kind.rawValue) • \(Int(finding.confidence * 100))%")
                    .font(.caption2.bold()).foregroundStyle(color(for: finding.kind))
                    .padding(.horizontal, 7).padding(.vertical, 4).background(color(for: finding.kind).opacity(0.12), in: Capsule())
            }
            Text(finding.summary).font(.subheadline)
            if !finding.domains.isEmpty { Text(finding.domains.joined(separator: " • ")).font(.caption).foregroundStyle(.cyan) }
            if !finding.evidence.isEmpty {
                DisclosureGroup("Why Nexus thinks this • \(finding.evidence.count) evidence items") {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(finding.evidence) { cite in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cite.sourceName + (cite.location.isEmpty ? "" : " • " + cite.location)).font(.caption.bold())
                                Text(cite.excerpt).font(.caption2).foregroundStyle(.secondary).lineLimit(5)
                            }
                        }
                    }.padding(.top, 4)
                }.font(.caption.bold())
            }
        }.v7Panel()
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Image(systemName: symbol).foregroundStyle(.cyan); Text(value).font(.headline).minimumScaleFactor(0.6); Text(title).font(.caption2).foregroundStyle(.secondary) }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }

    private func color(for kind: NexusSynthesisClaimKind) -> Color {
        switch kind { case .observed: return .green; case .derived: return .cyan; case .inferred: return .blue; case .hypothesis: return .orange; case .prediction: return .purple }
    }
}
