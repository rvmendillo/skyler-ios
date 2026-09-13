import Foundation
import SwiftUI
import Vision
import PDFKit
import UIKit
import UniformTypeIdentifiers

struct NexusV9FileEvidence: Identifiable, Hashable {
    let id = UUID()
    let citation: NexusV9Citation
    let text: String
}

enum NexusV9DocumentEngine {
    static func evidence(for item: NexusV8FileItem, maxUnits: Int = 80) async -> [NexusV9FileEvidence] {
        if item.ext == "pdf" { return pdfEvidence(item, maxPages: maxUnits) }
        if ["csv","tsv"].contains(item.ext) { return csvEvidence(item, maxRows: maxUnits) }
        if NexusV8FileSupport.imageExtensions.contains(item.ext) { return await imageEvidence(item) }
        if NexusV8FileSupport.textExtensions.contains(item.ext) { return textEvidence(item, maxChunks: maxUnits) }
        return [NexusV9FileEvidence(citation: NexusV9Citation(kind: .file, sourceID: item.id.uuidString, sourceName: item.name, location: item.kindLabel, excerpt: NexusV8FileSupport.metadata(item), filePath: item.path), text: NexusV8FileSupport.metadata(item))]
    }

    static func pdfEvidence(_ item: NexusV8FileItem, maxPages: Int) -> [NexusV9FileEvidence] {
        guard let pdf = PDFDocument(url: item.url) else { return [] }
        var out: [NexusV9FileEvidence] = []
        for index in 0..<min(pdf.pageCount, maxPages) {
            guard let text = pdf.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            let page = index + 1
            let excerpt = String(text.prefix(700))
            let citation = NexusV9Citation(kind: .pdfPage, sourceID: item.id.uuidString, sourceName: item.name, location: "Page \(page)", excerpt: excerpt, filePath: item.path)
            out.append(NexusV9FileEvidence(citation: citation, text: String(text.prefix(6_000))))
        }
        return out
    }

    static func textEvidence(_ item: NexusV8FileItem, maxChunks: Int) -> [NexusV9FileEvidence] {
        guard let text = try? NexusV8FileSupport.readableText(item.url, maxBytes: 2_000_000, maxCharacters: 160_000) else { return [] }
        let size = 2_500
        var out: [NexusV9FileEvidence] = []
        var start = text.startIndex
        var number = 1
        while start < text.endIndex && number <= maxChunks {
            let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[start..<end])
            let citation = NexusV9Citation(kind: item.ext.contains("swift") || ["py","js","ts","java","kt","c","cpp","go","rs"].contains(item.ext) ? .code : .file, sourceID: item.id.uuidString, sourceName: item.name, location: "Text chunk \(number)", excerpt: String(chunk.prefix(700)), filePath: item.path)
            out.append(NexusV9FileEvidence(citation: citation, text: chunk))
            start = end; number += 1
        }
        return out
    }

    static func csvEvidence(_ item: NexusV8FileItem, maxRows: Int) -> [NexusV9FileEvidence] {
        guard let raw = try? NexusV8FileSupport.readableText(item.url, maxBytes: 3_000_000, maxCharacters: 220_000) else { return [] }
        let delimiter: Character = item.ext == "tsv" ? "\t" : ","
        let lines = raw.split(whereSeparator: \.isNewline)
        guard let first = lines.first else { return [] }
        let headers = parseDelimited(String(first), delimiter: delimiter)
        return lines.dropFirst().prefix(maxRows).enumerated().map { offset, line in
            let values = parseDelimited(String(line), delimiter: delimiter)
            let fields = zip(headers, values).map { "\($0.0): \($0.1)" }.joined(separator: " • ")
            let row = offset + 2
            let citation = NexusV9Citation(kind: .csvRow, sourceID: item.id.uuidString, sourceName: item.name, location: "Row \(row)", excerpt: String(fields.prefix(700)), filePath: item.path)
            return NexusV9FileEvidence(citation: citation, text: fields)
        }
    }

    static func imageEvidence(_ item: NexusV8FileItem) async -> [NexusV9FileEvidence] {
        guard let image = UIImage(contentsOfFile: item.path), let cg = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { return [] }
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let summary = text.isEmpty ? "Image \(item.name); OCR found no readable text." : text
            let citation = NexusV9Citation(kind: .imageOCR, sourceID: item.id.uuidString, sourceName: item.name, location: "Recognized image text", excerpt: String(summary.prefix(700)), filePath: item.path)
            return [NexusV9FileEvidence(citation: citation, text: String(summary.prefix(15_000)))]
        }.value
    }

    static func parseDelimited(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = []; var current = ""; var quoted = false
        var iterator = line.makeIterator()
        while let char = iterator.next() {
            if char == "\"" { quoted.toggle(); continue }
            if char == delimiter && !quoted { result.append(current); current = "" }
            else { current.append(char) }
        }
        result.append(current)
        return result
    }
}

