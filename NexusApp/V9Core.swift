import Foundation
import SwiftUI
import NaturalLanguage
import CryptoKit
import LocalAuthentication
import Security
import CoreSpotlight
import UniformTypeIdentifiers

struct NexusV9Citation: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case record, file, pdfPage, csvRow, imageOCR, web, insight, code }
    let id: UUID
    let kind: Kind
    let sourceID: String
    let sourceName: String
    let location: String
    let excerpt: String
    let filePath: String?
    let createdAt: Date

    init(kind: Kind, sourceID: String, sourceName: String, location: String = "", excerpt: String, filePath: String? = nil) {
        self.id = UUID(); self.kind = kind; self.sourceID = sourceID; self.sourceName = sourceName
        self.location = location; self.excerpt = excerpt; self.filePath = filePath; self.createdAt = Date()
    }
}

struct NexusV9Chunk: Identifiable, Codable, Hashable {
    let id: String
    let sourceID: String
    let sourceName: String
    let title: String
    let text: String
    let timestamp: Date?
    let kind: NexusV9Citation.Kind
    let location: String
    let filePath: String?
    let vector: [Double]
    var fingerprint: String { "\(sourceID)|\(location)|\(text.count)" }
}

struct NexusV9SearchHit: Identifiable, Hashable {
    let id = UUID()
    let chunk: NexusV9Chunk
    let score: Double
    let lexical: Double
    let semantic: Double
    let learnedBoost: Double
}

enum NexusV9PerformanceMode: String, CaseIterable, Identifiable, Codable {
    case battery = "Battery Saver"
    case balanced = "Balanced"
    case maximum = "Maximum"
    var id: String { rawValue }
    var retrievalLimit: Int { self == .battery ? 6 : (self == .balanced ? 10 : 16) }
    var autoVision: Bool { self != .battery }
    var maxContextCharacters: Int { self == .battery ? 7_000 : (self == .balanced ? 13_000 : 22_000) }
}

struct NexusV9Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var isPrivate: Bool
    var fileIDs: Set<UUID>
    var tags: [String]
    var createdAt: Date
}

struct NexusV9StoredMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: String
    let text: String
    let attachmentIDs: [UUID]
    let createdAt: Date
}

struct NexusV9ConversationBranch: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var workspaceID: UUID?
    var parentID: UUID?
    var messages: [NexusV9StoredMessage]
    var createdAt: Date
}

struct NexusV9Entity: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable { case person, place, project, organization, topic, product, event, file, other }
    let id: UUID
    var canonicalName: String
    var aliases: Set<String>
    var kind: Kind
    var sourceIDs: Set<String>
    var strength: Double
}

struct NexusV9Insight: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var summary: String
    var evidence: [NexusV9Citation]
    var confidence: Double
    var firstSeen: Date
    var lastUpdated: Date
    var dismissed: Bool
}

struct NexusV9ContextItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case file, record, insight, text }
    let id: UUID
    let kind: Kind
    let referenceID: String
    let label: String
    let preview: String
}

struct NexusV9AutomationRule: Identifiable, Codable, Hashable {
    enum Trigger: String, Codable, CaseIterable { case fileImport, appOpen, manual, watchFolder }
    enum Action: String, Codable, CaseIterable { case index, extractDates, updateInsights, buildDashboard, summarize, tagFinance, tagTravel }
    let id: UUID
    var name: String
    var trigger: Trigger
    var contains: String
    var actions: [Action]
    var enabled: Bool
    var lastRun: Date?
}

struct NexusV9MiniApp: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable { case tracker, calculator, timeline, quiz, dashboard, comparison }
    let id: UUID
    var title: String
    var kind: Kind
    var sourceQuery: String
    var createdAt: Date
}

struct NexusV9DiagnosticSnapshot: Codable, Hashable {
    var lastQueryMilliseconds: Double = 0
    var lastRetrievalCount: Int = 0
    var lastContextCharacters: Int = 0
    var cacheHits: Int = 0
    var cacheMisses: Int = 0
    var indexedChunks: Int = 0
    var lastRoute: String = "Ready"
    var lastVisionUsed: Bool = false
}

