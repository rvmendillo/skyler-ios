import Foundation
import SwiftUI

struct NexusV7PreparedAnalysis: @unchecked Sendable {
    let package: NexusAnswerPackage
    let life: NexusLifeAnalysisReport
    let standardized: NexusStandardizationReport
}

private struct NexusV7AnalysisSnapshot: @unchecked Sendable {
    let comprehensive: NexusV4Report
    let personality: NexusPersonalityReport
    let life: NexusLifeAnalysisReport
    let standardized: NexusStandardizationReport
}

private struct NexusV7AnalysisCacheKey: Hashable, Sendable {
    let count: Int
    let firstID: String
    let middleID: String
    let lastID: String
    let firstTime: TimeInterval?
    let lastTime: TimeInterval?

    init(records: [KnowledgeRecord]) {
        count = records.count
        firstID = records.first?.id ?? ""
        middleID = records.isEmpty ? "" : records[records.count / 2].id
        lastID = records.last?.id ?? ""
        firstTime = records.first?.timestamp?.timeIntervalSince1970
        lastTime = records.last?.timestamp?.timeIntervalSince1970
    }
}

private actor NexusV7AnalysisCache {
    static let shared = NexusV7AnalysisCache()

    private var cachedKey: NexusV7AnalysisCacheKey?
    private var cachedSnapshot: NexusV7AnalysisSnapshot?

    func snapshot(for records: [KnowledgeRecord]) async -> NexusV7AnalysisSnapshot {
        let key = NexusV7AnalysisCacheKey(records: records)
        if key == cachedKey, let cachedSnapshot { return cachedSnapshot }

        let snapshot = await Task.detached(priority: .userInitiated) {
            // Keep the expensive, question-independent analysis off the main actor and
            // compute it only once per vault revision. The report objects are compact;
            // the large source array is not retained by this cache.
            let comprehensive = ComprehensiveAnalysisEngine.analyze(records)
            let personality = DataPersonalityEngine.analyze(records)
            let life = NexusLifeAnalysisEngine.analyze(records)
            let standardized = NexusStandardizationEngine.report(records)
            return NexusV7AnalysisSnapshot(comprehensive: comprehensive,
                                           personality: personality,
                                           life: life,
                                           standardized: standardized)
        }.value

        cachedKey = key
        cachedSnapshot = snapshot
        return snapshot
    }

    func invalidate() {
        cachedKey = nil
        cachedSnapshot = nil
    }
}

enum NexusV7AnswerEngine {
    static func prepare(question: String, records: [KnowledgeRecord]) async -> NexusV7PreparedAnalysis {
        let snapshot = await NexusV7AnalysisCache.shared.snapshot(for: records)
        let package = await Task.detached(priority: .userInitiated) {
            NexusReasoner.package(question: question,
                                  records: records,
                                  overallSummary: snapshot.comprehensive.overall,
                                  personality: snapshot.personality)
        }.value
        return NexusV7PreparedAnalysis(package: package,
                                       life: snapshot.life,
                                       standardized: snapshot.standardized)
    }