struct NexusV9ColumnSummary: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let nonEmpty: Int
    let numericCount: Int
    let min: Double?
    let max: Double?
    let average: Double?
    let uniqueCount: Int
}

struct NexusV9TableReport: Hashable {
    let rows: Int
    let columns: Int
    let summaries: [NexusV9ColumnSummary]
    let anomalies: [String]
}

enum NexusV9TableEngine {
    static func inspect(_ item: NexusV8FileItem) -> NexusV9TableReport? {
        guard ["csv","tsv"].contains(item.ext), let raw = try? NexusV8FileSupport.readableText(item.url, maxBytes: 4_000_000, maxCharacters: 400_000) else { return nil }
        let delimiter: Character = item.ext == "tsv" ? "\t" : ","
        let lines = raw.split(whereSeparator: \.isNewline).prefix(3_000)
        guard let first = lines.first else { return nil }
        let headers = NexusV9DocumentEngine.parseDelimited(String(first), delimiter: delimiter)
        let rows = lines.dropFirst().map { NexusV9DocumentEngine.parseDelimited(String($0), delimiter: delimiter) }
        var summaries: [NexusV9ColumnSummary] = []
        var anomalies: [String] = []
        for c in headers.indices {
            let values = rows.compactMap { c < $0.count ? $0[c].trimmingCharacters(in: .whitespacesAndNewlines) : nil }.filter { !$0.isEmpty }
            let numbers = values.compactMap(Double.init)
            let minV = numbers.min(); let maxV = numbers.max(); let avg = numbers.isEmpty ? nil : numbers.reduce(0,+) / Double(numbers.count)
            summaries.append(NexusV9ColumnSummary(name: headers[c].isEmpty ? "Column \(c+1)" : headers[c], nonEmpty: values.count, numericCount: numbers.count, min: minV, max: maxV, average: avg, uniqueCount: Set(values).count))
            if values.count < rows.count / 2 { anomalies.append("\(headers[c]) is missing in more than half of sampled rows.") }
            if let minV, let maxV, maxV > 0, abs(maxV - minV) > max(abs(avg ?? 0), 1) * 100 { anomalies.append("\(headers[c]) has a very wide numeric range; check for outliers or mixed units.") }
        }
        let widths = rows.map(\.count)
        if Set(widths).count > 1 { anomalies.append("Rows have inconsistent column counts; quoted delimiters or malformed rows may be present.") }
        return NexusV9TableReport(rows: rows.count, columns: headers.count, summaries: summaries, anomalies: anomalies)
    }
}

struct NexusV9CodeSymbol: Identifiable, Hashable {
    let id = UUID(); let kind: String; let name: String; let line: Int; let signature: String
}

