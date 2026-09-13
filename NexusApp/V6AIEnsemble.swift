import Foundation
import NaturalLanguage

struct NexusModelOpinion: Identifiable, Hashable {
    let id: String
    let model: String
    let role: String
    let finding: String
    let confidence: Double
    let evidence: [String]
}

struct NexusEnsembleResult: Hashable {
    let answer: String
    let consensus: Double
    let opinions: [NexusModelOpinion]
    let disagreements: [String]
    let evidence: [String]
}

enum NexusLocalEnsemble {
    static let modelNames = [
        "Apple Foundation Model",
        "Apple Sentence Embeddings",
        "Apple Sentiment Model",
        "Apple Entity Tagger",
        "NEXUS Statistical Pattern Model",
        "NEXUS Cross-source Consensus Model"
    ]

    static func analyze(question: String, records: [KnowledgeRecord], base: NexusAnswerPackage, life: NexusLifeAnalysisReport, standardized: NexusStandardizationReport) async -> NexusEnsembleResult {
        var opinions: [NexusModelOpinion] = []
        let q = question.lowercased()
        let textCorpus = relevantText(records: records, question: question)

        let statistical = statisticalOpinion(question: q, life: life, standardized: standardized)
        opinions.append(statistical)

        let semantic = semanticOpinion(question: question, corpus: textCorpus)
        opinions.append(semantic)

        let sentiment = sentimentOpinion(corpus: textCorpus)
        opinions.append(sentiment)

        let entities = entityOpinion(corpus: textCorpus)
        opinions.append(entities)

        let consensus = consensusOpinion(opinions: opinions, standardized: standardized)
        opinions.append(consensus)

        let localContext = opinions.map { "MODEL=\($0.model); ROLE=\($0.role); CONFIDENCE=\(Int($0.confidence*100))%; FINDING=\($0.finding); EVIDENCE=\($0.evidence.joined(separator: " | "))" }.joined(separator: "\n")
        let lifeContext = """
        LIFE ANALYSIS: \(life.overall)
        EVIDENCE QUALITY: \(Int(life.evidenceQuality * 100))%
        TOP GOALS: \(life.inferredGoals.prefix(4).map(\.title).joined(separator: ", "))
        STRENGTHS: \(life.strengths.prefix(4).map(\.title).joined(separator: ", "))
        CONSTRAINTS: \(life.weaknesses.prefix(4).map(\.title).joined(separator: ", "))
        DIRECTIONS: \(life.recommendedDirections.prefix(4).map(\.title).joined(separator: ", "))
        """

        let promptContext = base.context + "\n\nLOCAL ENSEMBLE OPINIONS:\n" + localContext + "\n\n" + lifeContext
        let generated = await NexusIntelligenceEngine.respond(question: "Synthesize the local ensemble for this question: \(question). Resolve disagreements conservatively. Explicitly separate observed evidence, inference and recommendation. Do not infer sensitive/protected traits.", context: promptContext)

        let disagreements = findDisagreements(opinions)
        let score = ensembleConfidence(opinions: opinions, standardized: standardized)
        let answer: String
        if let generated, !generated.isEmpty {
            answer = generated
        } else {
            answer = localSynthesis(question: question, base: base, life: life, opinions: opinions, disagreements: disagreements)
        }
        let evidence = Array(Set(base.evidence + opinions.flatMap(\.evidence))).prefix(12).map { $0 }
        return NexusEnsembleResult(answer: answer, consensus: score, opinions: opinions, disagreements: disagreements, evidence: evidence)
    }

    private static func statisticalOpinion(question: String, life: NexusLifeAnalysisReport, standardized: NexusStandardizationReport) -> NexusModelOpinion {
        let finding: String
        var evidence: [String] = []
        if question.contains("goal") || question.contains("direction") || question.contains("life") {
            finding = life.overall
            evidence = life.inferredGoals.prefix(3).map { "\($0.title): \(Int($0.confidence*100))%" }
        } else if question.contains("strength") {
            finding = life.strengths.first?.summary ?? "No high-confidence strength signal yet."
            evidence = life.strengths.prefix(3).map(\.title)
        } else if question.contains("weak") || question.contains("constraint") {
            finding = life.weaknesses.first?.summary ?? "No strong constraint signal yet."
            evidence = life.weaknesses.prefix(3).map(\.title)
        } else if let top = standardized.universalCharacteristics.first {
            finding = "The strongest standardized pattern is \(top.label): \(top.summary)"
            evidence = top.evidence
        } else {
            finding = "The statistical model has insufficient cross-source evidence for a strong claim."
        }
        return .init(id: "statistical", model: "NEXUS Statistical Pattern Model", role: "frequency + persistence + recency", finding: finding, confidence: max(0.25, life.evidenceQuality), evidence: Array(evidence.prefix(5)))
    }

