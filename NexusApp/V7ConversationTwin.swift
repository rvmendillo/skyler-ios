import Foundation
import SwiftUI

struct NexusConversationVoice: Identifiable, Hashable {
    let id: String
    let displayName: String
    let messageCount: Int
    let averageCharacters: Int
    let averageWords: Int
    let questionRate: Double
    let exclamationRate: Double
    let emojiRate: Double
    let lowercaseStartRate: Double
    let shortReplyRate: Double
    let commonOpeners: [String]
    let commonClosers: [String]
    let frequentWords: [String]
    let punctuationProfile: String
    let confidence: Double

    var styleSummary: String {
        var parts: [String] = []
        parts.append("Usually about \(averageWords) words / \(averageCharacters) characters per captured message")
        if shortReplyRate >= 0.45 { parts.append("often uses short replies") }
        if questionRate >= 0.20 { parts.append("frequently asks questions") }
        if exclamationRate >= 0.15 { parts.append("uses emphatic punctuation relatively often") }
        if emojiRate >= 0.12 { parts.append("uses emoji in a noticeable share of messages") }
        if lowercaseStartRate >= 0.55 { parts.append("often begins messages in lowercase") }
        return parts.joined(separator: "; ") + "."
    }
}

enum NexusConversationTwinEngine {
    private static let stopWords: Set<String> = [
        "the","and","that","this","with","from","have","your","you","for","are","was","were","not","but","about","what","when","where","which","would","could","should","just","also","very","then","than","there","they","them","their","our","ours","his","her","hers","him","she","who","how","why","into","been","being","will","can","cant","dont","does","did","its","im","ive","ill","youre","youve","youll"
    ]