enum NexusV9CodeEngine {
    static func symbols(_ item: NexusV8FileItem) -> [NexusV9CodeSymbol] {
        guard let text = try? NexusV8FileSupport.readableText(item.url, maxBytes: 2_000_000, maxCharacters: 250_000) else { return [] }
        let lines = text.components(separatedBy: .newlines)
        var out: [NexusV9CodeSymbol] = []
        let patterns: [(String,String)] = [
            ("function", #"\b(func|function|def)\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            ("type", #"\b(class|struct|enum|protocol|interface)\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            ("property", #"\b(let|var|const)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        ]
        for (offset,line) in lines.enumerated() {
            for (kind, pattern) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let ns = line as NSString; let range = NSRange(location: 0, length: ns.length)
                if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 3 {
                    let name = ns.substring(with: match.range(at: 2))
                    out.append(NexusV9CodeSymbol(kind: kind, name: name, line: offset + 1, signature: String(line.trimmingCharacters(in: .whitespaces).prefix(180))))
                }
            }
        }
        return Array(out.prefix(500))
    }
}

struct NexusV9ComparisonResult: Hashable {
    let similarity: Double
    let onlyLeft: [String]
    let onlyRight: [String]
    let contradictions: [String]
}

enum NexusV9CompareEngine {
    static func compare(_ left: NexusV8FileItem, _ right: NexusV8FileItem) -> NexusV9ComparisonResult {
        let a = text(left); let b = text(right)
        let aLines = Set(a.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let bLines = Set(b.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let union = aLines.union(bLines).count
        let similarity = union == 0 ? 1 : Double(aLines.intersection(bLines).count) / Double(union)
        let onlyA = Array(aLines.subtracting(bLines).prefix(30)); let onlyB = Array(bLines.subtracting(aLines).prefix(30))
        var contradictions: [String] = []
        let negators = [" not ", "never", "false", "disabled", "no "]
        for l in onlyA.prefix(80) {
            let words = Set(l.lowercased().split(separator: " ").filter { $0.count > 4 })
            for r in onlyB.prefix(80) {
                let rw = Set(r.lowercased().split(separator: " ").filter { $0.count > 4 })
                if words.intersection(rw).count >= 3 && negators.contains(where: { l.lowercased().contains($0) != r.lowercased().contains($0) }) {
                    contradictions.append("Possible conflict: “\(String(l.prefix(130)))” ↔ “\(String(r.prefix(130)))”")
                }
                if contradictions.count >= 10 { break }
            }
        }
        return NexusV9ComparisonResult(similarity: similarity, onlyLeft: onlyA, onlyRight: onlyB, contradictions: contradictions)
    }

    static func text(_ item: NexusV8FileItem) -> String {
        if item.ext == "pdf" { return (try? NexusV8FileSupport.pdfText(item.url, maxPages: 50, maxCharacters: 120_000)) ?? "" }
        return (try? NexusV8FileSupport.readableText(item.url, maxBytes: 2_000_000, maxCharacters: 120_000)) ?? ""
    }
}

enum NexusV9QuestionSuggestions {
    static func forFile(_ item: NexusV8FileItem) -> [String] {
        if ["csv","tsv"].contains(item.ext) { return ["What trends stand out?", "Find anomalies and missing data", "Summarize every column", "What charts would be most useful?"] }
        if item.ext == "pdf" { return ["Give me the executive summary", "What are the strongest claims and evidence?", "Find contradictions or caveats", "What important questions does this leave unanswered?"] }
        if NexusV8FileSupport.imageExtensions.contains(item.ext) { return ["Describe everything important in this image", "Read and explain visible text", "Analyze the layout, chart or diagram", "What might be easy to miss?"] }
        if ["swift","py","js","ts","java","kt","c","cpp","go","rs"].contains(item.ext) { return ["Explain this codebase simply", "Find likely bugs", "Map the main symbols and dependencies", "Suggest safe refactors"] }
        return ["Summarize this file", "What matters most?", "Find contradictions", "What information is missing?"]
    }
}

struct NexusV9GlobalSearchView: View {
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var query = ""
    @State private var hits: [NexusV9SearchHit] = []

    var body: some View {
        List {
            Section {
                TextField("Search everything in NEXUS", text: $query)
                    .textInputAutocapitalization(.never)
                    .onSubmit { hits = intelligence.search(query, limit: 30) }
                Button { hits = intelligence.search(query, limit: 30) } label: { Label("Hybrid Search", systemImage: "magnifyingglass.circle.fill") }
                Text("Semantic vectors + keyword matching + recency + learned relevance. Searches indexed files, records and derived memory without putting the whole vault into model context.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Results") {
                ForEach(hits) { hit in
                    if let path = hit.chunk.filePath, let file = library.files.first(where: { $0.path == path }) {
                        NavigationLink { NexusV9FileIntelligenceView(item: file) } label: { hitRow(hit) }
                    } else { hitRow(hit) }
                }
            }
        }
        .navigationTitle("Universal Search")
    }

    private func hitRow(_ hit: NexusV9SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(hit.chunk.title).font(.headline); Spacer(); Text(String(format: "%.0f%%", hit.score * 100)).font(.caption.monospacedDigit()).foregroundStyle(.cyan) }
            Text(hit.chunk.sourceName + " • " + hit.chunk.location).font(.caption).foregroundStyle(.secondary)
            Text(hit.chunk.text).font(.caption).lineLimit(4)
            Button("Mark useful") { intelligence.markUseful(hit.chunk.id) }.buttonStyle(.borderless).font(.caption)
        }.padding(.vertical, 3)
    }
}

struct NexusV9FileIntelligenceView: View {
    @EnvironmentObject var model: NexusModel
    let item: NexusV8FileItem
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @State private var question = ""
    @State private var answer = ""
    @State private var citations: [NexusV9Citation] = []
    @State private var busy = false
    @State private var selection = ""

