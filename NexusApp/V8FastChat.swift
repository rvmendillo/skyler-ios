import Foundation
import SwiftUI

enum NexusV8ChatSpeedMode: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case automatic = "Auto"
    case deep = "Deep"

    var id: String { rawValue }
}

@MainActor
final class NexusV8FastChatHub: ObservableObject {
    static let shared = NexusV8FastChatHub()

    @Published var mode: NexusV8ChatSpeedMode = .automatic
    @Published var busy = false
    @Published var status = "Ready"
    @Published var lastError = ""

    private var answerCache: [String:NexusV8SharedAnswer] = [:]
    private var answerCacheOrder: [String] = []
    private var fileTextCache: [String:String] = [:]
    private var fileTextCacheOrder: [String] = []

    private let friendlyStyle = """
    You are NEXUS, a polished consumer AI assistant. Answer naturally like ChatGPT or Claude: direct, clear, friendly, concise by default, and detailed only when useful. Start with the answer, not implementation details. Avoid internal engine names, model jargon, scoring jargon, and hidden reasoning unless the user explicitly asks. Use the supplied evidence for personal claims. If evidence is incomplete, say so plainly.
    """

    func answer(question rawQuestion: String,
                records: [KnowledgeRecord],
                attachments: [NexusV8FileItem],
                history: [ChatMessage],
                onPartial: ((String) -> Void)? = nil) async -> NexusV8SharedAnswer {
        let clean = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = clean.isEmpty ? (attachments.isEmpty ? "What stands out in my data?" : "Analyze these files and tell me what matters.") : clean
        let resolved = resolvedMode(question: question, attachments: attachments)
        let key = cacheKey(question: question, records: records, attachments: attachments, mode: resolved)
        if let cached = answerCache[key] {
            status = "Ready • cached"
            onPartial?(cached.text)
            return cached
        }

        busy = true
        lastError = ""
        defer { busy = false }

        status = resolved == .deep ? "Preparing a deeper answer…" : "Finding the most relevant context…"
        let recordContext = retrieveRelevantContext(question: question, records: records, deep: resolved == .deep)
        let historyContext = compactHistory(history)
        let attachment = await attachmentContext(items: attachments, question: question, mode: resolved)

        let compactContext = """
        RECENT CONVERSATION:
        \(historyContext)

        RELEVANT PERSONAL DATA:
        \(recordContext)

        ATTACHED FILES:
        \(attachment.context)
        """

        if resolved == .deep {
            status = "Cross-checking a difficult request…"
            let deep = await deepAnswer(question: question,
                                        records: records,
                                        compactContext: compactContext,
                                        attachmentEvidence: attachment.evidence,
                                        onPartial: onPartial)
            remember(deep, for: key)
            status = "Ready"
            return deep
        }

        status = "Generating answer…"
        let primary = await primaryAnswer(question: question, context: compactContext, onPartial: onPartial)
        let fallback = primary.isEmpty ? fallbackAnswer(question: question, context: compactContext) : primary
        var evidence = attachment.evidence
        if !recordContext.isEmpty { evidence.append("Used a small relevant subset of your NEXUS data instead of scanning the full vault") }
        if !historyContext.isEmpty { evidence.append("Used recent chat context") }
        let result = NexusV8SharedAnswer(text: friendlyCleanup(fallback), evidence: unique(evidence, limit: 10))
        if primary.isEmpty { onPartial?(result.text) }
        remember(result, for: key)
        status = "Ready"
        return result
    }

    private func resolvedMode(question: String, attachments: [NexusV8FileItem]) -> NexusV8ChatSpeedMode {
        switch mode {
        case .fast: return .fast
        case .deep: return .deep
        case .automatic:
            let q = question.lowercased()
            let deepSignals = [
                "deep analysis", "comprehensive", "thorough", "cross-check", "cross check", "compare all",
                "find contradictions", "all patterns", "analyze everything", "very detailed", "exhaustive"
            ]
            if attachments.count >= 4 || deepSignals.contains(where: q.contains) { return .deep }
            return .fast
        }
    }

    private func primaryAnswer(question: String,
                               context: String,
                               onPartial: ((String) -> Void)? = nil) async -> String {
        let portable = NexusPortableModelStore.shared
        let prompt = """
        Answer the user's question using only the relevant context below. Do not describe the retrieval process. If the context is unrelated, answer generally and say when personal data is insufficient.

        USER QUESTION:
        \(question)

        CONTEXT:
        \(String(context.prefix(15_000)))
        """

        if !portable.activeModelID.isEmpty,
           let local = await portable.streamRespond(prompt, systemContext: friendlyStyle, onPartial: { partial in
               onPartial?(self.friendlyCleanup(partial))
           }),
           !local.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return local
        }

