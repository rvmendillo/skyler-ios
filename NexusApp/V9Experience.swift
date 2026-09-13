import Foundation
import SwiftUI

struct NexusV9PluginDescriptor: Identifiable, Hashable {
    let id: String; let name: String; let symbol: String; let detail: String; let capabilities: [String]
}

@MainActor
final class NexusV9PluginRegistry: ObservableObject {
    static let shared = NexusV9PluginRegistry()
    @Published var plugins: [NexusV9PluginDescriptor] = [
        .init(id: "retrieval", name: "Hybrid Retrieval", symbol: "magnifyingglass.circle.fill", detail: "Local embeddings, lexical search, recency and learned reranking", capabilities: ["semantic search","rerank","context compression"]),
        .init(id: "documents", name: "Document Intelligence", symbol: "doc.text.magnifyingglass", detail: "PDF, text, OCR, CSV and code processors", capabilities: ["OCR","tables","code","citations"]),
        .init(id: "vision", name: "Vision Runtime", symbol: "eye.fill", detail: "Shared multimodal model for images, scanned pages, diagrams and charts", capabilities: ["images","PDF layouts","charts"]),
        .init(id: "models", name: "Local Model Router", symbol: "cpu.fill", detail: "Resident GGUF model, streaming and deep escalation", capabilities: ["streaming","routing","ensemble"]),
        .init(id: "insights", name: "Insight Engine", symbol: "sparkles", detail: "Deduplicated evidence-backed change and pattern detection", capabilities: ["insights","timeline","change detection"]),
        .init(id: "platform", name: "Platform Actions", symbol: "square.grid.3x3.fill", detail: "Shortcuts, Spotlight, deep links, share capture and exports", capabilities: ["Shortcuts","Spotlight","exports"])
    ]
}

struct NexusV9UndoEntry: Identifiable {
    let id = UUID(); let title: String; let createdAt = Date(); let undo: @MainActor () -> Void
}

@MainActor
final class NexusV9ActionJournal: ObservableObject {
    static let shared = NexusV9ActionJournal()
    @Published var entries: [NexusV9UndoEntry] = []
    func record(_ title: String, undo: @escaping @MainActor () -> Void) { entries.insert(NexusV9UndoEntry(title: title, undo: undo), at: 0); if entries.count > 20 { entries.removeLast(entries.count - 20) } }
    func undoLatest() { guard let entry = entries.first else { return }; entry.undo(); entries.removeFirst() }
}

struct NexusV9AgentProposal: Identifiable, Hashable {
    enum Action: String, Hashable { case addToWorkspace, pinContext, createDashboard, createAutomation, forgetSource }
    let id = UUID(); let title: String; let detail: String; let action: Action; let referenceID: String
}

@MainActor
final class NexusV9AgentCenter: ObservableObject {
    static let shared = NexusV9AgentCenter()
    @Published var proposals: [NexusV9AgentProposal] = []
    func proposeFromFiles(_ files: [NexusV8FileItem]) {
        proposals = files.prefix(8).map { file in NexusV9AgentProposal(title: "Organize \(file.name)", detail: "Add this file to the active workspace and pin it for the next AI question.", action: .addToWorkspace, referenceID: file.id.uuidString) }
    }
    func approve(_ proposal: NexusV9AgentProposal) {
        let store = NexusV9IntelligenceStore.shared
        if proposal.action == .addToWorkspace, let fileID = UUID(uuidString: proposal.referenceID), let index = store.workspaces.firstIndex(where: { $0.id == store.activeWorkspaceID }), let file = NexusV8FileLibrary.shared.files.first(where: { $0.id == fileID }) {
            let old = store.workspaces[index].fileIDs
            store.workspaces[index].fileIDs.insert(fileID)
            store.addToTray(kind: .file, referenceID: fileID.uuidString, label: file.name, preview: NexusV8FileSupport.metadata(file))
            NexusV9ActionJournal.shared.record("Organize \(file.name)") { store.workspaces[index].fileIDs = old }
        }
        proposals.removeAll { $0.id == proposal.id }
    }
}