    static func availableVoices(records: [KnowledgeRecord]) -> [NexusConversationVoice] {
        let messages = records.filter { $0.kind == .message && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let groups = Dictionary(grouping: messages) { normalizedSpeaker($0) }
        return groups.compactMap { name, records -> NexusConversationVoice? in
            guard !name.isEmpty, records.count >= 3 else { return nil }
            return profile(name: name, messages: records)
        }.sorted {
            if $0.messageCount == $1.messageCount { return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return $0.messageCount > $1.messageCount
        }
    }

    static func messages(for voice: NexusConversationVoice, records: [KnowledgeRecord]) -> [KnowledgeRecord] {
        records.filter { $0.kind == .message && normalizedSpeaker($0).caseInsensitiveCompare(voice.displayName) == .orderedSame }
    }

    static func reply(prompt: String, voice: NexusConversationVoice, records: [KnowledgeRecord]) async -> String {
        let speakerMessages = messages(for: voice, records: records)
        let relevant = relevantContext(prompt: prompt, records: records)
        let style = stylePrompt(voice)
        let context = """
        SIMULATED VOICE: \(voice.displayName)
        STYLE PROFILE (derived statistically from \(voice.messageCount) captured messages):
        \(style)

        NEXUS FACTUAL CONTEXT:
        \(relevant.joined(separator: "\n"))

        IMPORTANT:
        - This is a simulation based on observed conversational patterns, not the actual person.
        - Do not claim memories, intentions, emotions, opinions or events that are not in the supplied context.
        - Do not reproduce memorized messages verbatim. Generate a fresh reply using the statistical style profile.
        - If factual context is missing, answer naturally but state uncertainty rather than inventing personal facts.
        """

        if let generated = await NexusIntelligenceEngine.respond(
            question: "Reply to this message in the simulated conversational style described above: \(prompt)",
            context: context
        ), !generated.isEmpty {
            return generated
        }

        return deterministicFallback(prompt: prompt, voice: voice, speakerMessages: speakerMessages)
    }

    private static func normalizedSpeaker(_ record: KnowledgeRecord) -> String {
        for key in ["sender_name", "sender", "author", "participant", "username", "speaker"] {
            if let value = record.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return record.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func profile(name: String, messages: [KnowledgeRecord]) -> NexusConversationVoice {
        let sample = Array(messages.prefix(8_000))
        var charTotal = 0
        var wordTotal = 0
        var questions = 0
        var exclaims = 0
        var emojis = 0
        var lowercaseStarts = 0
        var shortReplies = 0
        var wordCounts: [String:Int] = [:]
        var openerCounts: [String:Int] = [:]
        var closerCounts: [String:Int] = [:]
        var punctuation: [Character:Int] = ["?":0,"!":0,".":0,",":0]

        for record in sample {
            let text = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            charTotal += text.count
            let words = text.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
            wordTotal += words.count
            if text.contains("?") { questions += 1 }
            if text.contains("!") { exclaims += 1 }
            if text.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { emojis += 1 }
            if let first = text.first, first.isLetter, first.isLowercase { lowercaseStarts += 1 }
            if words.count <= 5 { shortReplies += 1 }
            for c in text where punctuation[c] != nil { punctuation[c, default: 0] += 1 }

            let normalized = words.map { $0.lowercased() }.filter { $0.count >= 2 && !stopWords.contains($0) }
            for word in normalized { wordCounts[word, default: 0] += 1 }
            if let first = normalized.first { openerCounts[first, default: 0] += 1 }
            if let last = normalized.last { closerCounts[last, default: 0] += 1 }
        }

        let n = max(sample.count, 1)
        let commonOpeners = openerCounts.sorted { $0.value > $1.value }.prefix(6).map(\.key)
        let commonClosers = closerCounts.sorted { $0.value > $1.value }.prefix(6).map(\.key)
        let frequent = wordCounts.sorted { a, b in a.value == b.value ? a.key < b.key : a.value > b.value }.prefix(18).map(\.key)
        let punctuationProfile = punctuation.sorted { $0.value > $1.value }.map { "\($0.key): \($0.value)" }.joined(separator: " • ")
        let confidence = min(0.96, 0.22 + min(0.50, log10(Double(n) + 1) * 0.20) + min(0.24, Double(wordTotal) / 20_000.0))

        return NexusConversationVoice(
            id: name.lowercased(),
            displayName: name,
            messageCount: messages.count,
            averageCharacters: charTotal / n,
            averageWords: wordTotal / n,
            questionRate: Double(questions) / Double(n),
            exclamationRate: Double(exclaims) / Double(n),
            emojiRate: Double(emojis) / Double(n),
            lowercaseStartRate: Double(lowercaseStarts) / Double(n),
            shortReplyRate: Double(shortReplies) / Double(n),
            commonOpeners: commonOpeners,
            commonClosers: commonClosers,
            frequentWords: frequent,
            punctuationProfile: punctuationProfile,
            confidence: confidence
        )
    }

    private static func stylePrompt(_ voice: NexusConversationVoice) -> String {
        """
        Average message length: \(voice.averageWords) words, \(voice.averageCharacters) characters.
        Short-reply rate: \(Int(voice.shortReplyRate * 100))%.
        Question rate: \(Int(voice.questionRate * 100))%.
        Exclamation rate: \(Int(voice.exclamationRate * 100))%.
        Emoji rate: \(Int(voice.emojiRate * 100))%.
        Lowercase-start rate: \(Int(voice.lowercaseStartRate * 100))%.
        Common opening vocabulary: \(voice.commonOpeners.joined(separator: ", ")).
        Common closing vocabulary: \(voice.commonClosers.joined(separator: ", ")).
        Frequent non-stop words: \(voice.frequentWords.joined(separator: ", ")).
        Punctuation distribution: \(voice.punctuationProfile).
        Match the cadence and level of formality, but do not copy old sentences.
        """
    }

    private static func relevantContext(prompt: String, records: [KnowledgeRecord]) -> [String] {
        let terms = Set(prompt.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
        let ranked = records.prefix(30_000).compactMap { r -> (String,Int)? in
            let hay = (r.title + " " + r.text + " " + r.source).lowercased()
            let score = terms.reduce(0) { $0 + (hay.contains($1) ? 1 : 0) }
            guard score > 0 else { return nil }
            let body = r.text.isEmpty ? r.title : r.text
            return ("\(r.source) • \(r.kind.rawValue): \(String(body.prefix(220)))", score)
        }.sorted { $0.1 > $1.1 }
        return ranked.prefix(12).map(\.0)
    }

    private static func deterministicFallback(prompt: String, voice: NexusConversationVoice, speakerMessages: [KnowledgeRecord]) -> String {
        let lower = prompt.lowercased()
        let opener = voice.commonOpeners.first ?? "yeah"
        if lower.contains("?") {
            if voice.averageWords <= 8 { return "\(opener), maybe. i’d need a bit more context though." }
            return "\(opener), i think it depends on the context. i’d want to know a little more before being certain."
        }
        if voice.averageWords <= 6 { return "\(opener), got it." }
        return "\(opener), i get what you mean. that makes sense from what you said."
    }
}

@MainActor
final class NexusConversationTwinSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var busy = false

    func reset(voice: NexusConversationVoice?) {
        messages.removeAll()
        if let voice {
            messages.append(.init(role: .assistant, text: "Conversation Twin ready for \(voice.displayName). This is a simulated style model based on \(voice.messageCount) imported messages—not the actual person.", evidence: []))
        }
    }

    func send(_ text: String, voice: NexusConversationVoice, records: [KnowledgeRecord]) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !busy else { return }
        messages.append(.init(role: .user, text: clean, evidence: []))
        busy = true
        let response = await NexusConversationTwinEngine.reply(prompt: clean, voice: voice, records: records)
        messages.append(.init(role: .assistant, text: response, evidence: ["Style simulation: \(voice.displayName)", "Training evidence: \(voice.messageCount) captured messages", "Style confidence: \(Int(voice.confidence * 100))%"] ))
        busy = false
    }
}

struct ConversationTwinV7View: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var session = NexusConversationTwinSession()
    @State private var selectedID = ""
    @State private var draft = ""

    var body: some View {
        let voices = NexusConversationTwinEngine.availableVoices(records: model.records)
        let selected = voices.first(where: { $0.id == selectedID }) ?? voices.first

        VStack(spacing: 0) {
            if voices.isEmpty {
                ContentUnavailableView(
                    "No conversation voice yet",
                    systemImage: "person.wave.2.fill",
                    description: Text("Import Messenger/Instagram/Chat JSON with speaker names. NEXUS needs at least three messages from a participant before it creates a style profile.")
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Conversation Twin", systemImage: "person.2.wave.2.fill").font(.headline)
                        Spacer()
                        Text("SIMULATION").font(.caption2.bold()).foregroundStyle(.orange)
                    }
                    Picker("Voice", selection: $selectedID) {
                        ForEach(voices) { voice in Text("\(voice.displayName) • \(voice.messageCount)").tag(voice.id) }
                    }
                    .pickerStyle(.menu)
                    if let selected {
                        Text(selected.styleSummary).font(.caption).foregroundStyle(.secondary)
                        HStack { Text("Style confidence"); Spacer(); Text("\(Int(selected.confidence*100))%") }.font(.caption2)
                        ProgressView(value: selected.confidence)
                    }
                }
                .padding()
                .background(.thinMaterial)
                .onAppear {
                    if selectedID.isEmpty, let first = voices.first { selectedID = first.id; session.reset(voice: first) }
                }
                .onChange(of: selectedID) { _, newValue in
                    session.reset(voice: voices.first(where: { $0.id == newValue }))
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(session.messages) { message in
                                HStack {
                                    if message.role == .user { Spacer(minLength: 42) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.text)
                                        if !message.evidence.isEmpty {
                                            Text(message.evidence.joined(separator: " • ")).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(11)
                                    .background(message.role == .user ? Color.cyan.opacity(0.22) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                                    if message.role == .assistant { Spacer(minLength: 42) }
                                }.id(message.id)
                            }
                            if session.busy { ProgressView("Generating locally…").padding() }
                        }.padding()
                    }
                    .onChange(of: session.messages.count) { _, _ in if let last = session.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message the simulation…", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...5)
                    Button {
                        guard let selected else { return }
                        let send = draft; draft = ""
                        Task { await session.send(send, voice: selected, records: model.records) }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(session.busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding()
            }
        }
        .navigationTitle("Conversation Twin")
        .navigationBarTitleDisplayMode(.inline)
    }
}