        if let system = await NexusIntelligenceEngine.respond(question: prompt, context: friendlyStyle),
           !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onPartial?(friendlyCleanup(system))
            return system
        }
        return ""
    }

    private func deepAnswer(question: String,
                            records: [KnowledgeRecord],
                            compactContext: String,
                            attachmentEvidence: [String],
                            onPartial: ((String) -> Void)? = nil) async -> NexusV8SharedAnswer {
        let deep = await NexusV7AnswerEngine.answer(question: question, records: records)
        let draft = """
        FAST RETRIEVAL CONTEXT:
        \(String(compactContext.prefix(16_000)))

        DEEP ANALYSIS DRAFT:
        \(String(deep.answer.prefix(9_000)))
        """
        let final = await primaryAnswer(question: question, context: draft, onPartial: onPartial)
        var evidence = attachmentEvidence + Array(deep.evidence.prefix(8))
        evidence.append("Deep mode used the broader NEXUS analysis pipeline")
        if !deep.disagreements.isEmpty { evidence.append(contentsOf: deep.disagreements.prefix(2).map { "Caveat: \($0)" }) }
        let text = friendlyCleanup(final.isEmpty ? deep.answer : final)
        if final.isEmpty { onPartial?(text) }
        return NexusV8SharedAnswer(text: text, evidence: unique(evidence, limit: 12))
    }

    private func retrieveRelevantContext(question: String, records: [KnowledgeRecord], deep: Bool) -> String {
        guard !records.isEmpty else { return "" }
        let terms = queryTerms(question)
        let sampleLimit = deep ? 3500 : 1600
        let maxRecords = deep ? 22 : 10
        let maxCharacters = deep ? 18_000 : 8_500
        let start = max(0, records.count - sampleLimit)
        let slice = records[start..<records.count]

        var ranked: [(Int, Int, KnowledgeRecord)] = []
        ranked.reserveCapacity(slice.count)
        for (offset, record) in slice.enumerated() {
            let title = record.title.lowercased()
            let text = record.text.lowercased()
            let source = record.source.lowercased()
            let metadata = record.metadata.values.joined(separator: " ").lowercased()
            var score = 0
            for term in terms {
                if title.contains(term) { score += 5 }
                if text.contains(term) { score += 3 }
                if metadata.contains(term) { score += 2 }
                if source.contains(term) { score += 1 }
            }
            if terms.isEmpty { score = 1 }
            if score > 0 { ranked.append((score, offset, record)) }
        }

        ranked.sort {
            if $0.0 != $1.0 { return $0.0 > $1.0 }
            return $0.1 > $1.1
        }

        if ranked.isEmpty {
            ranked = Array(records.suffix(maxRecords)).enumerated().map { index, record in
                (1, index, record)
            }
        }

        var out = ""
        for (_, _, record) in ranked.prefix(maxRecords) {
            let date = record.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "undated"
            let metadata = record.metadata.prefix(5).map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            let block = """
            [\(record.source) • \(record.kind.rawValue) • \(date)]
            \(record.title)
            \(String(record.text.prefix(900)))
            \(metadata)

            """
            if out.count + block.count > maxCharacters { break }
            out += block
        }
        return out
    }

    private func queryTerms(_ question: String) -> Set<String> {
        let ignored: Set<String> = ["the","and","for","with","that","this","from","what","when","where","which","who","why","how","are","was","were","have","has","had","can","could","would","should","about","into","your","you","my","me","our"]
        let parts = question.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(parts.filter { $0.count >= 3 && !ignored.contains($0) })
    }

    private func compactHistory(_ history: [ChatMessage]) -> String {
        let messages = history.suffix(6)
        var text = messages.map { message in
            "\(message.role == .user ? "User" : "NEXUS"): \(String(message.text.prefix(900)))"
        }.joined(separator: "\n")
        if text.count > 4_500 { text = String(text.suffix(4_500)) }
        return text
    }

    private func attachmentContext(items: [NexusV8FileItem],
                                   question: String,
                                   mode: NexusV8ChatSpeedMode) async -> (context: String, evidence: [String]) {
        guard !items.isEmpty else { return ("", []) }
        status = "Reading attached files…"
        var blocks: [String] = []
        var evidence: [String] = []
        let charsPerFile = mode == .deep ? 16_000 : 7_500

        for item in items {
            let cacheID = "\(item.path)|\(item.size)"
            if let cached = fileTextCache[cacheID] {
                blocks.append("FILE: \(item.name)\n\(String(cached.prefix(charsPerFile)))")
                evidence.append("Read cached file content: \(item.name)")
                continue
            }

            do {
                let extracted: String
                if item.ext == "pdf" {
                    extracted = try NexusV8FileSupport.pdfText(item.url,
                                                               maxPages: mode == .deep ? 35 : 14,
                                                               maxCharacters: charsPerFile)
                } else if NexusV8FileSupport.textExtensions.contains(item.ext) {
                    extracted = try NexusV8FileSupport.readableText(item.url,
                                                                    maxBytes: mode == .deep ? 1_200_000 : 600_000,
                                                                    maxCharacters: charsPerFile)
                } else {
                    extracted = NexusV8FileSupport.metadata(item)
                }
                rememberFileText(extracted, for: cacheID)
                blocks.append("FILE: \(item.name)\n\(extracted)")
                evidence.append("Read \(item.kindLabel.lowercased()): \(item.name)")
            } catch {
                blocks.append("FILE: \(item.name)\nCould not extract text: \(error.localizedDescription)")
            }
        }

        let q = question.lowercased()
        let wantsVisuals = q.contains("image") || q.contains("chart") || q.contains("layout") || q.contains("visual") || q.contains("screenshot") || q.contains("scan")
        let imageItems = items.filter { NexusV8FileSupport.imageExtensions.contains($0.ext) }
        let pdfItems = items.filter { $0.ext == "pdf" }
        var visualItems = imageItems
        if mode == .deep || wantsVisuals { visualItems.append(contentsOf: pdfItems) }

        if !visualItems.isEmpty {
            let vision = NexusMultimodalStore.shared
            if vision.activePresetID.isEmpty,
               vision.isDownloaded(vision.selectedPreset),
               !vision.busy {
                status = "Loading the shared vision model once…"
                await vision.load(vision.selectedPreset)
            }
            if !vision.activePresetID.isEmpty && !vision.busy {
                status = "Understanding visual content…"
                await vision.analyzeFiles(visualItems.map(\.url), question: question)
                for result in vision.results {
                    blocks.append("VISUAL ANALYSIS — \(result.fileName):\n\(String(result.answer.prefix(mode == .deep ? 5_500 : 3_200)))")
                    evidence.append("Vision: \(result.fileName)")
                }
            } else if !imageItems.isEmpty {
                evidence.append("Image attached; load a vision model for visual understanding")
            }
        }

        var context = blocks.joined(separator: "\n\n---\n\n")
        context = String(context.prefix(mode == .deep ? 24_000 : 12_000))
        return (context, evidence)
    }

    private func fallbackAnswer(question: String, context: String) -> String {
        if context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "I don’t have enough relevant local context to answer that from your NEXUS data yet. Load a shared language model or add/import the relevant data, and I can answer it more directly."
        }
        return "I found relevant local context for “\(question)”, but no language model is currently available to turn it into a full conversational answer. Load a shared language model for the fastest local chat experience."
    }

    private func friendlyCleanup(_ text: String) -> String {
        text
            .replacingOccurrences(of: "Portable local-model cross-checks:", with: "A few additional observations:")
            .replacingOccurrences(of: "ORIGINAL LOCAL ENSEMBLE:", with: "")
            .replacingOccurrences(of: "ADDITIONAL PORTABLE LOCAL LLM OPINIONS:", with: "Additional observations:")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cacheKey(question: String,
                          records: [KnowledgeRecord],
                          attachments: [NexusV8FileItem],
                          mode: NexusV8ChatSpeedMode) -> String {
        let first = records.first?.id ?? ""
        let last = records.last?.id ?? ""
        let files = attachments.map { $0.id.uuidString }.joined(separator: ",")
        return "\(mode.rawValue)|\(records.count)|\(first)|\(last)|\(files)|\(question.lowercased())"
    }

    private func remember(_ answer: NexusV8SharedAnswer, for key: String) {
        answerCache[key] = answer
        answerCacheOrder.removeAll { $0 == key }
        answerCacheOrder.append(key)
        while answerCacheOrder.count > 20 {
            let oldest = answerCacheOrder.removeFirst()
            answerCache.removeValue(forKey: oldest)
        }
    }

    private func rememberFileText(_ text: String, for key: String) {
        fileTextCache[key] = text
        fileTextCacheOrder.removeAll { $0 == key }
        fileTextCacheOrder.append(key)
        while fileTextCacheOrder.count > 24 {
            let oldest = fileTextCacheOrder.removeFirst()
            fileTextCache.removeValue(forKey: oldest)
        }
    }

    private func unique(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values where seen.insert(value).inserted {
            output.append(value)
            if output.count >= limit { break }
        }
        return output
    }
}

