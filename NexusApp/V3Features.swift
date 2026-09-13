import Foundation
import SwiftUI
import UniformTypeIdentifiers
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Intelligence + zero-download fallback

enum NexusIntelligenceEngine {
    static var label: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple Intelligence • on-device"
            default:
                return "NEXUS Local • zero-download fallback"
            }
        }
        #endif
        return "NEXUS Local • zero-download fallback"
    }

    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func respond(question: String, context: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            do {
                let session = LanguageModelSession(instructions: """
                You are NEXUS, a private personal-knowledge analyst running on the user's device.
                Answer only from the supplied NEXUS evidence context. Distinguish observations from inference.
                Never invent facts, diagnoses, protected traits, or certainty that the evidence does not support.
                Prefer useful synthesis, patterns, changes, competing explanations, and concise evidence references.
                If evidence is incomplete, say what additional data would improve confidence.
                """)
                let prompt = """
                USER QUESTION:
                \(question)

                NEXUS EVIDENCE CONTEXT:
                \(String(context.prefix(7_500)))

                Give a direct answer first, then the strongest patterns and caveats when useful.
                """
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}

// MARK: - Data-driven personality

struct NexusTraitEstimate: Identifiable, Hashable {
    let id: String
    let name: String
    let score: Int
    let confidence: Double
    let explanation: String
    let evidence: [String]
}

struct NexusPersonalityReport: Hashable {
    let traits: [NexusTraitEstimate]
    let summary: String
    let coverage: String
    let styleCode: String
    let caveat: String

    static let empty = NexusPersonalityReport(
        traits: [],
        summary: "Import or connect more data to build a behavior-based personality profile.",
        coverage: "No behavioral evidence yet",
        styleCode: "—",
        caveat: "This is a behavioral estimate, not a clinical or psychometric diagnosis."
    )
}

enum DataPersonalityEngine {
    private static let opennessWords = ["learn","research","idea","creative","design","music","piano","art","philosophy","science","math","travel","culture","book","course","why","how","explore","experiment","build","code","programming","ai","history","language"]
    private static let planningWords = ["plan","schedule","deadline","goal","task","todo","remind","calendar","organize","finish","complete","budget","routine","prepare","project","checklist"]
    private static let warmthWords = ["thank","thanks","please","appreciate","sorry","welcome","congrats","congratulations","help","care","love","kind","glad","happy for"]
    private static let emotionWords = ["feel","feeling","worried","worry","stress","stressed","afraid","fear","sad","angry","upset","excited","nervous","overwhelmed","frustrated","emotional"]
    private static let curiosityWords = ["why","how","what","when","where","which","compare","difference","meaning","explain","learn","research"]

    static func analyze(_ records: [KnowledgeRecord]) -> NexusPersonalityReport {
        guard !records.isEmpty else { return .empty }

        let sample = Array(records.prefix(30_000))
        let sources = Set(sample.map(\.source))
        let kinds = Set(sample.map(\.kind))
        var wordCount = 0
        var unique = Set<String>()
        var opennessHits = 0
        var planningHits = 0
        var warmthHits = 0
        var emotionHits = 0
        var curiosityHits = 0
        var questions = 0

        var socialCount = 0
        var structuredCount = 0
        var people = Set<String>()
        var activeHours = Set<Int>()
        let calendar = Calendar.current

        for record in sample {
            if [.message, .comment, .reaction, .follow, .contact].contains(record.kind) { socialCount += 1 }
            if [.event, .reminder, .health, .activity].contains(record.kind) { structuredCount += 1 }
            if [.message, .contact, .comment, .follow].contains(record.kind), !record.title.isEmpty { people.insert(record.title.lowercased()) }
            if let d = record.timestamp { activeHours.insert(calendar.component(.hour, from: d)) }

            let text = (record.title + " " + record.text).lowercased()
            if text.contains("?") { questions += 1 }
            let tokens = text.split { !$0.isLetter && !$0.isNumber }.prefix(120).map(String.init)
            wordCount += tokens.count
            for token in tokens where token.count > 2 {
                if unique.count < 35_000 { unique.insert(token) }
            }
            opennessHits += hitCount(text, words: opennessWords)
            planningHits += hitCount(text, words: planningWords)
            warmthHits += hitCount(text, words: warmthWords)
            emotionHits += hitCount(text, words: emotionWords)
            curiosityHits += hitCount(text, words: curiosityWords)
        }

        let n = max(sample.count, 1)
        let lexicalDiversity = min(1.0, Double(unique.count) / Double(max(wordCount, 1)) * 14)
        let sourceBreadth = min(1.0, Double(sources.count) / 7.0)
        let kindBreadth = min(1.0, Double(kinds.count) / 12.0)
        let textScale = max(Double(wordCount) / 4_000.0, 1.0)

        let openSignal = Double(opennessHits + curiosityHits) / textScale
        let planSignal = Double(planningHits) / textScale + Double(structuredCount) / Double(n) * 45
        let socialSignal = Double(socialCount) / Double(n) * 60 + min(28, Double(people.count) * 0.7)
        let warmthSignal = Double(warmthHits) / textScale
        let emotionSignal = Double(emotionHits) / textScale

        let openness = clamp(48 + Int(min(31, openSignal * 0.8)) + Int(lexicalDiversity * 15) + Int(kindBreadth * 6))
        let conscientiousness = clamp(48 + Int(min(35, planSignal * 0.9)) + Int(sourceBreadth * 5))
        let extraversion = clamp(42 + Int(min(43, socialSignal * 0.65)) + Int(min(6, Double(activeHours.count) / 4.0)))
        let agreeableness = clamp(50 + Int(min(32, warmthSignal * 1.4)))
        let sensitivity = clamp(44 + Int(min(34, emotionSignal * 1.3)) + Int(min(8, Double(questions) / Double(n) * 45)))

        let baseConfidence = min(0.90, 0.28 + sourceBreadth * 0.24 + kindBreadth * 0.18 + min(0.20, Double(sample.count) / 15_000.0))
        let textConfidence = min(0.88, baseConfidence + min(0.12, Double(wordCount) / 80_000.0))

        let traits = [
            NexusTraitEstimate(id: "openness", name: "Openness / curiosity", score: openness, confidence: textConfidence,
                               explanation: "Estimated from topic diversity, curiosity language, learning/creative signals, searches and breadth of interests.",
                               evidence: ["\(opennessHits) exploration/creative signals", "\(curiosityHits) curiosity signals", "\(unique.count) distinct sampled terms", "\(kinds.count) activity types"]),
            NexusTraitEstimate(id: "conscientiousness", name: "Conscientiousness / structure", score: conscientiousness, confidence: baseConfidence,
                               explanation: "Estimated from planning language, reminders, events, routines, goals and structured activity evidence.",
                               evidence: ["\(planningHits) planning/goal signals", "\(structuredCount) structured records", "\(sources.count) contributing sources"]),
            NexusTraitEstimate(id: "extraversion", name: "Social orientation", score: extraversion, confidence: min(0.82, baseConfidence),
                               explanation: "Estimated from social activity breadth and recurring interaction evidence. This does not equate online volume with real-world sociability.",
                               evidence: ["\(socialCount) social records", "\(people.count) recurring social labels", "\(activeHours.count) active-hour buckets"]),
            NexusTraitEstimate(id: "agreeableness", name: "Cooperative / warm expression", score: agreeableness, confidence: min(0.72, textConfidence),
                               explanation: "Estimated cautiously from supportive, appreciative and cooperative language across available text.",
                               evidence: ["\(warmthHits) warmth/cooperation language signals", "Text evidence from \(sources.count) sources"]),
            NexusTraitEstimate(id: "sensitivity", name: "Emotional sensitivity / reactivity", score: sensitivity, confidence: min(0.68, textConfidence),
                               explanation: "Estimated cautiously from explicit emotional-expression language. It is not a mental-health assessment.",
                               evidence: ["\(emotionHits) emotional-expression signals", "\(questions) captured records containing questions"])
        ]

        let strongest = traits.sorted { $0.score > $1.score }.prefix(2).map(\.name)
        let summary = "Across the current vault, the strongest behavior-based personality signals are \(naturalJoin(strongest)). Scores are weighted by evidence breadth rather than by your self-description."
        let styleCode = mbtiLike(openness: openness, conscientiousness: conscientiousness, extraversion: extraversion, agreeableness: agreeableness)
        let coverage = "\(sample.count) records • \(sources.count) sources • \(kinds.count) activity types • \(wordCount) sampled words"
        return NexusPersonalityReport(traits: traits, summary: summary, coverage: coverage, styleCode: styleCode,
                                      caveat: "Behavioral estimates can reflect what was exported or connected. The MBTI-style code is exploratory, derived from broad trait signals, and is not a validated MBTI test.")
    }

    private static func hitCount(_ text: String, words: [String]) -> Int {
        words.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
    }

    private static func clamp(_ value: Int) -> Int { min(95, max(5, value)) }

    private static func mbtiLike(openness: Int, conscientiousness: Int, extraversion: Int, agreeableness: Int) -> String {
        let ie = extraversion >= 58 ? "E" : "I"
        let ns = openness >= 60 ? "N" : "S"
        let tf = agreeableness >= 62 ? "F" : "T"
        let jp = conscientiousness >= 58 ? "J" : "P"
        return ie + ns + tf + jp
    }

    private static func naturalJoin(_ values: [String]) -> String {
        guard let last = values.last else { return "" }
        if values.count == 1 { return last }
        return values.dropLast().joined(separator: ", ") + " and " + last
    }
}

// MARK: - Discovery engine

struct NexusDiscovery: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let explanation: String
    let evidence: [String]
    let symbol: String
}

