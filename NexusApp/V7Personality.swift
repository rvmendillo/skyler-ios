import Foundation
import SwiftUI
import NaturalLanguage

struct NexusPersonalityFacetV7: Identifiable, Hashable {
    let id: String
    let name: String
    let score: Int
    let low: Int
    let high: Int
    let confidence: Double
    let interpretation: String
    let evidence: [String]
    let caveats: [String]

    var evidenceLabel: String {
        switch confidence {
        case 0.70...: return "stronger evidence"
        case 0.40..<0.70: return "moderate evidence"
        case 0.20..<0.40: return "limited evidence"
        default: return "very provisional"
        }
    }
}

struct NexusPersonalityAxisV7: Identifiable, Hashable {
    let id: String
    let name: String
    let left: String
    let right: String
    let position: Double
    let confidence: Double
    let explanation: String
}

struct NexusPersonalityDeepReportV7: Hashable {
    let summary: String
    let facets: [NexusPersonalityFacetV7]
    let axes: [NexusPersonalityAxisV7]
    let communication: [String]
    let decisionStyle: [String]
    let contradictions: [String]
    let coverage: [String]
    let overallConfidence: Double
    let selfVoiceName: String?
}

enum NexusPersonalityDeepEngineV7 {
    static func analyze(records: [KnowledgeRecord], selfSpeakerID: String, selfReport: PersonalityProfile) -> NexusPersonalityDeepReportV7 {
        guard !records.isEmpty else {
            return .init(summary: "There is not enough behavioral evidence yet. NEXUS will still show very provisional estimates rather than hiding every dimension.",
                         facets: provisionalFacets(), axes: [], communication: [], decisionStyle: [], contradictions: ["No behavioral vault is available yet."], coverage: ["0 records"], overallConfidence: 0.05, selfVoiceName: nil)
        }

        let capped = Array(records.prefix(60_000))
        let standard = NexusStandardizationEngine.report(capped)
        let baseReport = ComprehensiveAnalysisEngine.analyze(capped)
        let voices = NexusConversationTwinEngine.availableVoices(records: capped)
        let selfVoice = voices.first(where: { $0.id == selfSpeakerID })
        let ownMessages = selfVoice.map { NexusConversationTwinEngine.messages(for: $0, records: capped) } ?? []

        let sourceCount = Set(capped.map(\.source)).count
        let dated = capped.compactMap(\.timestamp)
        let spanDays: Double = {
            guard let min = dated.min(), let max = dated.max() else { return 0 }
            return max.timeIntervalSince(min) / 86_400
        }()
        let baseConfidence = min(0.93,
                                 0.10 + min(0.28, Double(capped.count) / 16_000.0)
                                 + min(0.25, Double(sourceCount) * 0.055)
                                 + min(0.18, spanDays / 1_100.0)
                                 + min(0.12, Double(ownMessages.count) / 2_000.0))

        var facets = baseReport.traits.map { trait -> NexusPersonalityFacetV7 in
            let fallback = fallbackEstimate(for: trait.id, records: capped)
            let estimate = trait.estimate ?? fallback.score
            let confidence = trait.estimate == nil ? min(0.19, max(0.06, fallback.confidence)) : trait.confidence
            let width = max(10, Int(round(38 - confidence * 28)))
            let low = trait.low ?? max(5, estimate - width)
            let high = trait.high ?? min(95, estimate + width)
            let caveat = trait.estimate == nil
                ? ["This estimate is deliberately shown despite weak evidence. Treat the wide range as more important than the midpoint."]
                : []
            return .init(id: trait.id,
                         name: trait.name,
                         score: estimate,
                         low: low,
                         high: high,
                         confidence: confidence,
                         interpretation: trait.rationale,
                         evidence: trait.evidence + fallback.evidence,
                         caveats: caveat)
        }

        facets = enrichLanguageFacets(facets, selfVoice: selfVoice, ownMessages: ownMessages)

        let axes = buildAxes(records: capped, standard: standard, selfVoice: selfVoice)
        let communication = communicationSummary(selfVoice: selfVoice, ownMessages: ownMessages)
        let decision = decisionSummary(standard: standard, records: capped)
        let contradictions = contradictionSummary(facets: facets, selfReport: selfReport, standard: standard, selfVoice: selfVoice)
        let coverage = [
            "\(capped.count) analyzed records across \(sourceCount) sources",
            "\(dated.count) dated records over about \(Int(max(0, spanDays))) days",
            "\(standard.signalCount) standardized signals",
            selfVoice.map { "\($0.messageCount) self-identified conversation messages from \($0.displayName)" } ?? "No imported speaker has been marked as you; mixed conversation text is excluded from language-based traits"
        ]

        let ranked = facets.sorted { $0.confidence > $1.confidence }.prefix(3)
        let summary: String
        if ranked.isEmpty {
            summary = "NEXUS has only weak personality evidence so far. Estimates remain intentionally broad."
        } else {
            let description = ranked.map { "\($0.name) around \($0.score)/100 (\($0.evidenceLabel))" }.joined(separator: ", ")
            summary = "The current behavioral model is most informative for \(description). These are probabilistic behavioral estimates, not fixed identity labels. Low-evidence dimensions are still displayed with wider ranges so you can inspect the hypothesis instead of seeing a blank result."
        }

        let avgConfidence = facets.isEmpty ? baseConfidence : facets.map(\.confidence).reduce(0,+) / Double(facets.count)
        return .init(summary: summary, facets: facets, axes: axes, communication: communication, decisionStyle: decision, contradictions: contradictions, coverage: coverage, overallConfidence: min(0.95, avgConfidence * 0.7 + baseConfidence * 0.3), selfVoiceName: selfVoice?.displayName)
    }