struct NexusV9CachedAnswer: Codable, Hashable {
    let question: String
    let vector: [Double]
    let answer: String
    let evidence: [String]
    let createdAt: Date
}

@MainActor
final class NexusV9IntelligenceStore: ObservableObject {
    static let shared = NexusV9IntelligenceStore()

    @Published private(set) var chunks: [NexusV9Chunk] = []
    @Published var workspaces: [NexusV9Workspace] = []
    @Published var activeWorkspaceID: UUID?
    @Published var branches: [NexusV9ConversationBranch] = []
    @Published var entities: [NexusV9Entity] = []
    @Published var insights: [NexusV9Insight] = []
    @Published var contextTray: [NexusV9ContextItem] = []
    @Published var automations: [NexusV9AutomationRule] = []
    @Published var miniApps: [NexusV9MiniApp] = []
    @Published var ontology: [String:String] = [:]
    @Published var performanceMode: NexusV9PerformanceMode = .balanced
    @Published var diagnostics = NexusV9DiagnosticSnapshot()
    @Published var status = "V9 intelligence ready"
    @Published var indexProgress: Double = 0
    @Published var privateMode = false
    @Published var vaultLocked = false

    private var feedback: [String:Int] = [:]
    private var semanticCache: [NexusV9CachedAnswer] = []
    private let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
    private let saveURL: URL
    private let indexURL: URL

