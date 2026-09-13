import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

struct NexusV8FileItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let typeIdentifier: String
    let size: Int64
    let importedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
    var ext: String { url.pathExtension.lowercased() }

    var kindLabel: String {
        if ["png","jpg","jpeg","heic","heif","webp","gif","bmp","tif","tiff"].contains(ext) { return "Image" }
        if ext == "pdf" { return "PDF" }
        if ["csv","tsv"].contains(ext) { return "Table" }
        if NexusV8FileSupport.textExtensions.contains(ext) { return "Text" }
        return "File"
    }
}

enum NexusV8FileSupport {
    static let textExtensions: Set<String> = [
        "txt","md","markdown","json","jsonl","csv","tsv","html","htm","xml","yaml","yml","toml","ini","log",
        "swift","py","js","ts","tsx","jsx","java","kt","kts","c","h","cpp","hpp","m","mm","css","scss","sql",
        "sh","zsh","fish","rs","go","rb","php","r","dart"
    ]
    static let imageExtensions: Set<String> = ["png","jpg","jpeg","heic","heif","webp","gif","bmp","tif","tiff"]

    static func readableText(_ url: URL, maxBytes: Int = 1_500_000, maxCharacters: Int = 80_000) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        if text.isEmpty {
            throw NSError(domain: "NEXUS.Files", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file does not contain readable text."])
        }
        return String(text.prefix(maxCharacters))
    }

    static func pdfText(_ url: URL, maxPages: Int = 40, maxCharacters: Int = 80_000) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw NSError(domain: "NEXUS.Files", code: 2, userInfo: [NSLocalizedDescriptionKey: "NEXUS could not open this PDF."])
        }
        var text = ""
        for index in 0..<min(pdf.pageCount, maxPages) {
            guard let page = pdf.page(at: index), let pageText = page.string, !pageText.isEmpty else { continue }
            text += "\n--- Page \(index + 1) ---\n\(pageText)"
            if text.count >= maxCharacters { break }
        }
        if text.isEmpty {
            return "PDF with \(pdf.pageCount) page(s). No embedded text was found; a vision model can inspect rendered pages."
        }
        return String(text.prefix(maxCharacters))
    }

    static func metadata(_ item: NexusV8FileItem) -> String {
        let sizeText = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        return "\(item.name) • \(item.kindLabel) • \(sizeText)"
    }
}

@MainActor
final class NexusV8FileLibrary: ObservableObject {
    static let shared = NexusV8FileLibrary()

    @Published private(set) var files: [NexusV8FileItem] = []
    @Published var lastError = ""

    private let defaultsKey = "nexus.v8.file.library.v1"

    private init() {
        load()
    }

    @discardableResult
    func importURLs(_ urls: [URL]) throws -> [NexusV8FileItem] {
        guard !urls.isEmpty else { return [] }
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NEXUS-Files", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        var imported: [NexusV8FileItem] = []
        for source in urls {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            let safeName = source.lastPathComponent.isEmpty ? "file" : source.lastPathComponent
            let destination = base.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: source, to: destination)
                let values = try destination.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                let item = NexusV8FileItem(
                    id: UUID(),
                    name: safeName,
                    path: destination.path,
                    typeIdentifier: values.contentType?.identifier ?? UTType(filenameExtension: destination.pathExtension)?.identifier ?? "public.data",
                    size: Int64(values.fileSize ?? 0),
                    importedAt: Date()
                )
                files.insert(item, at: 0)
                imported.append(item)
            } catch {
                lastError = "Could not import \(safeName): \(error.localizedDescription)"
                throw error
            }
        }
        persist()
        return imported
    }

    func remove(_ item: NexusV8FileItem) {
        try? FileManager.default.removeItem(at: item.url)
        files.removeAll { $0.id == item.id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([NexusV8FileItem].self, from: data) else { return }
        files = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(files) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }
}

struct NexusV8SharedAnswer {
    let text: String
    let evidence: [String]
}

@MainActor
final class NexusV8AIHub: ObservableObject {
    static let shared = NexusV8AIHub()

    @Published var busy = false
    @Published var status = "Shared AI ready"
    @Published var lastError = ""

    private let friendlyStyle = """
    Write like a polished consumer AI assistant: clear, natural, warm but not chatty, and easy to understand. Start with the useful answer instead of implementation details. Use short paragraphs and bullets only when they improve clarity. Avoid developer jargon, model-runtime jargon, raw engine names, and internal scoring unless the user explicitly asks for them. Do not expose hidden reasoning. Be precise about uncertainty and never invent facts.
    """

