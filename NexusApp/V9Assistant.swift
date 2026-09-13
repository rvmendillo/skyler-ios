import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NexusV9Assistant: ObservableObject {
    static let shared = NexusV9Assistant()
    @Published var status = "Ready"
    @Published var busy = false
    @Published var lastCitations: [NexusV9Citation] = []
    @Published var lastContextBudget = ""

    private let style = """
    You are NEXUS, a polished private personal intelligence assistant. Answer like a high-quality consumer AI: useful answer first, natural language, concise unless detail helps. Never expose hidden reasoning. Clearly distinguish evidence from inference. For personal claims, use only the supplied NEXUS evidence. If evidence is incomplete, say what is missing. Cite source labels naturally when useful.
    """

    func answer(question raw: String,
                records: [KnowledgeRecord],
                attachments: [NexusV8FileItem] = [],
                history: [ChatMessage] = [],
                extraContext: String = "",
                onPartial: ((String) -> Void)? = nil) async -> NexusV8SharedAnswer {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return NexusV8SharedAnswer(text: "Ask me anything about your NEXUS data.", evidence: []) }
        busy = true; defer { busy = false }
        let intelligence = NexusV9IntelligenceStore.shared
        if let cached = intelligence.cachedAnswer(similarTo: question), attachments.isEmpty, extraContext.isEmpty {
            status = "Ready • semantic cache"
            onPartial?(cached.answer)
            return NexusV8SharedAnswer(text: cached.answer, evidence: cached.evidence)
        }

        if intelligence.chunks.isEmpty && (!records.isEmpty || !NexusV8FileLibrary.shared.files.isEmpty) {
            status = "Building retrieval index…"
            await intelligence.index(records: records, files: NexusV8FileLibrary.shared.files)
        }

        let route = intelligence.routeLabel(question: question, attachments: attachments)
        status = route
        let retrieved = intelligence.evidenceContext(for: question)
        lastCitations = retrieved.1
        let tray = intelligence.contextTray.map { "[CONTEXT TRAY • \($0.label)]\n\($0.preview)" }.joined(separator: "\n\n")
        let recent = history.suffix(6).map { "\($0.role == .user ? "User" : "NEXUS"): \(String($0.text.prefix(700)))" }.joined(separator: "\n")
        let combined = """
        USER QUESTION:
        \(question)

        RECENT CONVERSATION:
        \(recent)

        HYBRID RETRIEVAL EVIDENCE:
        \(retrieved.0)

        PINNED CONTEXT TRAY:
        \(tray)

        EXTRA FILE / SELECTION CONTEXT:
        \(String(extraContext.prefix(18_000)))
        """
        lastContextBudget = intelligence.contextBudgetSummary(for: question)

        let q = question.lowercased()
        let deep = route.contains("Deep") || q.contains("exhaustive") || q.contains("comprehensive")
        let visual = route.contains("Vision")
        if deep || visual {
            let previous = NexusV8FastChatHub.shared.mode
            NexusV8FastChatHub.shared.mode = deep ? .deep : .automatic
            let bridgedQuestion = "\(question)\n\nV9 RETRIEVED CONTEXT:\n\(String(combined.prefix(18_000)))"
            let result = await NexusV8FastChatHub.shared.answer(question: bridgedQuestion, records: records, attachments: attachments, history: history, onPartial: onPartial)
            NexusV8FastChatHub.shared.mode = previous
            let evidence = Array(Set(result.evidence + retrieved.1.map { "\($0.sourceName) • \($0.location)" })).prefix(14)
            let final = NexusV8SharedAnswer(text: result.text, evidence: Array(evidence))
            if !intelligence.privateMode { intelligence.cache(question: question, answer: final.text, evidence: final.evidence) }
            status = "Ready"
            return final
        }

        if NexusPortableModelStore.shared.activeModelID.isEmpty { await intelligence.warmBestLocalModel() }
        let prompt = """
        Answer the user from the context below. Prefer cited evidence over assumptions. If the question is general and the personal evidence is irrelevant, answer generally without pretending the vault supports it.

        \(String(combined.prefix(intelligence.performanceMode.maxContextCharacters)))
        """
        var output = ""
        if !NexusPortableModelStore.shared.activeModelID.isEmpty,
           let local = await NexusPortableModelStore.shared.streamRespond(prompt, systemContext: style, onPartial: { partial in
               output = partial
               onPartial?(partial)
           }), !local.isEmpty {
            output = local
        } else if let system = await NexusIntelligenceEngine.respond(question: prompt, context: style), !system.isEmpty {
            output = system; onPartial?(system)
        }

        if output.isEmpty {
            if retrieved.1.isEmpty && extraContext.isEmpty { output = "I don’t have enough relevant local evidence for that yet. Import or connect the source that would answer it, or load a local language model for general offline chat." }
            else { output = "I found relevant evidence, but no language model is currently available to synthesize it. Load a shared local model and I can answer from the indexed sources immediately." }
            onPartial?(output)
        }

        var evidence = retrieved.1.map { "\($0.sourceName) • \($0.location)" }
        if !attachments.isEmpty { evidence.append(contentsOf: attachments.map { "Attached: \($0.name)" }) }
        if retrieved.1.isEmpty { evidence.append("Missing information: no strongly matching indexed evidence was found") }
        let final = NexusV8SharedAnswer(text: output.trimmingCharacters(in: .whitespacesAndNewlines), evidence: Array(evidence.uniqued(by: { $0 }).prefix(14)))
        if !intelligence.privateMode { intelligence.cache(question: question, answer: final.text, evidence: final.evidence) }
        status = "Ready"
        return final
    }
}