    private static func provisionalFacets() -> [NexusPersonalityFacetV7] {
        [
            ("openness","Openness / curiosity"),
            ("conscientiousness","Conscientiousness / structure"),
            ("extraversion","Social orientation"),
            ("agreeableness","Cooperative communication"),
            ("emotional","Emotional expressiveness")
        ].map { id, name in
            .init(id: id, name: name, score: 50, low: 15, high: 85, confidence: 0.05,
                  interpretation: "Neutral prior shown because there is not enough behavioral evidence yet.", evidence: [], caveats: ["Very provisional midpoint; the uncertainty range is the meaningful part."])
        }
    }

    private static func fallbackEstimate(for id: String, records: [KnowledgeRecord]) -> (score: Int, confidence: Double, evidence: [String]) {
        let searches = records.filter { $0.kind == .search }.count
        let saves = records.filter { $0.kind == .saved }.count
        let plans = records.filter { [.event,.reminder].contains($0.kind) }.count
        let social = records.filter { [.follow,.comment,.contact].contains($0.kind) }.count
        switch id {
        case "openness":
            let score = min(85, 48 + min(20, searches / 4) + min(12, saves / 10))
            return (score, searches + saves > 0 ? 0.18 : 0.08, ["\(searches) searches", "\(saves) saved items"])
        case "conscientiousness":
            let score = min(82, 48 + min(28, plans / 3))
            return (score, plans > 0 ? 0.18 : 0.07, ["\(plans) calendar/reminder records"])
        case "extraversion":
            let score = min(78, 48 + min(22, social / 8))
            return (score, social > 0 ? 0.16 : 0.06, ["\(social) observable social actions"])
        case "agreeableness": return (50, 0.06, ["No self-authored language identity selected"])
        case "emotional": return (50, 0.05, ["No self-authored longitudinal language identity selected"])
        default: return (50, 0.05, [])
        }
    }