    var body: some View {
        List {
            Section("View") { NexusV8FileViewer(item: item).frame(minHeight: 360).listRowInsets(EdgeInsets()) }
            Section("Ask this file") {
                TextField("Ask anything about this file", text: $question, axis: .vertical)
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(NexusV9QuestionSuggestions.forFile(item), id: \.self) { suggestion in Button(suggestion) { question = suggestion; ask() }.buttonStyle(.bordered) } } }
                Button { ask() } label: { Label(busy ? "Analyzing…" : "Ask", systemImage: "sparkles") }.disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !answer.isEmpty { Text(answer).textSelection(.enabled) }
            }
            Section("Ask selected content") {
                TextEditor(text: $selection).frame(minHeight: 90)
                Text("Paste or copy a passage/row/code region here. NEXUS sends only this selection when you want a tightly scoped answer.").font(.caption).foregroundStyle(.secondary)
                Button("Ask about selection") { let s = selection; guard !s.isEmpty else { return }; question = "Explain or analyze this selected content:\n\n\(s)"; ask(useAttachment: false) }
            }
            if !citations.isEmpty {
                Section("Tap-to-source evidence") { ForEach(citations) { citation in NavigationLink { NexusV9CitationSourceView(citation: citation) } label: { VStack(alignment: .leading) { Text(citation.sourceName).font(.headline); Text(citation.location).font(.caption).foregroundStyle(.cyan); Text(citation.excerpt).font(.caption).lineLimit(3) } } } }
            }
            Section("Context tray") { Button { intelligence.addToTray(kind: .file, referenceID: item.id.uuidString, label: item.name, preview: NexusV8FileSupport.metadata(item)) } label: { Label("Add file to context tray", systemImage: "tray.and.arrow.down.fill") } }
            if ["csv","tsv"].contains(item.ext) { Section("Table intelligence") { NavigationLink("Open table analysis") { NexusV9TableIntelligenceView(item: item) } } }
            if ["swift","py","js","ts","java","kt","c","cpp","go","rs"].contains(item.ext) { Section("Code intelligence") { NavigationLink("Open code workspace") { NexusV9CodeWorkspaceView(item: item) } } }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask(useAttachment: Bool = true) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines); guard !q.isEmpty else { return }
        busy = true
        Task {
            let evidence = await NexusV9DocumentEngine.evidence(for: item, maxUnits: 50)
            await MainActor.run { citations = Array(evidence.map(\.citation).prefix(12)) }
            let result = await NexusV9Assistant.shared.answer(question: q, records: model.records, attachments: useAttachment ? [item] : [], extraContext: useAttachment ? evidence.prefix(20).map { "[\($0.citation.location)]\n\($0.text)" }.joined(separator: "\n\n") : selection)
            await MainActor.run { answer = result.text; busy = false }
        }
    }
}