struct AskV9View: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var assistant = NexusV9Assistant.shared
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var language = NexusPortableModelStore.shared
    @State private var draft = ""
    @State private var attachedIDs: Set<UUID> = []
    @State private var showImporter = false
    @State private var showContext = false
    @State private var importError = ""
    @State private var attachmentHistory: [UUID:[UUID]] = [:]

    private var attachments: [NexusV8FileItem] { library.files.filter { attachedIDs.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.chatMessages) { message in messageView(message).id(message.id) }
                    }.padding()
                }
                .onChange(of: model.chatMessages.count) { _, _ in if let id = model.chatMessages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
            if !attachments.isEmpty { attachmentStrip }
            composer
        }
        .navigationTitle("NEXUS V9 Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showContext = true } label: { Image(systemName: "tray.full.fill") }
                Menu {
                    Button("Branch this conversation") { intelligence.branchCurrentConversation(model.chatMessages, name: "Branch \(intelligence.branches.count + 1)") }
                    Button("Clear chat") { model.clearChat() }
                    Toggle("Private session", isOn: $intelligence.privateMode)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showContext) { NavigationStack { NexusV9ContextInspectorView(query: draft) } }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .image, .pdf, .plainText, .commaSeparatedText], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get(); let imported = try library.importURLs(urls); attachedIDs.formUnion(imported.map(\.id)); intelligence.runAutomations(for: .fileImport, importedNames: imported.map(\.name))
                Task { await intelligence.index(records: model.records, files: library.files) }
            } catch { importError = error.localizedDescription }
        }
        .alert("Import failed", isPresented: Binding(get: { !importError.isEmpty }, set: { if !$0 { importError = "" } })) { Button("OK") { importError = "" } } message: { Text(importError) }
    }

    private var header: some View {
        VStack(spacing: 7) {
            HStack {
                Label(assistant.status, systemImage: assistant.busy ? "sparkles" : "bolt.fill").font(.caption).foregroundStyle(.cyan)
                Spacer()
                Text(language.activeModelID.isEmpty ? "No LLM loaded" : "Resident model").font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Picker("Workspace", selection: Binding(get: { intelligence.activeWorkspaceID }, set: { intelligence.activeWorkspaceID = $0 })) {
                    ForEach(intelligence.workspaces) { Text($0.name).tag(Optional($0.id)) }
                }.pickerStyle(.menu)
                Spacer()
                if intelligence.privateMode { Label("Private", systemImage: "eye.slash.fill").font(.caption).foregroundStyle(.orange) }
                Text(intelligence.performanceMode.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.horizontal).padding(.vertical, 8).background(.thinMaterial)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { item in
                    NavigationLink { NexusV9FileIntelligenceView(item: item) } label: {
                        HStack(spacing: 5) { Image(systemName: item.kindLabel == "Image" ? "photo" : item.ext == "pdf" ? "doc.richtext" : "doc"); Text(item.name).lineLimit(1); Button { attachedIDs.remove(item.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                            .font(.caption).padding(8).background(.thinMaterial, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal).padding(.vertical, 6)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button { showImporter = true } label: { Image(systemName: "paperclip.circle.fill").font(.title2) }
            TextField("Message NEXUS", text: $draft, axis: .vertical).lineLimit(1...6).textFieldStyle(.roundedBorder)
            Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(assistant.busy || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty))
        }.padding().background(.ultraThinMaterial)
    }

    @ViewBuilder private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 7) {
            HStack { if message.role == .user { Spacer() }; Text(message.text.isEmpty ? "…" : message.text).textSelection(.enabled).padding(12).background(message.role == .user ? Color.cyan.opacity(0.20) : Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 18)); if message.role == .assistant { Spacer() } }
            if let ids = attachmentHistory[message.id], !ids.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(ids, id: \.self) { id in if let file = library.files.first(where: { $0.id == id }) { NavigationLink { NexusV9FileIntelligenceView(item: file) } label: { Label(file.name, systemImage: "doc.fill").font(.caption).padding(6).background(.thinMaterial, in: Capsule()) } } } } }
            }
            if message.role == .assistant && !message.evidence.isEmpty { Text(message.evidence.prefix(5).joined(separator: " • ")).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = q.isEmpty ? "Analyze the attached files and tell me what matters." : q
        let sent = attachments
        draft = ""; attachedIDs.removeAll()
        let user = ChatMessage(role: .user, text: effective, evidence: [])
        model.chatMessages.append(user); attachmentHistory[user.id] = sent.map(\.id)
        let placeholder = ChatMessage(role: .assistant, text: "", evidence: [])
        model.chatMessages.append(placeholder)
        Task {
            let result = await assistant.answer(question: effective, records: model.records, attachments: sent, history: Array(model.chatMessages.dropLast(1)), onPartial: { partial in
                if let index = model.chatMessages.firstIndex(where: { $0.id == placeholder.id }) {
                    model.chatMessages[index] = ChatMessage(role: .assistant, text: partial, evidence: [])
                }
            })
            if let index = model.chatMessages.firstIndex(where: { $0.id == placeholder.id }) {
                model.chatMessages[index] = ChatMessage(role: .assistant, text: result.text, evidence: result.evidence)
            } else { model.chatMessages.append(ChatMessage(role: .assistant, text: result.text, evidence: result.evidence)) }
        }
    }
}