struct NexusV9WorkspacesView: View {
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var name = ""
    var body: some View {
        List {
            Section("Create workspace / project") {
                TextField("Project name", text: $name)
                Button("Create") { store.createWorkspace(name: name); name = "" }
            }
            Section("Workspaces") {
                ForEach(store.workspaces) { workspace in
                    Button { store.activeWorkspaceID = workspace.id } label: {
                        HStack { Image(systemName: workspace.symbol); VStack(alignment: .leading) { Text(workspace.name).font(.headline); Text("\(workspace.fileIDs.count) files • \(workspace.isPrivate ? "private" : "global-searchable")").font(.caption).foregroundStyle(.secondary) }; Spacer(); if store.activeWorkspaceID == workspace.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) } }
                    }.buttonStyle(.plain)
                }
            }
            if let active = store.workspaces.first(where: { $0.id == store.activeWorkspaceID }) {
                Section("Active workspace files") {
                    ForEach(library.files.filter { active.fileIDs.contains($0.id) }) { file in NavigationLink(file.name) { NexusV9FileIntelligenceView(item: file) } }
                    Menu("Add file") { ForEach(library.files.filter { !active.fileIDs.contains($0.id) }) { file in Button(file.name) { if let i = store.workspaces.firstIndex(where: { $0.id == active.id }) { store.workspaces[i].fileIDs.insert(file.id) } } } }
                }
            }
            Section("Conversation branches") { ForEach(store.branches) { branch in VStack(alignment: .leading) { Text(branch.name).font(.headline); Text("\(branch.messages.count) messages • \(branch.createdAt.formatted())").font(.caption).foregroundStyle(.secondary) } } }
        }.navigationTitle("Projects & Branches")
    }
}