struct NexusV9CitationSourceView: View {
    let citation: NexusV9Citation
    @ObservedObject private var library = NexusV8FileLibrary.shared
    var body: some View {
        Group {
            if let path = citation.filePath, let item = library.files.first(where: { $0.path == path }) {
                if item.ext == "pdf", let page = pageNumber(citation.location) { NexusV9PDFPageView(url: item.url, page: page) }
                else { NexusV8FileViewer(item: item) }
            } else { ScrollView { Text(citation.excerpt).textSelection(.enabled).padding() } }
        }
        .navigationTitle(citation.location.isEmpty ? citation.sourceName : citation.location)
        .navigationBarTitleDisplayMode(.inline)
    }
    private func pageNumber(_ text: String) -> Int? { Int(text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) }
}

struct NexusV9PDFPageView: UIViewRepresentable {
    let url: URL; let page: Int
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical; return view }
    func updateUIView(_ view: PDFView, context: Context) { if view.document?.documentURL != url { view.document = PDFDocument(url: url) }; if let target = view.document?.page(at: max(0, page - 1)) { view.go(to: target) } }
}

struct NexusV9TableIntelligenceView: View {
    let item: NexusV8FileItem
    private var report: NexusV9TableReport? { NexusV9TableEngine.inspect(item) }
    var body: some View {
        List {
            if let report {
                Section { Text("\(report.rows) sampled rows • \(report.columns) columns") }
                Section("Columns") { ForEach(report.summaries) { s in VStack(alignment: .leading, spacing: 3) { Text(s.name).font(.headline); Text("\(s.nonEmpty) values • \(s.uniqueCount) unique • \(s.numericCount) numeric").font(.caption); if let avg = s.average { Text("min \(s.min ?? 0, format: .number) • avg \(avg, format: .number) • max \(s.max ?? 0, format: .number)").font(.caption).foregroundStyle(.secondary) } } } }
                Section("Anomalies") { if report.anomalies.isEmpty { Text("No simple structural anomalies found.") } else { ForEach(report.anomalies, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") } } }
                Section("Viewer") { NexusV8CSVViewer(url: item.url).frame(minHeight: 380).listRowInsets(EdgeInsets()) }
            } else { Text("This table could not be parsed.") }
        }.navigationTitle("Table Intelligence")
    }
}

struct NexusV9CodeWorkspaceView: View {
    let item: NexusV8FileItem
    private var symbols: [NexusV9CodeSymbol] { NexusV9CodeEngine.symbols(item) }
    var body: some View {
        List {
            Section("Source") { NexusV8TextViewer(url: item.url).frame(minHeight: 380).listRowInsets(EdgeInsets()) }
            Section("Symbols") { ForEach(symbols) { symbol in VStack(alignment: .leading) { HStack { Text(symbol.name).font(.headline); Spacer(); Text("L\(symbol.line)").font(.caption.monospacedDigit()).foregroundStyle(.cyan) }; Text(symbol.kind + " • " + symbol.signature).font(.caption).foregroundStyle(.secondary) } } }
        }.navigationTitle("Code Workspace")
    }
}

struct NexusV9CompareFilesView: View {
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var leftID: UUID?
    @State private var rightID: UUID?
    var body: some View {
        List {
            Section("Choose two files") {
                Picker("Left", selection: $leftID) { Text("Select").tag(UUID?.none); ForEach(library.files) { Text($0.name).tag(Optional($0.id)) } }
                Picker("Right", selection: $rightID) { Text("Select").tag(UUID?.none); ForEach(library.files) { Text($0.name).tag(Optional($0.id)) } }
            }
            if let left = library.files.first(where: { $0.id == leftID }), let right = library.files.first(where: { $0.id == rightID }) {
                let result = NexusV9CompareEngine.compare(left, right)
                Section("Similarity") { ProgressView(value: result.similarity); Text(result.similarity, format: .percent.precision(.fractionLength(1))) }
                Section("Only in \(left.name)") { ForEach(result.onlyLeft.prefix(15), id: \.self) { Text($0).font(.caption) } }
                Section("Only in \(right.name)") { ForEach(result.onlyRight.prefix(15), id: \.self) { Text($0).font(.caption) } }
                Section("Possible contradictions") { if result.contradictions.isEmpty { Text("No simple text-level contradictions detected.") } else { ForEach(result.contradictions, id: \.self) { Text($0).font(.caption) } } }
            }
        }.navigationTitle("Compare / What Changed?")
    }
}