enum NexusDiscoveryEngine {
    static func discoveries(_ records: [KnowledgeRecord]) -> [NexusDiscovery] {
        guard !records.isEmpty else { return [] }
        let sample = Array(records.prefix(30_000))
        let sources = Dictionary(grouping: sample, by: \.source).mapValues(\.count)
        let terms = crossSourceTerms(sample)
        let dated = sample.compactMap { $0.timestamp == nil ? nil : $0 }
        let social = sample.filter { [.message,.comment,.reaction,.follow,.contact].contains($0.kind) }
        let questions = sample.filter { $0.kind == .search || $0.text.contains("?") }
        var out: [NexusDiscovery] = []

        if let bridge = terms.first(where: { $0.sources >= 2 }) {
            out.append(.init(id: "bridge", title: "Cross-source bridge", value: bridge.term,
                             explanation: "This theme appears independently across multiple data sources, making it stronger than a single-app signal.",
                             evidence: ["\(bridge.count) mentions", "\(bridge.sources) independent sources"], symbol: "point.3.connected.trianglepath.dotted"))
        }

        out.append(.init(id: "coverage", title: "Knowledge coverage", value: "\(sources.count) sources",
                         explanation: "NEXUS becomes more reliable when unrelated sources converge on the same pattern.",
                         evidence: sources.sorted { $0.value > $1.value }.prefix(7).map { "\($0.key): \($0.value) records" }, symbol: "square.stack.3d.up.fill"))

        if !social.isEmpty {
            let people = Dictionary(grouping: social.filter { !$0.title.isEmpty }, by: { $0.title }).mapValues(\.count).sorted { $0.value > $1.value }
            out.append(.init(id: "social", title: "Social constellation", value: "\(Set(social.map(\.title)).filter { !$0.isEmpty }.count) labels",
                             explanation: "A view of recurring people/contact labels and interaction density; frequency is not the same as closeness.",
                             evidence: people.prefix(6).map { "\($0.key): \($0.value) signals" }, symbol: "person.3.fill"))
        }

        if !questions.isEmpty {
            out.append(.init(id: "curiosity", title: "Curiosity signature", value: "\(questions.count) question/search signals",
                             explanation: "Questions and searches reveal what repeatedly pulls your attention toward explanation, comparison and discovery.",
                             evidence: questions.prefix(6).map { String(($0.text.isEmpty ? $0.title : $0.text).prefix(120)) }, symbol: "questionmark.bubble.fill"))
        }

        let change = changeSignal(dated)
        if let change {
            out.append(change)
        }

        let years = Set(dated.compactMap { $0.timestamp.map { Calendar.current.component(.year, from: $0) } })
        if years.count > 1 {
            out.append(.init(id: "eras", title: "Life-era depth", value: "\(years.count) years",
                             explanation: "Your dated evidence spans enough time to compare persistent interests against temporary phases.",
                             evidence: years.sorted().map(String.init), symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90"))
        }

        return out
    }

    private struct TermSignal { let term: String; let count: Int; let sources: Int }

    private static func crossSourceTerms(_ records: [KnowledgeRecord]) -> [TermSignal] {
        let stop: Set<String> = ["this","that","with","from","have","your","you","the","and","for","was","are","but","not","http","https","www","com","message","instagram","facebook","messenger","photo","video"]
        var total: [String:Int] = [:]
        var sourceSets: [String:Set<String>] = [:]
        for record in records {
            let text = (record.title + " " + record.text).lowercased()
            let words = Set(text.split { !$0.isLetter && !$0.isNumber }.prefix(100).map(String.init).filter { $0.count >= 4 && !stop.contains($0) })
            for word in words {
                total[word, default: 0] += 1
                sourceSets[word, default: []].insert(record.source)
            }
        }
        return total.map { TermSignal(term: $0.key, count: $0.value, sources: sourceSets[$0.key]?.count ?? 0) }
            .filter { $0.count >= 3 }
            .sorted { a, b in a.sources == b.sources ? a.count > b.count : a.sources > b.sources }
    }

    private static func changeSignal(_ dated: [KnowledgeRecord]) -> NexusDiscovery? {
        guard let newest = dated.compactMap(\.timestamp).max(), dated.count >= 40 else { return nil }
        let recentStart = Calendar.current.date(byAdding: .day, value: -90, to: newest) ?? newest
        let previousStart = Calendar.current.date(byAdding: .day, value: -180, to: newest) ?? newest
        let recent = dated.filter { ($0.timestamp ?? .distantPast) >= recentStart }
        let previous = dated.filter { let d = $0.timestamp ?? .distantPast; return d >= previousStart && d < recentStart }
        guard recent.count >= 10, previous.count >= 10 else { return nil }
        let recentTerms = crossSourceTerms(recent)
        let previousTerms = Dictionary(uniqueKeysWithValues: crossSourceTerms(previous).map { ($0.term, $0.count) })
        let rising = recentTerms.map { ($0.term, $0.count - (previousTerms[$0.term] ?? 0)) }.filter { $0.1 > 1 }.sorted { $0.1 > $1.1 }
        guard !rising.isEmpty else { return nil }
        return .init(id: "change", title: "Recent momentum", value: rising[0].0,
                     explanation: "These themes increased in the latest 90-day evidence window compared with the preceding 90 days.",
                     evidence: rising.prefix(6).map { "\($0.0): +\($0.1) signals" }, symbol: "chart.line.uptrend.xyaxis")
    }
}

// MARK: - Import staging

struct NexusImportResult {
    let records: [KnowledgeRecord]
    let stagedFiles: Int
    let errors: [String]
}

enum NexusImportCoordinator {
    static func importURLs(_ urls: [URL], target: String) async -> NexusImportResult {
        await withTaskGroup(of: ([KnowledgeRecord], String?).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let staged = try stage(url)
                        defer { try? FileManager.default.removeItem(at: staged) }
                        let parsed = try MetaArchiveImporter().importURL(staged)
                        return (relabel(parsed, target: target), nil)
                    } catch {
                        return ([], "\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
            var records: [KnowledgeRecord] = []
            var errors: [String] = []
            var stagedCount = 0
            for await result in group {
                if !result.0.isEmpty { stagedCount += 1; records.append(contentsOf: result.0) }
                if let error = result.1 { errors.append(error) }
            }
            let deduped = Array(Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }).values)
            return NexusImportResult(records: deduped, stagedFiles: stagedCount, errors: errors)
        }
    }

    private static func stage(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NEXUS-Staged", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        let ext = url.pathExtension
        let name = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let destination = root.appendingPathComponent(name, isDirectory: isDir.boolValue)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { source in
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: source, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard fm.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return destination
    }

    private static func relabel(_ records: [KnowledgeRecord], target: String) -> [KnowledgeRecord] {
        let lower = target.lowercased()
        let forced: String? = lower.contains("instagram") ? "Instagram" : (lower.contains("facebook") || lower.contains("messenger")) ? "Meta" : nil
        guard let forced else { return records }
        return records.map { record in
            let source: String
            if forced == "Meta" && record.kind == .message { source = "Messenger" }
            else if record.source == "Imported Files" || record.source == "Meta Archive" { source = forced }
            else { source = record.source }
            return KnowledgeRecord(id: record.id, source: source, kind: record.kind, timestamp: record.timestamp, title: record.title, text: record.text, metadata: record.metadata)
        }
    }
}

// MARK: - Chat retrieval and model extension

struct NexusAnswerPackage {
    let localAnswer: String
    let evidence: [String]
    let context: String
}

enum NexusReasoner {
    static func package(question: String, records: [KnowledgeRecord], overallSummary: String, personality: NexusPersonalityReport) -> NexusAnswerPackage {
        guard !records.isEmpty else {
            return .init(localAnswer: "I need evidence first. Import an Instagram/Messenger archive or connect on-device sources, then ask again.", evidence: [], context: "No imported evidence.")
        }
        let queryTerms = Set(question.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        let scored = records.prefix(30_000).compactMap { record -> (KnowledgeRecord, Int)? in
            let hay = (record.title + " " + record.text + " " + record.source + " " + record.kind.rawValue).lowercased()
            var score = 0
            for term in queryTerms where hay.contains(term) { score += 3 }
            if question.lowercased().contains("interest") && [.search,.saved,.post,.media,.message].contains(record.kind) { score += 1 }
            if question.lowercased().contains("people") || question.lowercased().contains("relationship") {
                if [.message,.contact,.comment,.follow,.reaction].contains(record.kind) { score += 2 }
            }
            if question.lowercased().contains("personality") { score += record.text.isEmpty ? 0 : 1 }
            return score > 0 ? (record, score) : nil
        }.sorted { $0.1 > $1.1 }.prefix(14).map(\.0)

        let fallback = localAnswer(question: question, records: records, overallSummary: overallSummary, personality: personality, relevant: scored)
        let evidence = scored.prefix(8).map { record in
            let snippet = String((record.text.isEmpty ? record.title : record.text).prefix(150))
            return "\(record.source) • \(record.kind.rawValue): \(snippet)"
        }
        let personalityContext = personality.traits.map { "\($0.name)=\($0.score)/100 confidence \(Int($0.confidence * 100))%" }.joined(separator: "; ")
        let recordContext = scored.prefix(12).enumerated().map { i, r in
            "[\(i + 1)] source=\(r.source), type=\(r.kind.rawValue), date=\(r.timestamp?.formatted(date: .numeric, time: .omitted) ?? "unknown"), title=\(r.title), text=\(String(r.text.prefix(350)))"
        }.joined(separator: "\n")
        let context = """
        Overall deterministic summary: \(overallSummary)
        Data-driven personality: \(personalityContext)
        Coverage: \(personality.coverage)
        Retrieved evidence:
        \(recordContext)
        """
        return .init(localAnswer: fallback, evidence: evidence, context: context)
    }

    private static func localAnswer(question: String, records: [KnowledgeRecord], overallSummary: String, personality: NexusPersonalityReport, relevant: [KnowledgeRecord]) -> String {
        let q = question.lowercased()
        if q.contains("personality") || q.contains("trait") || q.contains("mbti") {
            let traits = personality.traits.sorted { $0.score > $1.score }.map { "\($0.name) \($0.score)/100" }.joined(separator: ", ")
            return "Based on the current overall data, the personality model estimates: \(traits). The strongest signals are evidence-weighted and remain separate from self-report. Current exploratory style code: \(personality.styleCode)."
        }
        if q.contains("overall") || q.contains("analyze me") || q.contains("who am i") { return overallSummary + " " + personality.summary }
        if q.contains("interest") || q.contains("topic") {
            let discoveries = NexusDiscoveryEngine.discoveries(records)
            if let bridge = discoveries.first(where: { $0.id == "bridge" }) { return "A strong recurring cross-source theme is \(bridge.value). " + bridge.explanation }
        }
        if q.contains("change") || q.contains("recent") || q.contains("evol") {
            if let change = NexusDiscoveryEngine.discoveries(records).first(where: { $0.id == "change" }) { return "Your clearest recent momentum signal is \(change.value). " + change.explanation + " " + change.evidence.joined(separator: "; ") }
        }
        if !relevant.isEmpty {
            return "I found \(relevant.count) highly relevant records across \(Set(relevant.map(\.source)).count) sources. The strongest evidence is shown below; on Apple-Intelligence-capable devices I also synthesize these records with the built-in on-device model."
        }
        return overallSummary
    }
}

extension NexusModel {
    var v3Personality: NexusPersonalityReport { DataPersonalityEngine.analyze(records) }
    var v3Discoveries: [NexusDiscovery] { NexusDiscoveryEngine.discoveries(records) }
    var v3AIStatus: String { NexusIntelligenceEngine.label }

    func askV3(_ raw: String) async {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        chatMessages.append(ChatMessage(role: .user, text: question, evidence: []))
        let package = NexusReasoner.package(question: question, records: records, overallSummary: overallSummary, personality: v3Personality)
        let generated = await NexusIntelligenceEngine.respond(question: question, context: package.context)
        let answer = generated?.isEmpty == false ? generated! : package.localAnswer
        chatMessages.append(ChatMessage(role: .assistant, text: answer, evidence: package.evidence))
    }
}