    private struct PersistedState: Codable {
        var workspaces: [NexusV9Workspace]
        var activeWorkspaceID: UUID?
        var branches: [NexusV9ConversationBranch]
        var entities: [NexusV9Entity]
        var insights: [NexusV9Insight]
        var contextTray: [NexusV9ContextItem]
        var automations: [NexusV9AutomationRule]
        var miniApps: [NexusV9MiniApp]
        var ontology: [String:String]
        var performanceMode: NexusV9PerformanceMode
        var feedback: [String:Int]
        var semanticCache: [NexusV9CachedAnswer]
    }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        saveURL = base.appendingPathComponent("nexus-v9-state.json")
        indexURL = base.appendingPathComponent("nexus-v9-index.json")
        load()
        if workspaces.isEmpty {
            workspaces = [
                NexusV9Workspace(id: UUID(), name: "Personal", symbol: "person.crop.circle", isPrivate: false, fileIDs: [], tags: ["global"], createdAt: Date()),
                NexusV9Workspace(id: UUID(), name: "Work", symbol: "briefcase.fill", isPrivate: false, fileIDs: [], tags: ["work"], createdAt: Date())
            ]
            activeWorkspaceID = workspaces.first?.id
            seedAutomations()
            persist()
        }
    }

    func createWorkspace(name: String, symbol: String = "square.grid.2x2", privateSession: Bool = false) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let item = NexusV9Workspace(id: UUID(), name: clean, symbol: symbol, isPrivate: privateSession, fileIDs: [], tags: [], createdAt: Date())
        workspaces.append(item); activeWorkspaceID = item.id; persist()
    }

    func branchCurrentConversation(_ messages: [ChatMessage], name: String = "Branch") {
        let stored = messages.suffix(30).map { NexusV9StoredMessage(id: UUID(), role: $0.role.rawValue, text: $0.text, attachmentIDs: [], createdAt: $0.timestamp) }
        branches.insert(NexusV9ConversationBranch(id: UUID(), name: name, workspaceID: activeWorkspaceID, parentID: nil, messages: stored, createdAt: Date()), at: 0)
        persist()
    }

    func addToTray(kind: NexusV9ContextItem.Kind, referenceID: String, label: String, preview: String) {
        if contextTray.contains(where: { $0.referenceID == referenceID && $0.kind == kind }) { return }
        contextTray.append(NexusV9ContextItem(id: UUID(), kind: kind, referenceID: referenceID, label: label, preview: String(preview.prefix(600))))
        if contextTray.count > 40 { contextTray.removeFirst(contextTray.count - 40) }
        persist()
    }

    func clearTray() { contextTray.removeAll(); persist() }

    func vector(for text: String) -> [Double] {
        let clean = String(text.prefix(4_000))
        if let v = sentenceEmbedding?.vector(for: clean), !v.isEmpty { return normalized(v) }
        var result = Array(repeating: 0.0, count: 96)
        for token in tokens(clean) {
            var hash: UInt64 = 1469598103934665603
            for byte in token.utf8 { hash ^= UInt64(byte); hash &*= 1099511628211 }
            let index = Int(hash % UInt64(result.count))
            result[index] += 1.0
        }
        return normalized(result)
    }

    func index(records: [KnowledgeRecord], files: [NexusV8FileItem], force: Bool = false) async {
        status = "Indexing memory, files and evidence…"
        indexProgress = 0.02
        let existing = force ? Set<String>() : Set(chunks.map(\.id))
        var incoming: [NexusV9Chunk] = force ? [] : chunks
        let recordLimit = 5_000
        let recent = records.prefix(recordLimit)
        let total = max(1, recent.count + files.count)
        var completed = 0

        for record in recent {
            let id = "record:\(record.id)"
            if !existing.contains(id) {
                let body = [record.title, record.text, record.metadata.values.joined(separator: " ")].joined(separator: "\n")
                incoming.append(NexusV9Chunk(id: id, sourceID: record.id, sourceName: record.source, title: record.title, text: String(body.prefix(2_500)), timestamp: record.timestamp, kind: .record, location: record.kind.rawValue, filePath: nil, vector: vector(for: body)))
            }
            completed += 1
            if completed % 120 == 0 { indexProgress = Double(completed) / Double(total); await Task.yield() }
        }

        for file in files {
            let baseID = "file:\(file.id.uuidString)"
            if !existing.contains(baseID) {
                let preview: String
                if file.ext == "pdf" { preview = (try? NexusV8FileSupport.pdfText(file.url, maxPages: 8, maxCharacters: 12_000)) ?? NexusV8FileSupport.metadata(file) }
                else if NexusV8FileSupport.textExtensions.contains(file.ext) { preview = (try? NexusV8FileSupport.readableText(file.url, maxBytes: 500_000, maxCharacters: 12_000)) ?? NexusV8FileSupport.metadata(file) }
                else { preview = NexusV8FileSupport.metadata(file) }
                incoming.append(NexusV9Chunk(id: baseID, sourceID: file.id.uuidString, sourceName: file.name, title: file.name, text: preview, timestamp: file.importedAt, kind: .file, location: file.kindLabel, filePath: file.path, vector: vector(for: preview)))
            }
            completed += 1
            indexProgress = min(0.98, Double(completed) / Double(total))
        }

        let unique = Dictionary(grouping: incoming, by: \.id).compactMap { $0.value.last }
        chunks = Array(unique.prefix(7_500))
        diagnostics.indexedChunks = chunks.count
        deriveEntities()
        deriveInsights()
        persistIndex()
        persist()
        indexProgress = 1
        status = "Indexed \(chunks.count) searchable evidence chunks"
        await indexSpotlight(files: files)
    }

    func search(_ query: String, limit: Int? = nil) -> [NexusV9SearchHit] {
        let started = CFAbsoluteTimeGetCurrent()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let qTokens = Set(tokens(q))
        let qVector = vector(for: q)
        let now = Date()
        var hits: [NexusV9SearchHit] = []
        hits.reserveCapacity(min(chunks.count, 3_000))
        for chunk in chunks {
            let chunkTokens = Set(tokens(chunk.title + " " + chunk.text))
            let intersect = qTokens.intersection(chunkTokens).count
            let lexical = qTokens.isEmpty ? 0 : Double(intersect) / Double(qTokens.count)
            let semantic = max(0, cosine(qVector, chunk.vector))
            let learned = min(0.15, Double(feedback[chunk.id, default: 0]) * 0.025)
            let recency: Double
            if let t = chunk.timestamp {
                let days = max(0, now.timeIntervalSince(t) / 86_400)
                recency = 0.06 * exp(-days / 240.0)
            } else { recency = 0 }
            let score = lexical * 0.50 + semantic * 0.39 + learned + recency
            if score > 0.08 { hits.append(NexusV9SearchHit(chunk: chunk, score: score, lexical: lexical, semantic: semantic, learnedBoost: learned)) }
        }
        hits.sort { $0.score > $1.score }
        let count = limit ?? performanceMode.retrievalLimit
        let result = Array(hits.prefix(count))
        diagnostics.lastQueryMilliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1000
        diagnostics.lastRetrievalCount = result.count
        diagnostics.lastContextCharacters = result.reduce(0) { $0 + $1.chunk.text.count }
        return result
    }

    func evidenceContext(for query: String) -> (String, [NexusV9Citation]) {
        let hits = search(query)
        var context = ""
        var citations: [NexusV9Citation] = []
        for hit in hits {
            let excerpt = String(hit.chunk.text.prefix(1_400))
            let block = "[\(hit.chunk.sourceName) • \(hit.chunk.location)]\n\(excerpt)\n\n"
            if context.count + block.count > performanceMode.maxContextCharacters { break }
            context += block
            citations.append(NexusV9Citation(kind: hit.chunk.kind, sourceID: hit.chunk.sourceID, sourceName: hit.chunk.sourceName, location: hit.chunk.location, excerpt: String(excerpt.prefix(500)), filePath: hit.chunk.filePath))
        }
        return (context, citations)
    }

    func markUseful(_ chunkID: String) {
        feedback[chunkID, default: 0] += 1
        persist()
    }

    func cachedAnswer(similarTo question: String) -> NexusV9CachedAnswer? {
        let v = vector(for: question)
        let best = semanticCache.map { ($0, cosine(v, $0.vector)) }.max { $0.1 < $1.1 }
        guard let best, best.1 >= 0.965, Date().timeIntervalSince(best.0.createdAt) < 86_400 else {
            diagnostics.cacheMisses += 1; return nil
        }
        diagnostics.cacheHits += 1
        return best.0
    }

    func cache(question: String, answer: String, evidence: [String]) {
        semanticCache.removeAll { cosine(vector(for: question), $0.vector) > 0.98 }
        semanticCache.append(NexusV9CachedAnswer(question: question, vector: vector(for: question), answer: answer, evidence: evidence, createdAt: Date()))
        if semanticCache.count > 40 { semanticCache.removeFirst(semanticCache.count - 40) }
        persist()
    }

    func addInsight(title: String, summary: String, evidence: [NexusV9Citation], confidence: Double) {
        let key = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = insights.firstIndex(where: { $0.title.lowercased() == key }) {
            insights[index].summary = summary
            insights[index].evidence = Array((insights[index].evidence + evidence).uniqued(by: { "\($0.sourceID)|\($0.location)" }).prefix(12))
            insights[index].confidence = max(insights[index].confidence, confidence)
            insights[index].lastUpdated = Date()
        } else {
            insights.insert(NexusV9Insight(id: UUID(), title: title, summary: summary, evidence: evidence, confidence: min(1, max(0, confidence)), firstSeen: Date(), lastUpdated: Date(), dismissed: false), at: 0)
        }
        persist()
    }

    func mergeEntities(_ ids: Set<UUID>, canonicalName: String) {
        let matches = entities.filter { ids.contains($0.id) }
        guard !matches.isEmpty else { return }
        let aliases = matches.reduce(into: Set<String>()) { result, item in result.formUnion(item.aliases); result.insert(item.canonicalName) }
        let sources = matches.reduce(into: Set<String>()) { $0.formUnion($1.sourceIDs) }
        let merged = NexusV9Entity(id: UUID(), canonicalName: canonicalName, aliases: aliases, kind: matches.first?.kind ?? .other, sourceIDs: sources, strength: matches.map(\.strength).max() ?? 0)
        entities.removeAll { ids.contains($0.id) }; entities.append(merged); persist()
    }

    func teach(alias: String, means canonical: String) {
        ontology[alias.lowercased()] = canonical
        persist()
    }

    func forgetSource(_ sourceID: String) {
        chunks.removeAll { $0.sourceID == sourceID || $0.sourceName == sourceID }
        entities = entities.compactMap { entity in
            var e = entity; e.sourceIDs.remove(sourceID); return e.sourceIDs.isEmpty ? nil : e
        }
        insights = insights.filter { !$0.evidence.contains(where: { $0.sourceID == sourceID || $0.sourceName == sourceID }) }
        persistIndex(); persist()
    }

    func runAutomations(for trigger: NexusV9AutomationRule.Trigger, importedNames: [String] = []) {
        let haystack = importedNames.joined(separator: " ").lowercased()
        for index in automations.indices where automations[index].enabled && automations[index].trigger == trigger {
            let needle = automations[index].contains.lowercased()
            guard needle.isEmpty || haystack.contains(needle) else { continue }
            automations[index].lastRun = Date()
        }
        persist()
    }

    func createMiniApp(from prompt: String) {
        let p = prompt.lowercased()
        let kind: NexusV9MiniApp.Kind = p.contains("quiz") ? .quiz : p.contains("calculator") ? .calculator : p.contains("timeline") ? .timeline : p.contains("compare") ? .comparison : p.contains("track") ? .tracker : .dashboard
        miniApps.insert(NexusV9MiniApp(id: UUID(), title: prompt.isEmpty ? "Generated Dashboard" : String(prompt.prefix(52)), kind: kind, sourceQuery: prompt, createdAt: Date()), at: 0)
        persist()
    }

    func warmBestLocalModel() async {
        guard NexusPortableModelStore.shared.activeModelID.isEmpty, performanceMode != .battery else { return }
        let store = NexusPortableModelStore.shared
        let downloaded = store.models.filter { store.isDownloaded($0) }.sorted { $0.estimatedBytes < $1.estimatedBytes }
        if let candidate = downloaded.first { status = "Warming \(candidate.name)…"; await store.load(candidate); status = "Warm model ready" }
    }

    func routeLabel(question: String, attachments: [NexusV8FileItem]) -> String {
        let q = question.lowercased()
        let visual = attachments.contains { NexusV8FileSupport.imageExtensions.contains($0.ext) } || q.contains("image") || q.contains("visual") || q.contains("chart")
        let deep = q.contains("deep") || q.contains("comprehensive") || q.contains("cross-check") || attachments.count >= 4
        let route = visual ? "Vision + language" : deep ? "Deep evidence synthesis" : "Fast retrieval + resident model"
        diagnostics.lastRoute = route; diagnostics.lastVisionUsed = visual
        return route
    }

    func contextBudgetSummary(for query: String) -> String {
        let hits = search(query)
        let chars = hits.reduce(0) { $0 + $1.chunk.text.count }
        return "\(hits.count) retrieved evidence chunks • ~\(chars) characters • \(performanceMode.rawValue) • route: \(diagnostics.lastRoute)"
    }

    func authenticateVault() async -> Bool {
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { vaultLocked = false; return true }
        do { let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock the private NEXUS vault"); vaultLocked = !ok; return ok }
        catch { vaultLocked = true; return false }
    }

    func encrypt(_ data: Data) throws -> Data {
        let key = try vaultKey(); let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw NSError(domain: "NEXUS.V9", code: 9) }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        let key = try vaultKey(); let box = try AES.GCM.SealedBox(combined: data); return try AES.GCM.open(box, using: key)
    }

    private func vaultKey() throws -> SymmetricKey {
        let service = "com.rey.nexus.vaultkey"; let account = "primary"
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:account, kSecReturnData as String:true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data { return SymmetricKey(data: data) }
        let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let add: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:account, kSecValueData as String:data, kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw NSError(domain: "NEXUS.V9", code: 10) }
        return SymmetricKey(data: data)
    }

    private func deriveEntities() {
        var counts: [String:(Int,Set<String>)] = [:]
        for chunk in chunks.prefix(4_000) {
            let words = tokens(chunk.title + " " + chunk.text).filter { $0.count >= 4 }
            for word in words.prefix(120) {
                var pair = counts[word, default: (0, [])]; pair.0 += 1; pair.1.insert(chunk.sourceID); counts[word] = pair
            }
        }
        let top = counts.sorted { $0.value.0 > $1.value.0 }.prefix(120)
        entities = top.map { name, value in
            let canonical = ontology[name] ?? name.replacingOccurrences(of: "_", with: " ").capitalized
            return NexusV9Entity(id: UUID(), canonicalName: canonical, aliases: [name], kind: .topic, sourceIDs: value.1, strength: min(1, Double(value.0) / 40.0))
        }
    }

    private func deriveInsights() {
        guard !chunks.isEmpty else { return }
        let sources = Set(chunks.map(\.sourceName))
        let topEntities = entities.sorted { $0.strength > $1.strength }.prefix(5)
        if !topEntities.isEmpty {
            let names = topEntities.map(\.canonicalName).joined(separator: ", ")
            let cites = chunks.prefix(4).map { NexusV9Citation(kind: $0.kind, sourceID: $0.sourceID, sourceName: $0.sourceName, location: $0.location, excerpt: String($0.text.prefix(300)), filePath: $0.filePath) }
            addInsight(title: "Strong recurring signals", summary: "Across \(sources.count) indexed sources, the strongest recurring signals currently include \(names).", evidence: cites, confidence: min(0.94, 0.45 + Double(sources.count) * 0.06))
        }
    }

    private func indexSpotlight(files: [NexusV8FileItem]) async {
        let items = files.prefix(300).map { file -> CSSearchableItem in
            let attr = CSSearchableItemAttributeSet(contentType: .data)
            attr.title = file.name; attr.contentDescription = NexusV8FileSupport.metadata(file)
            return CSSearchableItem(uniqueIdentifier: "nexus-file-\(file.id.uuidString)", domainIdentifier: "com.rey.nexus.files", attributeSet: attr)
        }
        do { try await CSSearchableIndex.default().indexSearchableItems(Array(items)) } catch { }
    }

    private func seedAutomations() {
        automations = [
            NexusV9AutomationRule(id: UUID(), name: "Index every import", trigger: .fileImport, contains: "", actions: [.index, .updateInsights], enabled: true, lastRun: nil),
            NexusV9AutomationRule(id: UUID(), name: "Finance CSV intelligence", trigger: .fileImport, contains: "csv", actions: [.tagFinance, .buildDashboard], enabled: true, lastRun: nil),
            NexusV9AutomationRule(id: UUID(), name: "Travel document dates", trigger: .fileImport, contains: "travel", actions: [.extractDates, .tagTravel], enabled: true, lastRun: nil)
        ]
    }

    private func tokens(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }
    }

    private func normalized(_ v: [Double]) -> [Double] {
        let length = sqrt(v.reduce(0) { $0 + $1 * $1 }); guard length > 0 else { return v }; return v.map { $0 / length }
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        return zip(a,b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private func persistIndex() {
        do { try JSONEncoder().encode(chunks).write(to: indexURL, options: .atomic) } catch { }
    }

    private func persist() {
        let state = PersistedState(workspaces: workspaces, activeWorkspaceID: activeWorkspaceID, branches: branches, entities: entities, insights: insights, contextTray: contextTray, automations: automations, miniApps: miniApps, ontology: ontology, performanceMode: performanceMode, feedback: feedback, semanticCache: semanticCache)
        do { try JSONEncoder().encode(state).write(to: saveURL, options: .atomic) } catch { }
    }

    private func load() {
        if let data = try? Data(contentsOf: saveURL), let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            workspaces = state.workspaces; activeWorkspaceID = state.activeWorkspaceID; branches = state.branches; entities = state.entities; insights = state.insights; contextTray = state.contextTray; automations = state.automations; miniApps = state.miniApps; ontology = state.ontology; performanceMode = state.performanceMode; feedback = state.feedback; semanticCache = state.semanticCache
        }
        if let data = try? Data(contentsOf: indexURL), let decoded = try? JSONDecoder().decode([NexusV9Chunk].self, from: data) { chunks = decoded; diagnostics.indexedChunks = decoded.count }
    }
}

extension Array {
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>(); return filter { seen.insert(key($0)).inserted }
    }
}