    func answer(question rawQuestion: String, records: [KnowledgeRecord], attachments: [NexusV8FileItem] = []) async -> NexusV8SharedAnswer {
        let clean = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = clean.isEmpty ? (attachments.isEmpty ? "What stands out in my data?" : "Summarize these files and tell me what matters.") : clean
        busy = true
        lastError = ""
        defer { busy = false }

        if !attachments.isEmpty {
            status = "Reading attached files…"
            let fileResult = await analyzeFiles(attachments, question: question)
            var combined = fileResult.text
            var evidence = fileResult.evidence

            if !records.isEmpty {
                status = "Connecting files with your NEXUS data…"
                let personal = await NexusV7AnswerEngine.answer(question: question, records: records)
                combined += "\n\nPERSONAL NEXUS CONTEXT:\n" + String(personal.answer.prefix(6500))
                evidence.append(contentsOf: personal.evidence.prefix(6))
            }

            let polished = await polish(question: question, content: combined)
            status = "Ready"
            return NexusV8SharedAnswer(text: polished, evidence: Array(Set(evidence)).prefix(14).map { $0 })
        }

        status = "Thinking across your NEXUS data…"
        let result = await NexusV7AnswerEngine.answer(question: question, records: records)
        let polished = await polish(question: question, content: result.answer)
        var evidence = result.evidence
        if !result.disagreements.isEmpty { evidence.append(contentsOf: result.disagreements.prefix(3).map { "Caveat: \($0)" }) }
        status = "Ready"
        return NexusV8SharedAnswer(text: polished, evidence: Array(evidence.prefix(14)))
    }

    func analyzeFiles(_ items: [NexusV8FileItem], question rawQuestion: String) async -> NexusV8SharedAnswer {
        guard !items.isEmpty else { return NexusV8SharedAnswer(text: "Attach at least one file first.", evidence: []) }
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Analyze these files together. Explain the main content, important details, relationships, patterns, and anything uncertain."
            : rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)

        status = "Reading file contents…"
        var evidenceBlocks: [String] = []
        var evidenceLabels: [String] = []

        for item in items {
            do {
                if item.ext == "pdf" {
                    let text = try NexusV8FileSupport.pdfText(item.url, maxPages: 40, maxCharacters: 22_000)
                    evidenceBlocks.append("FILE: \(item.name)\nPDF TEXT:\n\(text)")
                    evidenceLabels.append("Read PDF: \(item.name)")
                } else if NexusV8FileSupport.textExtensions.contains(item.ext) {
                    let text = try NexusV8FileSupport.readableText(item.url, maxBytes: 900_000, maxCharacters: 22_000)
                    evidenceBlocks.append("FILE: \(item.name)\nCONTENT:\n\(text)")
                    evidenceLabels.append("Read \(item.kindLabel.lowercased()): \(item.name)")
                } else {
                    evidenceBlocks.append("FILE: \(NexusV8FileSupport.metadata(item))")
                }
            } catch {
                evidenceBlocks.append("FILE: \(NexusV8FileSupport.metadata(item))\nREAD ERROR: \(error.localizedDescription)")
            }
        }

        let vision = NexusMultimodalStore.shared
        if vision.activePresetID.isEmpty, vision.isDownloaded(vision.selectedPreset), !vision.busy {
            status = "Loading the shared vision model…"
            await vision.load(vision.selectedPreset)
        }

        if !vision.activePresetID.isEmpty && !vision.busy {
            status = "Vision model is inspecting images and page layouts…"
            await vision.analyzeFiles(items.map(\.url), question: question)
            for result in vision.results {
                evidenceBlocks.append("VISION ANALYSIS — \(result.fileName) [\(result.kind)]:\n\(String(result.answer.prefix(6000)))")
                evidenceLabels.append("Vision analysis: \(result.fileName)")
            }
            if !vision.lastError.isEmpty { lastError = vision.lastError }
        } else if items.contains(where: { NexusV8FileSupport.imageExtensions.contains($0.ext) }) {
            evidenceLabels.append("Images attached; load a vision model for visual understanding")
        }

        var joined = evidenceBlocks.joined(separator: "\n\n---\n\n")
        joined = String(joined.prefix(26_000))