    private static func enrichLanguageFacets(_ facets: [NexusPersonalityFacetV7], selfVoice: NexusConversationVoice?, ownMessages: [KnowledgeRecord]) -> [NexusPersonalityFacetV7] {
        guard let selfVoice, !ownMessages.isEmpty else { return facets }
        let sample = Array(ownMessages.prefix(5_000))
        let joined = sample.map(\.text).joined(separator: " \n ").lowercased()
        let politeTerms = ["thanks","thank you","please","sorry","appreciate","welcome"]
        let collaborativeTerms = ["we","us","together","agree","sure","okay","ok","help"]
        let affectTerms = ["love","happy","sad","excited","angry","feel","feels","feeling","miss","worry","glad"]
        let polite = politeTerms.reduce(0) { $0 + joined.components(separatedBy: $1).count - 1 }
        let collab = collaborativeTerms.reduce(0) { $0 + joined.components(separatedBy: $1).count - 1 }
        let affect = affectTerms.reduce(0) { $0 + joined.components(separatedBy: $1).count - 1 }
        let messageCount = max(sample.count, 1)
        let cooperativeScore = clamp(48 + min(22, (polite + collab) * 100 / max(messageCount, 30)))
        let expressiveScore = clamp(45 + Int(selfVoice.exclamationRate * 25) + Int(selfVoice.emojiRate * 30) + min(20, affect * 100 / max(messageCount, 40)))
        let languageConfidence = min(0.82, 0.20 + min(0.50, log10(Double(messageCount) + 1) * 0.20) + min(0.12, Double(Set(sample.map(\.source)).count) * 0.04))
        let width = max(10, Int(round(35 - languageConfidence * 25)))

        return facets.map { facet in
            if facet.id == "agreeableness" {
                return .init(id: facet.id, name: "Cooperative communication", score: cooperativeScore,
                             low: max(5, cooperativeScore - width), high: min(95, cooperativeScore + width), confidence: languageConfidence,
                             interpretation: "Estimated from the self-identified speaker's politeness, collaborative wording and conversational patterns. This is communication behavior, not a moral judgment or proof of agreeableness in every setting.",
                             evidence: ["Self voice: \(selfVoice.displayName)", "\(messageCount) sampled messages", "\(polite) politeness markers", "\(collab) collaborative-word markers"],
                             caveats: ["Context matters: work chats, close-friend chats and group chats can produce different styles."])
            }
            if facet.id == "emotional" {
                return .init(id: facet.id, name: "Emotional expressiveness", score: expressiveScore,
                             low: max(5, expressiveScore - width), high: min(95, expressiveScore + width), confidence: languageConfidence,
                             interpretation: "Estimated from observable expression markers such as affect words, emoji and emphasis. It does not measure mental health, emotional stability or hidden internal state.",
                             evidence: ["Self voice: \(selfVoice.displayName)", "Emoji in \(Int(selfVoice.emojiRate*100))% of sampled messages", "Exclamation marks in \(Int(selfVoice.exclamationRate*100))%", "\(affect) affect-word markers"],
                             caveats: ["Texting style can differ sharply by audience and platform."])
            }
            return facet
        }
    }

    private static func buildAxes(records: [KnowledgeRecord], standard: NexusStandardizationReport, selfVoice: NexusConversationVoice?) -> [NexusPersonalityAxisV7] {
        let action = Dictionary(uniqueKeysWithValues: standard.dominantActions.map { ($0.label, $0.count) })
        let explore = Double(action["Explore"] ?? 0)
        let plan = Double((action["Plan"] ?? 0) + (action["Organize"] ?? 0))
        let create = Double(action["Create"] ?? 0)
        let consume = Double(action["Consume"] ?? 0)
        let communicate = Double((action["Communicate"] ?? 0) + (action["Connect"] ?? 0))
        let total = max(1, Double(standard.signalCount))

        func position(_ right: Double, _ left: Double) -> Double {
            let denom = max(1, right + left)
            return min(1, max(0, 0.5 + (right - left) / denom * 0.45))
        }

        var axes: [NexusPersonalityAxisV7] = [
            .init(id: "explore-plan", name: "Cognitive mode", left: "Structure", right: "Exploration", position: position(explore, plan), confidence: min(0.85, (explore + plan) / max(30, total * 0.15)), explanation: "Compares exploratory/search behavior with planning and organization signals."),
            .init(id: "consume-create", name: "Engagement mode", left: "Consume", right: "Create", position: position(create, consume), confidence: min(0.82, (create + consume) / max(30, total * 0.12)), explanation: "Compares captured creation with consumption activity."),
            .init(id: "solo-social", name: "Interaction footprint", left: "Independent", right: "Social", position: min(0.95, max(0.05, 0.35 + communicate / total * 1.6)), confidence: min(0.75, communicate / max(20, total * 0.15)), explanation: "Uses observable communication/connect actions, not message volume alone as proof of extraversion.")
        ]
        if let selfVoice {
            axes.append(.init(id: "brief-elaborate", name: "Conversation cadence", left: "Brief", right: "Elaborate", position: min(0.95, Double(selfVoice.averageWords) / 28.0), confidence: selfVoice.confidence, explanation: "Derived from the self-identified speaker's average message length."))
        }
        return axes
    }