struct AskV8FastView: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var hub = NexusV8FastChatHub.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var draft = ""
    @State private var attachedIDs: Set<UUID> = []
    @State private var showImporter = false
    @State private var importError = ""
    @State private var attachmentCards: [UUID:[NexusV8FileItem]] = [:]

    private var attachments: [NexusV8FileItem] { library.files.filter { attachedIDs.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "bolt.fill").foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXUS Chat").font(.headline)
                    Text("Fast retrieval • streaming • shared loaded model • files").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink { FilesV8FastView() } label: { Image(systemName: "folder") }
                NavigationLink { PortableModelsV8View() } label: { Image(systemName: "cpu") }
            }
            .padding(.horizontal)
            .padding(.top, 10)

            Picker("Response mode", selection: $hub.mode) {
                ForEach(NexusV8ChatSpeedMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 11) {
                        ForEach(model.chatMessages) { message in
                            HStack {
                                if message.role == .user { Spacer(minLength: 42) }
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(message.text.isEmpty && message.role == .assistant ? "…" : message.text).textSelection(.enabled)
                                    if let cards = attachmentCards[message.id], !cards.isEmpty {
                                        ForEach(cards) { item in
                                            NavigationLink { NexusV8FileViewer(item: item) } label: {
                                                HStack(spacing: 7) {
                                                    Image(systemName: icon(for: item))
                                                    Text(item.name).lineLimit(1)
                                                    Spacer()
                                                    Image(systemName: "chevron.right").font(.caption2)
                                                }
                                                .font(.caption)
                                                .padding(8)
                                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    if !message.evidence.isEmpty {
                                        DisclosureGroup("Sources & notes") {
                                            VStack(alignment: .leading, spacing: 4) {
                                                ForEach(Array(message.evidence.enumerated()), id: \.offset) { _, item in
                                                    Text("• \(item)").font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }.padding(.top, 4)
                                        }
                                        .font(.caption.bold())
                                        .tint(.cyan)
                                    }
                                }
                                .padding(12)
                                .background(message.role == .user ? Color.cyan.opacity(0.20) : Color.secondary.opacity(0.11), in: RoundedRectangle(cornerRadius: 17))
                                if message.role == .assistant { Spacer(minLength: 42) }
                            }
                            .id(message.id)
                        }
                        if hub.busy {
                            HStack { ProgressView(); Text(hub.status).font(.caption).foregroundStyle(.secondary); Spacer() }.padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: model.chatMessages.count) { _, _ in
                    if let last = model.chatMessages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { item in
                            HStack(spacing: 6) {
                                NavigationLink { NexusV8FileViewer(item: item) } label: { Label(item.name, systemImage: icon(for: item)).lineLimit(1) }
                                Button { attachedIDs.remove(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                            }
                            .font(.caption)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.13), in: Capsule())
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 4)
            }

            if !importError.isEmpty { Text(importError).font(.caption2).foregroundStyle(.red).padding(.horizontal) }

            HStack(alignment: .bottom, spacing: 8) {
                Button { showImporter = true } label: { Image(systemName: "paperclip.circle.fill").font(.title2) }
                TextField("Message NEXUS…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(hub.busy || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty))
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do {
                let imported = try library.importURLs(try result.get())
                attachedIDs.formUnion(imported.map(\.id))
                importError = ""
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func send() {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments
        guard !clean.isEmpty || !files.isEmpty else { return }
        let shown = clean.isEmpty ? "Analyze attached files" : clean
        let userMessage = ChatMessage(role: .user, text: shown, evidence: [])
        model.chatMessages.append(userMessage)
        if !files.isEmpty { attachmentCards[userMessage.id] = files }
        let history = Array(model.chatMessages.dropLast())
        let assistantMessage = ChatMessage(role: .assistant, text: "", evidence: [])
        model.chatMessages.append(assistantMessage)
        let assistantID = assistantMessage.id
        draft = ""
        attachedIDs.removeAll()

        Task {
            let result = await hub.answer(question: clean,
                                          records: model.records,
                                          attachments: files,
                                          history: history,
                                          onPartial: { partial in
                if let index = model.chatMessages.firstIndex(where: { $0.id == assistantID }) {
                    model.chatMessages[index].text = partial
                }
            })
            if let index = model.chatMessages.firstIndex(where: { $0.id == assistantID }) {
                model.chatMessages[index].text = result.text
                model.chatMessages[index].evidence = result.evidence
            }
        }
    }

    private func icon(for item: NexusV8FileItem) -> String {
        switch item.kindLabel {
        case "Image": return "photo"
        case "PDF": return "doc.richtext"
        case "Table": return "tablecells"
        case "Text": return "doc.text"
        default: return "doc"
        }
    }
}