        status = "Language models are cross-checking the file evidence…"
        let portable = NexusPortableModelStore.shared
        var modelViews: [String] = []
        let downloadedEnsemble = portable.ensembleModels().filter { portable.isDownloaded($0) }
        for model in downloadedEnsemble.prefix(2) {
            if let opinion = await portable.opinionFromModel(model, question: question, context: joined) {
                modelViews.append("\(model.name): \(String(opinion.finding.prefix(3500)))")
                evidenceLabels.append("Cross-check: \(model.name)")
            }
        }

        let appleView = await NexusIntelligenceEngine.respond(
            question: "Answer the user's question from the supplied file evidence. Be practical and flag missing/uncertain information.",
            context: "QUESTION: \(question)\n\nFILES:\n\(String(joined.prefix(18_000)))"
        )
        if let appleView, !appleView.isEmpty {
            modelViews.append("System intelligence: \(String(appleView.prefix(4500)))")
            evidenceLabels.append("System intelligence cross-check")
        }

        let synthesisInput = """
        USER QUESTION:
        \(question)

        FILE EVIDENCE:
        \(joined)

        OTHER MODEL VIEWS:
        \(modelViews.joined(separator: "\n\n"))
        """

        let final: String
        if !portable.activeModelID.isEmpty,
           let response = await portable.respond(
                "Synthesize the file evidence and other model views into the best final answer for the user. Resolve conflicts conservatively and do not mention internal model orchestration unless asked.\n\n\(String(synthesisInput.prefix(28_000)))",
                systemContext: friendlyStyle
           ), !response.isEmpty {
            final = response
            evidenceLabels.append("Final synthesis: shared local language model")
        } else if let appleView, !appleView.isEmpty {
            final = appleView
        } else if let visionFirst = vision.results.first?.answer, !visionFirst.isEmpty {
            final = vision.results.count == 1 ? visionFirst : vision.results.map { "\($0.fileName):\n\($0.answer)" }.joined(separator: "\n\n")
        } else {
            final = fallbackFileSummary(items: items, evidence: joined, question: question)
        }

        status = "Ready"
        return NexusV8SharedAnswer(text: friendlyCleanup(final), evidence: Array(Set(evidenceLabels)).prefix(14).map { $0 })
    }

    private func polish(question: String, content: String) async -> String {
        let portable = NexusPortableModelStore.shared
        let prompt = """
        Rewrite the draft below as the final answer to the user. Preserve factual meaning and uncertainty, but make it feel like a high-quality ChatGPT/Claude response rather than a diagnostic report. Do not mention internal engines, consensus machinery, or implementation details unless the user asked for them.

        USER QUESTION: \(question)

        DRAFT:
        \(String(content.prefix(10_000)))
        """
        if !portable.activeModelID.isEmpty,
           let response = await portable.respond(prompt, systemContext: friendlyStyle), !response.isEmpty {
            return friendlyCleanup(response)
        }
        if let response = await NexusIntelligenceEngine.respond(question: prompt, context: friendlyStyle), !response.isEmpty {
            return friendlyCleanup(response)
        }
        return friendlyCleanup(content)
    }

    private func friendlyCleanup(_ text: String) -> String {
        text
            .replacingOccurrences(of: "Portable local-model cross-checks:", with: "A few additional observations:")
            .replacingOccurrences(of: "ORIGINAL LOCAL ENSEMBLE:", with: "")
            .replacingOccurrences(of: "ADDITIONAL PORTABLE LOCAL LLM OPINIONS:", with: "Additional observations:")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackFileSummary(items: [NexusV8FileItem], evidence: String, question: String) -> String {
        let names = items.map(\.name).joined(separator: ", ")
        let readable = evidence.split(separator: "\n").prefix(24).joined(separator: "\n")
        return "I imported \(items.count) file\(items.count == 1 ? "" : "s"): \(names). I could read the text/metadata shown below, but no loaded language or vision model was available to produce a deeper synthesis yet.\n\n\(readable)\n\nLoad a shared language model for richer answers, and a vision model when you want NEXUS to understand images or page layouts."
    }
}

extension NexusModel {
    @MainActor
    func askV8(_ raw: String, attachments: [NexusV8FileItem]) async {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty && attachments.isEmpty { return }
        let display = clean.isEmpty ? "Analyze attached files" : clean
        let attachmentLine = attachments.isEmpty ? "" : "\n\n📎 " + attachments.map(\.name).joined(separator: ", ")
        chatMessages.append(ChatMessage(role: .user, text: display + attachmentLine, evidence: []))
        let result = await NexusV8AIHub.shared.answer(question: clean, records: records, attachments: attachments)
        chatMessages.append(ChatMessage(role: .assistant, text: result.text, evidence: result.evidence))
    }
}