    private static func communicationSummary(selfVoice: NexusConversationVoice?, ownMessages: [KnowledgeRecord]) -> [String] {
        guard let selfVoice else {
            return ["No imported speaker is marked as you, so NEXUS intentionally avoids attributing other people's wording to your personality.", "Choose your identity on this page or in Conversation Twin to unlock self-authored language analysis."]
        }
        return [
            selfVoice.styleSummary,
            "Questions appear in about \(Int(selfVoice.questionRate * 100))% of captured messages; emoji in \(Int(selfVoice.emojiRate * 100))%; emphatic punctuation in \(Int(selfVoice.exclamationRate * 100))%.",
            "Common opening vocabulary: \(selfVoice.commonOpeners.joined(separator: ", ")).",
            "The selected identity contributes \(ownMessages.count) self-attributed messages to language-based analysis."
        ]
    }

    private static func decisionSummary(standard: NexusStandardizationReport, records: [KnowledgeRecord]) -> [String] {
        let actions = standard.dominantActions.prefix(6)
        guard !actions.isEmpty else { return ["Not enough standardized action evidence yet."] }
        var out = ["Dominant observable action families: " + actions.map { "\($0.label) \($0.count)" }.joined(separator: " • ")]
        if let explore = actions.first(where: { $0.label == "Explore" }), explore.count > 10 { out.append("Repeated exploration suggests information gathering is a meaningful part of how choices are approached.") }
        if let plan = actions.first(where: { $0.label == "Plan" }), plan.count > 8 { out.append("Planning evidence suggests at least some decisions are externalized into calendars/reminders rather than kept purely mentally.") }
        if records.filter({ $0.kind == .saved }).count > 10 { out.append("Saved-item behavior suggests a tendency to preserve options or references for later evaluation.") }
        return out
    }

    private static func contradictionSummary(facets: [NexusPersonalityFacetV7], selfReport: PersonalityProfile, standard: NexusStandardizationReport, selfVoice: NexusConversationVoice?) -> [String] {
        let manual: [String:Int] = [
            "openness": Int(selfReport.openness),
            "conscientiousness": Int(selfReport.conscientiousness),
            "extraversion": Int(selfReport.extraversion),
            "agreeableness": Int(selfReport.agreeableness),
            "emotional": 100 - Int(selfReport.neuroticism)
        ]
        var out: [String] = []
        for facet in facets {
            guard let m = manual[facet.id], facet.confidence >= 0.20 else { continue }
            let delta = abs(m - facet.score)
            if delta >= 22 { out.append("Self-report and observed evidence differ on \(facet.name): self-report \(m), behavioral estimate \(facet.score). Treat the difference as a question to investigate, not a winner/loser comparison.") }
        }
        if standard.sourceCount < 3 { out.append("Fewer than three standardized sources means apparent personality patterns may still be app-specific.") }
        if selfVoice == nil { out.append("Language-based personality evidence remains deliberately conservative until your speaker identity is selected.") }
        if out.isEmpty { out.append("No large self-report/behavior contradiction crossed the current threshold. Smaller differences are still visible in each trait card.") }
        return out
    }