struct NexusV9ContextInspectorView: View {
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    let query: String
    var body: some View {
        List {
            Section("Context budget") { Text(query.isEmpty ? "Type a question in Chat to preview its retrieval budget." : intelligence.contextBudgetSummary(for: query)); Text("NEXUS keeps the large knowledge base indexed locally and sends only the most relevant evidence into active model context.").font(.caption).foregroundStyle(.secondary) }
            Section("Pinned context tray") { if intelligence.contextTray.isEmpty { Text("Nothing pinned yet.") } else { ForEach(intelligence.contextTray) { item in VStack(alignment: .leading) { Text(item.label).font(.headline); Text(item.preview).font(.caption).lineLimit(3) } }; Button(role: .destructive) { intelligence.clearTray() } label: { Text("Clear tray") } } }
            Section("Diagnostics") { LabeledContent("Indexed chunks", value: "\(intelligence.diagnostics.indexedChunks)"); LabeledContent("Last retrieval", value: "\(intelligence.diagnostics.lastRetrievalCount)"); LabeledContent("Last context", value: "\(intelligence.diagnostics.lastContextCharacters) chars"); LabeledContent("Cache hits", value: "\(intelligence.diagnostics.cacheHits)"); LabeledContent("Route", value: intelligence.diagnostics.lastRoute) }
        }.navigationTitle("Context Inspector")
    }
}