    private static func semanticOpinion(question: String, corpus: [String]) -> NexusModelOpinion {
        guard !corpus.isEmpty else {
            return .init(id: "semantic", model: "Apple Sentence Embeddings", role: "semantic relevance", finding: "No text corpus was available for semantic comparison.", confidence: 0.1, evidence: [])
        }
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english), let qv = embedding.vector(for: question) else {
            return .init(id: "semantic", model: "Apple Sentence Embeddings", role: "semantic relevance", finding: "The system sentence-embedding model is unavailable for the current language/device.", confidence: 0.15, evidence: [])
        }
        let ranked = corpus.prefix(80).compactMap { text -> (String, Double)? in
            guard let v = embedding.vector(for: String(text.prefix(700))) else { return nil }
            return (text, cosine(qv, v))
        }.sorted { $0.1 > $1.1 }
        let best = ranked.prefix(5)
        let avg = best.isEmpty ? 0 : best.map(\.1).reduce(0,+) / Double(best.count)
        let evidence = best.map { "\(Int(max(0,$0.1)*100))% semantic match: \(String($0.0.prefix(140)))" }
        return .init(id: "semantic", model: "Apple Sentence Embeddings", role: "semantic relevance", finding: best.isEmpty ? "No strong semantic match was found." : "The retrieved evidence is semantically aligned with the question at roughly \(Int(max(0, avg)*100))% average similarity among the strongest local matches.", confidence: min(0.90, max(0.20, avg)), evidence: evidence)
    }

    private static func sentimentOpinion(corpus: [String]) -> NexusModelOpinion {
        let sample = corpus.prefix(60).joined(separator: "\n")
        guard !sample.isEmpty else { return .init(id: "sentiment", model: "Apple Sentiment Model", role: "tone check", finding: "No textual evidence available for tone analysis.", confidence: 0.1, evidence: []) }
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = String(sample.prefix(12_000))
        guard let text = tagger.string, !text.isEmpty,
              let tag = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore).0,
              let value = Double(tag.rawValue) else {
            return .init(id: "sentiment", model: "Apple Sentiment Model", role: "tone check", finding: "The built-in sentiment model returned no reliable score for this mixed corpus.", confidence: 0.20, evidence: [])
        }
        let label = value > 0.20 ? "more positive" : value < -0.20 ? "more negative" : "mostly neutral/mixed"
        return .init(id: "sentiment", model: "Apple Sentiment Model", role: "tone check", finding: "The retrieved text sample is \(label). This is a property of the selected text corpus, not a personality judgment.", confidence: min(0.75, 0.35 + abs(value) * 0.4), evidence: ["Local sentiment score: \(String(format: "%.2f", value))"])
    }

    private static func entityOpinion(corpus: [String]) -> NexusModelOpinion {
        let text = String(corpus.prefix(40).joined(separator: "\n").prefix(10_000))
        guard !text.isEmpty else { return .init(id: "entities", model: "Apple Entity Tagger", role: "people/place/organization extraction", finding: "No text available for local entity extraction.", confidence: 0.1, evidence: []) }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var counts: [String:Int] = [:]
        let range = text.startIndex..<text.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, tokenRange in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                let token = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if token.count > 1 { counts[token, default: 0] += 1 }
            }
            return true
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(8)
        return .init(id: "entities", model: "Apple Entity Tagger", role: "people/place/organization extraction", finding: top.isEmpty ? "No stable named entities were detected in the retrieved sample." : "Recurring named entities in the retrieved evidence include \(top.prefix(5).map(\.key).joined(separator: ", ")).", confidence: min(0.80, 0.28 + Double(top.count)*0.06), evidence: top.map { "\($0.key): \($0.value) local mentions" })
    }

    private static func consensusOpinion(opinions: [NexusModelOpinion], standardized: NexusStandardizationReport) -> NexusModelOpinion {
        let high = opinions.filter { $0.confidence >= 0.50 }
        let breadth = min(1.0, Double(standardized.sourceCount) / 5.0)
        let confidence = min(0.92, 0.30 + Double(high.count) * 0.10 + breadth * 0.22)
        let finding = high.count >= 3 ? "Several independent local engines have enough signal to support synthesis, while provenance and uncertainty remain visible." : "The local engines do not yet have broad enough agreement for a high-confidence synthesis."
        return .init(id: "consensus", model: "NEXUS Cross-source Consensus Model", role: "agreement + evidence quality", finding: finding, confidence: confidence, evidence: ["\(high.count) local engines above 50% confidence", "\(standardized.sourceCount) standardized sources"])
    }

    private static func findDisagreements(_ opinions: [NexusModelOpinion]) -> [String] {
        var out: [String] = []
        let sentiment = opinions.first { $0.id == "sentiment" }
        let semantic = opinions.first { $0.id == "semantic" }
        if let sentiment, sentiment.confidence < 0.35 { out.append("Tone evidence is weak or mixed; do not use it as a strong behavioral conclusion.") }
        if let semantic, semantic.confidence < 0.35 { out.append("The question has weak semantic alignment with retrieved records; the answer should stay general or request more evidence.") }
        let weak = opinions.filter { $0.confidence < 0.25 }.map(\.model)
        if !weak.isEmpty { out.append("Low-signal engines: " + weak.joined(separator: ", ")) }
        return out
    }

    private static func ensembleConfidence(opinions: [NexusModelOpinion], standardized: NexusStandardizationReport) -> Double {
        guard !opinions.isEmpty else { return 0 }
        let avg = opinions.map(\.confidence).reduce(0,+) / Double(opinions.count)
        let breadth = min(1.0, Double(standardized.sourceCount) / 5.0)
        return min(0.95, avg * 0.72 + breadth * 0.28)
    }

    private static func localSynthesis(question: String, base: NexusAnswerPackage, life: NexusLifeAnalysisReport, opinions: [NexusModelOpinion], disagreements: [String]) -> String {
        var parts: [String] = [base.localAnswer]
        if question.lowercased().contains("direction") || question.lowercased().contains("goal") || question.lowercased().contains("life") {
            if let d = life.recommendedDirections.first { parts.append("Recommended direction: \(d.title). \(d.summary)") }
        }
        let confident = opinions.filter { $0.confidence >= 0.50 }.prefix(3)
        if !confident.isEmpty { parts.append("Local-model consensus: " + confident.map { $0.finding }.joined(separator: " ")) }
        if !disagreements.isEmpty { parts.append("Caveat: " + disagreements.joined(separator: " ")) }
        return parts.joined(separator: "\n\n")
    }

    private static func relevantText(records: [KnowledgeRecord], question: String) -> [String] {
        let terms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        let scored = records.prefix(25_000).compactMap { record -> (String, Int)? in
            let body = record.text.isEmpty ? record.title : record.text
            guard !body.isEmpty else { return nil }
            let hay = (record.title + " " + record.text + " " + record.source).lowercased()
            var score = 0
            for term in terms where hay.contains(term) { score += 2 }
            if [.search,.saved,.event,.reminder,.note,.post,.message].contains(record.kind) { score += 1 }
            return score > 0 ? ("\(record.source) • \(record.kind.rawValue): \(String(body.prefix(700)))", score) : nil
        }.sorted { $0.1 > $1.1 }
        if scored.isEmpty {
            return records.prefix(80).compactMap { record in
                let body = record.text.isEmpty ? record.title : record.text
                return body.isEmpty ? nil : "\(record.source): \(String(body.prefix(700)))"
            }
        }
        return scored.prefix(100).map(\.0)
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, aa = 0.0, bb = 0.0
        for i in a.indices { dot += a[i]*b[i]; aa += a[i]*a[i]; bb += b[i]*b[i] }
        guard aa > 0, bb > 0 else { return 0 }
        return dot / (sqrt(aa) * sqrt(bb))
    }
}

extension NexusModel {
    func askV6(_ raw: String) async {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        chatMessages.append(ChatMessage(role: .user, text: question, evidence: []))
        let package = NexusReasoner.package(question: question, records: records, overallSummary: comprehensiveReport.overall, personality: v3Personality)
        let result = await NexusLocalEnsemble.analyze(question: question, records: records, base: package, life: lifeAnalysis, standardized: standardizedReport)
        var evidence = result.evidence
        evidence.insert("Ensemble consensus: \(Int(result.consensus * 100))%", at: 0)
        if !result.disagreements.isEmpty { evidence.append(contentsOf: result.disagreements.map { "Disagreement: \($0)" }) }
        chatMessages.append(ChatMessage(role: .assistant, text: result.answer, evidence: Array(evidence.prefix(16))))
    }
}