struct AskV8View: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var hub = NexusV8AIHub.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var draft = ""
    @State private var attachedIDs: Set<UUID> = []
    @State private var showImporter = false
    @State private var importError = ""

    private var attachments: [NexusV8FileItem] { library.files.filter { attachedIDs.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXUS Chat").font(.headline)
                    Text("Shared AI • your data • files • images • PDFs").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink { FilesV8View() } label: { Image(systemName: "folder") }
                    .accessibilityLabel("Files")
                NavigationLink { PortableModelsV8View() } label: { Image(systemName: "cpu") }
                    .accessibilityLabel("Shared AI models")
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
                                        DisclosureGroup("Sources & notes") {
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
                        if hub.busy {
                            HStack { ProgressView(); Text(hub.status).font(.caption).foregroundStyle(.secondary); Spacer() }.padding()
                        }
                    }.padding()
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
                                NavigationLink { NexusV8FileViewer(item: item) } label: {
                                    Label(item.name, systemImage: icon(for: item)).lineLimit(1)
                                }
                                Button { attachedIDs.remove(item.id) } label: { Image(systemName: "xmark.circle.fill") }
                            }
                            .font(.caption)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.13), in: Capsule())
                        }
                    }.padding(.horizontal)
                }.padding(.top, 6)
            }

            if !importError.isEmpty { Text(importError).font(.caption2).foregroundStyle(.red).padding(.horizontal) }

            HStack(alignment: .bottom, spacing: 8) {
                Button { showImporter = true } label: { Image(systemName: "paperclip.circle.fill").font(.title2) }
                    .accessibilityLabel("Attach files")
                TextField("Message NEXUS…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                Button {
                    let text = draft
                    let files = attachments
                    draft = ""
                    attachedIDs.removeAll()
                    Task { await model.askV8(text, attachments: files) }
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(hub.busy || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty))
            }.padding().background(.ultraThinMaterial)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                let imported = try library.importURLs(urls)
                attachedIDs.formUnion(imported.map(\.id))
                importError = ""
            } catch {
                importError = error.localizedDescription
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

struct FilesV8View: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var hub = NexusV8AIHub.shared
    @ObservedObject private var vision = NexusMultimodalStore.shared
    @ObservedObject private var language = NexusPortableModelStore.shared
    @State private var selectedIDs: Set<UUID> = []
    @State private var question = ""
    @State private var answer = ""
    @State private var evidence: [String] = []
    @State private var showImporter = false
    @State private var importError = ""

    private var selected: [NexusV8FileItem] { library.files.filter { selectedIDs.contains($0.id) } }

    var body: some View {
        List {
            Section {
                Text("Files are copied into NEXUS so they remain readable after the picker closes. Open them directly here, attach them in Chat, or select several for one combined AI analysis.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { showImporter = true } label: { Label("Import files", systemImage: "square.and.arrow.down") }
                if !importError.isEmpty { Text(importError).font(.caption).foregroundStyle(.red) }
            }

            Section("Shared AI") {
                HStack { Label("Language", systemImage: "text.bubble.fill"); Spacer(); Text(language.activeModelID.isEmpty ? "Not loaded" : "Loaded").foregroundStyle(language.activeModelID.isEmpty ? .secondary : .green) }
                HStack { Label("Vision", systemImage: "eye.fill"); Spacer(); Text(vision.activePresetID.isEmpty ? "Not loaded" : "Loaded").foregroundStyle(vision.activePresetID.isEmpty ? .secondary : .green) }
                NavigationLink("Language model manager") { PortableModelsV8View() }
                NavigationLink("Vision model manager") { MultimodalLabV8View() }
                Text("The same loaded models are reused by Chat and file analysis. For images and scanned/page-layout understanding, load a vision model. Text, CSV and embedded PDF text remain readable without one.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Imported files") {
                if library.files.isEmpty {
                    ContentUnavailableView("No files yet", systemImage: "folder", description: Text("Import images, PDFs, CSVs, text/code, or other documents."))
                }
                ForEach(library.files) { item in
                    HStack(spacing: 10) {
                        Button { toggle(item) } label: {
                            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(item.id) ? .cyan : .secondary)
                        }.buttonStyle(.plain)
                        NavigationLink { NexusV8FileViewer(item: item) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).lineLimit(1)
                                Text("\(item.kindLabel) • \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions { Button(role: .destructive) { selectedIDs.remove(item.id); library.remove(item) } label: { Label("Delete", systemImage: "trash") } }
                }
            }

            Section("Analyze together") {
                TextField("Ask about the selected files…", text: $question, axis: .vertical).lineLimit(2...5)
                Button {
                    let items = selected
                    Task {
                        let result = await hub.analyzeFiles(items, question: question)
                        answer = result.text
                        evidence = result.evidence
                    }
                } label: { Label(selected.isEmpty ? "Select files above" : "Analyze \(selected.count) file\(selected.count == 1 ? "" : "s")", systemImage: "sparkles") }
                    .disabled(selected.isEmpty || hub.busy)
                if hub.busy { ProgressView().overlay(alignment: .leading) { Text(hub.status).font(.caption).padding(.leading, 28) } }
            }

            if !answer.isEmpty {
                Section("AI answer") {
                    Text(answer).textSelection(.enabled)
                    if !evidence.isEmpty {
                        DisclosureGroup("What NEXUS used") {
                            ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in Text("• \(item)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Files")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do {
                let imported = try library.importURLs(try result.get())
                selectedIDs.formUnion(imported.map(\.id))
                importError = ""
            } catch { importError = error.localizedDescription }
        }
    }

    private func toggle(_ item: NexusV8FileItem) {
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
    }
}

struct NexusV8FileViewer: View {
    let item: NexusV8FileItem

    var body: some View {
        Group {
            if NexusV8FileSupport.imageExtensions.contains(item.ext) {
                NexusV8ImageViewer(url: item.url)
            } else if item.ext == "pdf" {
                NexusV8PDFViewer(url: item.url)
            } else if ["csv","tsv"].contains(item.ext) {
                NexusV8CSVViewer(url: item.url, delimiter: item.ext == "tsv" ? "\t" : ",")
            } else if NexusV8FileSupport.textExtensions.contains(item.ext) {
                NexusV8TextViewer(url: item.url)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "doc.fill").font(.system(size: 52)).foregroundStyle(.cyan)
                    Text(item.name).font(.headline)
                    Text(NexusV8FileSupport.metadata(item)).font(.caption).foregroundStyle(.secondary)
                    Text("This file is stored inside NEXUS, but this format does not have a dedicated reader yet. NEXUS can still use an iOS-rendered preview in the vision analysis screen when the system supports one.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding()
                }.padding()
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NexusV8ImageViewer: View {
    let url: URL
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().padding()
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
            }
        }.background(Color.black.opacity(0.35))
    }
}

private struct NexusV8PDFViewer: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url { uiView.document = PDFDocument(url: url) }
    }
}

private struct NexusV8TextViewer: View {
    let url: URL
    @State private var text = "Loading…"
    @State private var error = ""

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(error.isEmpty ? text : error)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .task {
            do { text = try NexusV8FileSupport.readableText(url) }
            catch { error = error.localizedDescription }
        }
    }
}

private struct NexusV8CSVViewer: View {
    let url: URL
    let delimiter: Character
    @State private var rows: [[String]] = []
    @State private var error = ""

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            if !error.isEmpty {
                Text(error).foregroundStyle(.red).padding()
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(rowIndex == 0 ? .caption.bold() : .caption)
                                    .textSelection(.enabled)
                                    .padding(7)
                                    .frame(width: 170, alignment: .leading)
                                    .background(rowIndex == 0 ? Color.cyan.opacity(0.14) : Color.clear)
                                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                            }
                        }
                    }
                }.padding()
            }
        }
        .task {
            do {
                let text = try NexusV8FileSupport.readableText(url, maxBytes: 1_500_000, maxCharacters: 180_000)
                rows = text.split(whereSeparator: \.isNewline).prefix(1000).map { parseCSVLine(String($0), delimiter: delimiter) }
            } catch { error = error.localizedDescription }
        }
    }

    private func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" {
                let next = line.index(after: index)
                if quoted, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if ch == delimiter && !quoted {
                cells.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            index = line.index(after: index)
        }
        cells.append(current)
        return cells
    }
}