    static func answer(question: String, records: [KnowledgeRecord]) async -> NexusEnsembleResult {
        let prepared = await prepare(question: question, records: records)
        let base = await NexusLocalEnsemble.analyze(question: question,
                                                    records: records,
                                                    base: prepared.package,
                                                    life: prepared.life,
                                                    standardized: prepared.standardized)

        let store = await MainActor.run { NexusPortableModelStore.shared }
        let portableModels = await MainActor.run { store.ensembleModels() }
        guard !portableModels.isEmpty else { return base }

        var portableOpinions: [NexusModelOpinion] = []
        portableOpinions.reserveCapacity(portableModels.count)
        let sharedPortableContext = prepared.package.context + "\nLIFE: " + prepared.life.overall + "\nBASE ENSEMBLE: " + base.answer
        for model in portableModels {
            if let opinion = await store.opinionFromModel(model, question: question, context: sharedPortableContext) {
                portableOpinions.append(opinion)
            }
        }
        guard !portableOpinions.isEmpty else { return base }

        let allOpinions = base.opinions + portableOpinions
        let goodPortable = portableOpinions.filter { $0.confidence >= 0.45 }
        let portableText = portableOpinions.map { "\($0.model): \($0.finding)" }.joined(separator: "\n")
        let synthesisContext = """
        ORIGINAL LOCAL ENSEMBLE:
        \(base.answer)

        ADDITIONAL PORTABLE LOCAL LLM OPINIONS:
        \(portableText)

        EVIDENCE CONTEXT:
        \(String(prepared.package.context.prefix(6000)))
        """

        let finalAnswer: String
        if let apple = await NexusIntelligenceEngine.respond(
            question: "Synthesize these independent on-device opinions for: \(question). Prefer claims supported by multiple engines, preserve uncertainty, and do not invent personal facts.",
            context: synthesisContext
        ), !apple.isEmpty {
            finalAnswer = apple
        } else if let portableSynthesis = await store.respond(
            "Synthesize these independent opinions conservatively for the user's question: \(question)\n\n\(portableText)\n\nBase: \(base.answer)",
            systemContext: "Prefer cross-model agreement and supplied evidence. Mark low-evidence claims as provisional."
        ), !portableSynthesis.isEmpty {
            finalAnswer = portableSynthesis
        } else {
            let extras = goodPortable.map { "\($0.model): \($0.finding)" }.joined(separator: "\n\n")
            finalAnswer = extras.isEmpty ? base.answer : base.answer + "\n\nPortable local-model cross-checks:\n" + extras
        }

        let portableAvg = portableOpinions.map(\.confidence).reduce(0,+) / Double(max(portableOpinions.count, 1))
        let consensus = min(0.97, base.consensus * 0.70 + portableAvg * 0.30)
        var disagreements = base.disagreements
        if portableOpinions.contains(where: { $0.confidence < 0.25 }) {
            disagreements.append("At least one optional GGUF model returned a low-confidence or failed opinion; it was down-weighted.")
        }
        let evidence = Array(Set(base.evidence + portableOpinions.flatMap(\.evidence) + ["Portable LLM cross-checks: \(portableOpinions.count)"])).prefix(16).map { $0 }
        return NexusEnsembleResult(answer: finalAnswer, consensus: consensus, opinions: allOpinions, disagreements: disagreements, evidence: evidence)
    }
}

extension NexusModel {
    func askV7(_ raw: String) async {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        chatMessages.append(ChatMessage(role: .user, text: clean, evidence: []))
        let result = await NexusV7AnswerEngine.answer(question: clean, records: records)
        var evidence = result.evidence
        evidence.insert("Multi-engine consensus: \(Int(result.consensus * 100))%", at: 0)
        if !result.disagreements.isEmpty {
            evidence.append(contentsOf: result.disagreements.prefix(4).map { "Caveat: \($0)" })
        }
        chatMessages.append(ChatMessage(role: .assistant, text: result.answer, evidence: Array(evidence.prefix(18))))
    }
}

struct AskV7View: View {
    @EnvironmentObject var model: NexusModel
    @State private var draft = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "brain.head.profile.fill").foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXUS Ensemble").font(.headline)
                    Text("Apple/on-device NLP + statistics + enabled GGUF models").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink { PortableModelsV7View() } label: { Image(systemName: "cpu") }
            }.padding().background(.thinMaterial)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 11) {
                        ForEach(model.chatMessages) { message in
                            HStack {
                                if message.role == .user { Spacer(minLength: 46) }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(message.text).textSelection(.enabled)
                                    if !message.evidence.isEmpty {
                                        DisclosureGroup("Evidence & model notes") {
                                            VStack(alignment: .leading, spacing: 4) {
                                                ForEach(Array(message.evidence.enumerated()), id: \.offset) { _, item in
                                                    Text("• \(item)").font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }.padding(.top, 4)
                                        }.font(.caption.bold()).tint(.cyan)
                                    }
                                }
                                .padding(12)
                                .background(message.role == .user ? Color.cyan.opacity(0.20) : Color.secondary.opacity(0.11), in: RoundedRectangle(cornerRadius: 17))
                                if message.role == .assistant { Spacer(minLength: 46) }
                            }.id(message.id)
                        }
                        if busy {
                            HStack { ProgressView(); Text("Comparing local models and evidence…").font(.caption).foregroundStyle(.secondary); Spacer() }.padding()
                        }
                    }.padding()
                }
                .onChange(of: model.chatMessages.count) { _, _ in
                    if let last = model.chatMessages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your data, patterns, personality, goals…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                Button {
                    let text = draft
                    draft = ""
                    busy = true
                    Task { await model.askV7(text); busy = false }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding().background(.ultraThinMaterial)
        }
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
    }
}