    private static func clamp(_ value: Int) -> Int { min(95, max(5, value)) }
}

struct NexusPersonalityRadarV7: View {
    let facets: [NexusPersonalityFacetV7]

    var body: some View {
        Canvas { context, size in
            let count = max(facets.count, 3)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.34

            for ring in 1...4 {
                var path = Path()
                for i in 0..<count {
                    let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(count)
                    let r = radius * CGFloat(ring) / 4
                    let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            }

            for i in 0..<count {
                let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(count)
                let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                var spoke = Path(); spoke.move(to: center); spoke.addLine(to: p)
                context.stroke(spoke, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            }

            guard facets.count >= 3 else { return }
            var shape = Path()
            for (i, facet) in facets.enumerated() {
                let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(facets.count)
                let r = radius * CGFloat(facet.score) / 100
                let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if i == 0 { shape.move(to: p) } else { shape.addLine(to: p) }
            }
            shape.closeSubpath()
            context.fill(shape, with: .color(.cyan.opacity(0.18)))
            context.stroke(shape, with: .color(.cyan), lineWidth: 2.5)
        }
        .frame(height: 250)
    }
}

struct PersonalityLabV7View: View {
    @EnvironmentObject var model: NexusModel
    @AppStorage("nexus.self.speakerID") private var selfSpeakerID = ""
    @State private var report: NexusPersonalityDeepReportV7?
    @State private var loading = true
    @State private var phase = "Preparing evidence…"

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if loading || report == nil {
                    VStack(spacing: 13) {
                        ProgressView().controlSize(.large)
                        Text("Building personality model").font(.headline)
                        Text(phase).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: loading ? 0.68 : 1).tint(.cyan)
                    }.padding(30).frame(maxWidth: .infinity).v7Panel()
                } else if let report {
                    header(report)
                    identityPicker(report)
                    NexusPersonalityRadarV7(facets: report.facets).v7Panel()
                    traitSection(report)
                    axisSection(report)
                    textSection("Communication style", "bubble.left.and.bubble.right.fill", report.communication)
                    textSection("Decision & information style", "brain.head.profile", report.decisionStyle)
                    selfReportSection(report)
                    textSection("Contradictions & competing explanations", "arrow.triangle.branch", report.contradictions)
                    textSection("Evidence coverage", "checkmark.shield.fill", report.coverage)
                }
            }.padding()
        }
        .navigationTitle("Personality Lab")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: analysisKey) { await rebuild() }
    }

    private var analysisKey: String { "\(model.records.count)|\(model.records.first?.id ?? "")|\(selfSpeakerID)" }

    @ViewBuilder private func header(_ report: NexusPersonalityDeepReportV7) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label("Behavioral personality model", systemImage: "person.crop.circle.badge.checkmark").font(.title2.bold()); Spacer(); Text("\(Int(report.overallConfidence*100))%").font(.caption.bold()).foregroundStyle(.cyan) }
            Text(report.summary).foregroundStyle(.secondary)
            ProgressView(value: report.overallConfidence).tint(.cyan)
            Text("Personality estimates are hypotheses from observable data. A low-confidence estimate is shown rather than hidden, but its wide range should be treated as the main result.").font(.caption).foregroundStyle(.tertiary)
        }.v7Panel()
    }

    @ViewBuilder private func identityPicker(_ report: NexusPersonalityDeepReportV7) -> some View {
        let voices = NexusConversationTwinEngine.availableVoices(records: model.records)
        VStack(alignment: .leading, spacing: 8) {
            Label("Which imported speaker is you?", systemImage: "person.badge.key.fill").font(.headline)
            Text("This prevents NEXUS from analyzing your contacts' language as if it were yours.").font(.caption).foregroundStyle(.secondary)
            Picker("Self identity", selection: $selfSpeakerID) {
                Text("Not selected").tag("")
                ForEach(voices) { voice in Text("\(voice.displayName) • \(voice.messageCount) messages").tag(voice.id) }
            }.pickerStyle(.menu)
            if let name = report.selfVoiceName { Label("Self-authored language enabled for \(name)", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
        }.v7Panel()
    }

    @ViewBuilder private func traitSection(_ report: NexusPersonalityDeepReportV7) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Core facets").font(.title3.bold())
            ForEach(report.facets) { facet in
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text(facet.name).font(.headline); Spacer(); Text("\(facet.score) [\(facet.low)–\(facet.high)]").font(.subheadline.bold()).foregroundStyle(facet.confidence < 0.20 ? .orange : .cyan) }
                    ProgressView(value: Double(facet.score), total: 100).tint(facet.confidence < 0.20 ? .orange : .cyan)
                    HStack { Text(facet.evidenceLabel.capitalized); Spacer(); Text("confidence \(Int(facet.confidence*100))%") }.font(.caption2).foregroundStyle(.secondary)
                    Text(facet.interpretation).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Evidence + caveats") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(facet.evidence.prefix(8), id: \.self) { Text("• \($0)").font(.caption2).foregroundStyle(.secondary) }
                            ForEach(facet.caveats, id: \.self) { Text("⚠︎ \($0)").font(.caption2).foregroundStyle(.orange) }
                        }.padding(.top, 5)
                    }.font(.caption.bold()).tint(.cyan)
                }
                if facet.id != report.facets.last?.id { Divider() }
            }
        }.v7Panel()
    }

    @ViewBuilder private func axisSection(_ report: NexusPersonalityDeepReportV7) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behavioral style axes").font(.title3.bold())
            ForEach(report.axes) { axis in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(axis.name).font(.headline); Spacer(); Text("\(Int(axis.confidence*100))%").font(.caption).foregroundStyle(.secondary) }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.secondary.opacity(0.16)).frame(height: 8)
                            Circle().fill(.cyan).frame(width: 16, height: 16).offset(x: max(0, geo.size.width * axis.position - 8))
                        }
                    }.frame(height: 18)
                    HStack { Text(axis.left); Spacer(); Text(axis.right) }.font(.caption2).foregroundStyle(.secondary)
                    Text(axis.explanation).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.v7Panel()
    }

    @ViewBuilder private func selfReportSection(_ report: NexusPersonalityDeepReportV7) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Self-report vs observed behavior").font(.title3.bold())
            Text("Self-report is kept separate; it does not overwrite the behavioral estimate.").font(.caption).foregroundStyle(.secondary)
            let values: [(String,Int)] = [
                ("Openness", Int(model.personality.openness)),
                ("Conscientiousness", Int(model.personality.conscientiousness)),
                ("Extraversion", Int(model.personality.extraversion)),
                ("Agreeableness", Int(model.personality.agreeableness)),
                ("Emotional stability", 100 - Int(model.personality.neuroticism))
            ]
            ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                let behavioral = report.facets.indices.contains(index) ? report.facets[index].score : 50
                HStack { Text(item.0).font(.caption); Spacer(); Text("Self \(item.1) • Data \(behavioral)").font(.caption.bold()).foregroundStyle(abs(item.1-behavioral) >= 20 ? .orange : .secondary) }
            }
            if !model.personality.mbti.isEmpty { Text("Saved self-reported MBTI: \(model.personality.mbti.uppercased()) • shown as self-description, not treated as a measured behavioral fact.").font(.caption2).foregroundStyle(.tertiary) }
        }.v7Panel()
    }

    @ViewBuilder private func textSection(_ title: String, _ symbol: String, _ rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.title3.bold())
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in Text("• \(row)").font(.subheadline).foregroundStyle(.secondary) }
        }.v7Panel()
    }

    private func rebuild() async {
        loading = true
        phase = "Standardizing cross-source behavior…"
        let records = model.records
        let speaker = selfSpeakerID
        let selfReport = model.personality
        let result = await Task.detached(priority: .userInitiated) {
            NexusPersonalityDeepEngineV7.analyze(records: records, selfSpeakerID: speaker, selfReport: selfReport)
        }.value
        phase = "Calibrating uncertainty…"
        report = result
        loading = false
    }
}