struct NexusV9InsightInboxView: View {
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    var body: some View {
        List {
            Section { Text("Insights evolve instead of duplicating themselves. Confidence rises when multiple indexed sources support the same pattern.").font(.caption).foregroundStyle(.secondary) }
            ForEach(store.insights.filter { !$0.dismissed }) { insight in
                NavigationLink { NexusV9InsightDetailView(insight: insight) } label: {
                    VStack(alignment: .leading, spacing: 5) { HStack { Text(insight.title).font(.headline); Spacer(); Text(insight.confidence, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()).foregroundStyle(.cyan) }; Text(insight.summary).font(.subheadline).lineLimit(4); Text("\(insight.evidence.count) evidence links • updated \(insight.lastUpdated.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("Insight Inbox")
    }
}

struct NexusV9InsightDetailView: View {
    let insight: NexusV9Insight
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    var body: some View {
        List {
            Section { Text(insight.summary).textSelection(.enabled); ProgressView(value: insight.confidence); Text("Evidence strength: \(strength)").font(.caption).foregroundStyle(.secondary) }
            Section("Evidence provenance") { ForEach(insight.evidence) { citation in NavigationLink { NexusV9CitationSourceView(citation: citation) } label: { VStack(alignment: .leading) { Text(citation.sourceName).font(.headline); Text(citation.location).font(.caption).foregroundStyle(.cyan); Text(citation.excerpt).font(.caption).lineLimit(4) } } } }
            Section { Button("Pin insight to context tray") { store.addToTray(kind: .insight, referenceID: insight.id.uuidString, label: insight.title, preview: insight.summary) } }
        }.navigationTitle(insight.title)
    }
    private var strength: String { insight.confidence >= 0.8 ? "Strong recurring evidence" : insight.confidence >= 0.55 ? "Moderate evidence" : "Early / limited evidence" }
}

struct NexusV9Graph2View: View {
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    @State private var selected: NexusV9Entity?
    var body: some View {
        List {
            Section("Knowledge Graph 2.0") { Text("Entities are merged from indexed evidence and can be corrected with your own ontology. Strength reflects recurrence, not importance or identity certainty.").font(.caption).foregroundStyle(.secondary) }
            Section("Strong entities") {
                ForEach(store.entities.sorted { $0.strength > $1.strength }.prefix(80)) { entity in
                    Button { selected = entity } label: { HStack { VStack(alignment: .leading) { Text(entity.canonicalName).font(.headline); Text("\(entity.sourceIDs.count) linked evidence items • \(entity.kind.rawValue)").font(.caption).foregroundStyle(.secondary) }; Spacer(); ProgressView(value: entity.strength).frame(width: 70) } }.buttonStyle(.plain)
                }
            }
        }.navigationTitle("Knowledge Graph 2.0").sheet(item: $selected) { entity in NavigationStack { NexusV9EntityDetailView(entity: entity) } }
    }
}

struct NexusV9EntityDetailView: View {
    let entity: NexusV9Entity
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    @State private var alias = ""
    var body: some View {
        List {
            Section { Text(entity.canonicalName).font(.title2.bold()); Text("Aliases: \(entity.aliases.sorted().joined(separator: ", "))").font(.caption); Text("Linked sources: \(entity.sourceIDs.count)") }
            Section("Teach NEXUS") { TextField("Alias or phrase", text: $alias); Button("Map alias to this entity") { guard !alias.isEmpty else { return }; store.teach(alias: alias, means: entity.canonicalName); alias = "" } }
            Section("Related evidence") { ForEach(store.chunks.filter { entity.sourceIDs.contains($0.sourceID) }.prefix(25)) { chunk in VStack(alignment: .leading) { Text(chunk.title).font(.headline); Text(chunk.text).font(.caption).lineLimit(4) } } }
        }.navigationTitle("Entity")
    }
}

struct NexusV9Timeline2View: View {
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    private var dated: [NexusV9Chunk] { store.chunks.filter { $0.timestamp != nil }.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) } }
    var body: some View {
        List {
            Section { Text("A unified timeline built from every indexed source. Search and change detection operate on the same evidence layer.").font(.caption).foregroundStyle(.secondary) }
            ForEach(dated.prefix(500)) { chunk in HStack(alignment: .top) { Text(chunk.timestamp?.formatted(date: .abbreviated, time: .omitted) ?? "").font(.caption.monospacedDigit()).frame(width: 78, alignment: .leading).foregroundStyle(.cyan); VStack(alignment: .leading) { Text(chunk.title.isEmpty ? chunk.sourceName : chunk.title).font(.headline); Text(chunk.text).font(.caption).lineLimit(3) } } }
        }.navigationTitle("Universal Timeline")
    }
}

struct NexusV9ChangeDetectionView: View {
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    private var result: (newer:[String], older:[String]) {
        let dated = store.chunks.compactMap { c -> (NexusV9Chunk,Date)? in c.timestamp.map { (c,$0) } }.sorted { $0.1 < $1.1 }
        guard dated.count >= 10 else { return ([],[]) }
        let mid = dated.count / 2
        let old = tokenCounts(dated[..<mid].map { $0.0.text }.joined(separator: " "))
        let new = tokenCounts(dated[mid...].map { $0.0.text }.joined(separator: " "))
        let newer = new.keys.sorted { (new[$0,default:0] - old[$0,default:0]) > (new[$1,default:0] - old[$1,default:0]) }.filter { new[$0,default:0] > old[$0,default:0] }.prefix(20)
        let older = old.keys.sorted { (old[$0,default:0] - new[$0,default:0]) > (old[$1,default:0] - new[$1,default:0]) }.filter { old[$0,default:0] > new[$0,default:0] }.prefix(20)
        return (Array(newer),Array(older))
    }
    var body: some View {
        List { Section("Increasing signals") { ForEach(result.newer, id: \.self) { Label($0, systemImage: "arrow.up.right") } }; Section("Decreasing signals") { ForEach(result.older, id: \.self) { Label($0, systemImage: "arrow.down.right") } }; Section { Text("This compares the earlier and later halves of dated indexed evidence. It measures changing language/signals, not causation.").font(.caption).foregroundStyle(.secondary) } }.navigationTitle("What Changed?")
    }
    private func tokenCounts(_ text: String) -> [String:Int] { var out:[String:Int]=[:]; for t in text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) where t.count >= 5 { out[t,default:0]+=1 }; return out }
}

struct NexusV9DashboardView: View {
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    @State private var prompt = ""
    var body: some View {
        List {
            Section("Generate mini app / dashboard") { TextField("e.g. Track my travel plans and savings", text: $prompt, axis: .vertical); Button("Generate") { store.createMiniApp(from: prompt); prompt = "" } }
            Section("Generated") { ForEach(store.miniApps) { app in NavigationLink { NexusV9MiniAppView(app: app) } label: { Label { VStack(alignment: .leading) { Text(app.title).font(.headline); Text(app.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: symbol(app.kind)).foregroundStyle(.cyan) } } } }
            Section("Live intelligence dashboard") { LabeledContent("Indexed evidence", value: "\(store.chunks.count)"); LabeledContent("Entities", value: "\(store.entities.count)"); LabeledContent("Insights", value: "\(store.insights.count)"); LabeledContent("Projects", value: "\(store.workspaces.count)"); LabeledContent("Retrieval cache", value: "\(store.diagnostics.cacheHits) hits") }
        }.navigationTitle("Dashboards & Mini Apps")
    }
    private func symbol(_ kind: NexusV9MiniApp.Kind) -> String { switch kind { case .tracker: return "checklist"; case .calculator: return "function"; case .timeline: return "clock"; case .quiz: return "questionmark.bubble"; case .dashboard: return "chart.bar.xaxis"; case .comparison: return "rectangle.split.2x1" } }
}

struct NexusV9MiniAppView: View {
    let app: NexusV9MiniApp
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    @State private var a = ""; @State private var b = ""
    var body: some View {
        List {
            Section { Text(app.sourceQuery).font(.subheadline); Text("Generated locally from a safe NEXUS template; it never executes arbitrary downloaded code.").font(.caption).foregroundStyle(.secondary) }
            switch app.kind {
            case .calculator:
                Section("Calculator") { TextField("Value A", text: $a).keyboardType(.decimalPad); TextField("Value B", text: $b).keyboardType(.decimalPad); let av = Double(a) ?? 0; let bv = Double(b) ?? 0; LabeledContent("A + B", value: String(av + bv)); LabeledContent("A × B", value: String(av * bv)) }
            case .timeline:
                Section("Related timeline") { ForEach(store.search(app.sourceQuery, limit: 20).map(\.chunk)) { c in VStack(alignment: .leading) { Text(c.timestamp?.formatted(date: .abbreviated, time: .omitted) ?? "Undated").font(.caption).foregroundStyle(.cyan); Text(c.title).font(.headline); Text(c.text).font(.caption).lineLimit(3) } } }
            case .quiz:
                Section("Study prompts") { ForEach(store.search(app.sourceQuery, limit: 8).map(\.chunk)) { c in Text("What can you recall about: \(c.title.isEmpty ? String(c.text.prefix(60)) : c.title)?") } }
            case .comparison:
                Section { NavigationLink("Choose two files to compare") { NexusV9CompareFilesView() } }
            case .tracker:
                Section("Evidence tracker") { ForEach(store.search(app.sourceQuery, limit: 20)) { h in HStack { Image(systemName: "checkmark.circle"); VStack(alignment: .leading) { Text(h.chunk.title).font(.headline); Text(h.chunk.sourceName).font(.caption) } } } }
            case .dashboard:
                Section("Top evidence") { ForEach(store.search(app.sourceQuery, limit: 15)) { h in VStack(alignment: .leading) { HStack { Text(h.chunk.title).font(.headline); Spacer(); Text(h.score, format: .percent.precision(.fractionLength(0))).font(.caption) }; Text(h.chunk.text).font(.caption).lineLimit(3) } } }
            }
        }.navigationTitle(app.title)
    }
}

struct NexusV9AutomationsView: View {
    @ObservedObject private var store = NexusV9IntelligenceStore.shared
    @State private var ruleText = ""
    var body: some View {
        List {
            Section("Natural-language automation") { TextField("Whenever I import a bank CSV, update my finance dashboard", text: $ruleText, axis: .vertical); Button("Create rule") { createRule() }; Text("Rules are local and event-driven while NEXUS is active. iOS may suspend ordinary apps in the background, so folder watches resume when NEXUS becomes active.").font(.caption).foregroundStyle(.secondary) }
            Section("Rules") { ForEach($store.automations) { $rule in VStack(alignment: .leading) { Toggle(rule.name, isOn: $rule.enabled); Text("\(rule.trigger.rawValue) → \(rule.actions.map(\.rawValue).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary); if let date = rule.lastRun { Text("Last run \(date.formatted())").font(.caption2) } } } }
        }.navigationTitle("Automations")
    }
    private func createRule() {
        let lower = ruleText.lowercased(); guard !lower.isEmpty else { return }
        let contains = lower.contains("csv") ? "csv" : lower.contains("pdf") ? "pdf" : ""
        var actions: [NexusV9AutomationRule.Action] = [.index, .summarize]
        if lower.contains("finance") || lower.contains("bank") { actions.append(contentsOf: [.tagFinance,.buildDashboard]) }
        if lower.contains("travel") { actions.append(contentsOf: [.extractDates,.tagTravel]) }
        store.automations.append(NexusV9AutomationRule(id: UUID(), name: String(ruleText.prefix(70)), trigger: .fileImport, contains: contains, actions: Array(Set(actions)), enabled: true, lastRun: nil)); ruleText = ""
    }
}

struct NexusV9AgentView: View {
    @ObservedObject private var agent = NexusV9AgentCenter.shared
    @ObservedObject private var journal = NexusV9ActionJournal.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    var body: some View {
        List {
            Section { Button("Suggest safe organization actions") { agent.proposeFromFiles(library.files) }; Text("NEXUS proposes local organizational actions first. Nothing destructive is executed without confirmation, and reversible organizational actions create an undo checkpoint.").font(.caption).foregroundStyle(.secondary) }
            Section("Proposals") { ForEach(agent.proposals) { p in VStack(alignment: .leading) { Text(p.title).font(.headline); Text(p.detail).font(.caption); HStack { Button("Approve") { agent.approve(p) }.buttonStyle(.borderedProminent); Button("Dismiss") { agent.proposals.removeAll { $0.id == p.id } }.buttonStyle(.bordered) } } } }
            Section("Undo") { Button("Undo latest") { journal.undoLatest() }.disabled(journal.entries.isEmpty); ForEach(journal.entries) { e in Text(e.title + " • " + e.createdAt.formatted()).font(.caption) } }
        }.navigationTitle("Local Agent Actions")
    }
}

struct NexusV9PluginView: View {
    @ObservedObject private var registry = NexusV9PluginRegistry.shared
    var body: some View { List { ForEach(registry.plugins) { plugin in VStack(alignment: .leading, spacing: 4) { Label(plugin.name, systemImage: plugin.symbol).font(.headline); Text(plugin.detail).font(.caption).foregroundStyle(.secondary); Text(plugin.capabilities.joined(separator: " • ")).font(.caption2).foregroundStyle(.cyan) } } }.navigationTitle("Plugin Architecture") }
}