extension NexusPortableModelStore {
    static let v8Qwen4B = NexusPortableModel(
        id: "v8-qwen3-4b-q4",
        name: "Qwen3 4B Q4_K_M",
        path: "hf://Qwen/Qwen3-4B-GGUF/Qwen3-4B-Q4_K_M.gguf",
        source: "Official Qwen GGUF • verified V8 source",
        approximateSize: "~2.50 GB",
        enabledForEnsemble: false
    )

    static let v8Qwen8B = NexusPortableModel(
        id: "v8-qwen3-8b-q4",
        name: "Qwen3 8B Q4_K_M",
        path: "hf://Qwen/Qwen3-8B-GGUF/Qwen3-8B-Q4_K_M.gguf",
        source: "Official Qwen GGUF • verified V8 source",
        approximateSize: "~5.03 GB",
        enabledForEnsemble: false
    )

    static var v8VerifiedPresets: [NexusPortableModel] {
        [smolTinyPreset, qwenTinyPreset, qwenBalancedPreset, v8Qwen4B, v8Qwen8B]
    }
}

struct PortableModelsV8View: View {
    @ObservedObject private var store = NexusPortableModelStore.shared
    @State private var picker = false

    var body: some View {
        List {
            Section {
                Text("These language models are shared by Chat, file analysis and the rest of NEXUS. Download once, then load the model you want to keep active.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(store.memorySummary).font(.caption2).foregroundStyle(.secondary)
                if store.busy || store.progress > 0 {
                    ProgressView(value: store.progress) { Text(store.status).font(.caption) }
                    if store.downloadSnapshot.totalBytes > 0 { Text(store.downloadSnapshot.detailText).font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
                } else { Text(store.status).font(.caption).foregroundStyle(.secondary) }
                if !store.lastError.isEmpty { Text(store.lastError).font(.caption).foregroundStyle(.red) }
            }

            Section("Verified presets") {
                ForEach(NexusPortableModelStore.v8VerifiedPresets) { preset in presetRow(preset) }
            }

            Section("Your models") {
                Button { picker = true } label: { Label("Import GGUF from Files", systemImage: "square.and.arrow.down") }
                ForEach(store.models) { model in modelRow(model) }
            }

            Section("About downloads") {
                Text("V8 uses current verified model locations for the large Qwen presets. Downloads remain resumable, use parallel byte ranges when supported, and fall back to the runtime downloader when the server does not support ranged transfers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Shared AI Models")
        .sheet(isPresented: $picker) { NexusGGUFDocumentPicker { url in picker = false; Task { await store.importGGUF(url) } } }
        .task {
            for oldID in ["qwen3-4b-q4", "qwen3-8b-q4"] {
                if let old = store.models.first(where: { $0.id == oldID }), !store.isDownloaded(old) { store.delete(old) }
            }
        }
    }

    @ViewBuilder private func presetRow(_ preset: NexusPortableModel) -> some View {
        let existing = store.models.first(where: { $0.id == preset.id })
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).font(.headline)
                    Text("\(preset.approximateSize) • \(preset.source)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let model = existing, store.activeModelID == model.id { Label("Loaded", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
            }
            if let model = existing {
                HStack {
                    if !store.isDownloaded(model) { Button("Download") { Task { await store.download(model) } }.buttonStyle(.bordered).disabled(store.busy) }
                    Button(store.activeModelID == model.id ? "Reload" : "Load") { Task { await store.load(model) } }.buttonStyle(.borderedProminent).disabled(store.busy)
                    Button(model.enabledForEnsemble ? "In ensemble" : "Use for cross-checks") { store.toggleEnsemble(model) }.buttonStyle(.bordered)
                }
            } else {
                Button("Add model") { store.addPreset(preset) }.buttonStyle(.bordered)
            }
        }.padding(.vertical, 3)
    }

    @ViewBuilder private func modelRow(_ model: NexusPortableModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.headline)
                    Text("\(model.approximateSize) • \(model.source)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.activeModelID == model.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else if store.isDownloaded(model) { Image(systemName: "internaldrive.fill").foregroundStyle(.secondary) }
            }
            HStack {
                if model.isPreset && !store.isDownloaded(model) { Button("Download") { Task { await store.download(model) } }.buttonStyle(.bordered).disabled(store.busy) }
                Button(store.activeModelID == model.id ? "Reload" : "Load") { Task { await store.load(model) } }.buttonStyle(.borderedProminent).disabled(store.busy)
                Button(model.enabledForEnsemble ? "Cross-check on" : "Cross-check off") { store.toggleEnsemble(model) }.buttonStyle(.bordered)
            }
        }.padding(.vertical, 3)
    }
}
