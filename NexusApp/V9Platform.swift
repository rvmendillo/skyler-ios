import Foundation
import SwiftUI
import UIKit
import Speech
import AVFoundation
import VisionKit
import PhotosUI
import AppIntents
import ZIPFoundation

struct NexusV9StorageSnapshot: Hashable {
    let models: Int64; let files: Int64; let indexes: Int64; let caches: Int64; let total: Int64
}

enum NexusV9StorageEngine {
    static func snapshot() -> NexusV9StorageSnapshot {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let models = size(base.appendingPathComponent("NEXUS-Models"))
        let files = size(base.appendingPathComponent("NEXUS-Files"))
        let indexes = ["nexus-v9-index.json","nexus-v9-state.json","nexus-vault.json"].reduce(Int64(0)) { $0 + size(base.appendingPathComponent($1)) }
        let total = size(base)
        return NexusV9StorageSnapshot(models: models, files: files, indexes: indexes, caches: max(0,total-models-files-indexes), total: total)
    }
    static func size(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let file as URL in e { total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        } else { total = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }
}

struct NexusV9BenchmarkResult: Hashable {
    let vectorMS: Double; let searchMS: Double; let modelSeconds: Double?; let modelCharacters: Int; let memoryGB: Double
}

@MainActor
enum NexusV9Benchmark {
    static func run() async -> NexusV9BenchmarkResult {
        let intelligence = NexusV9IntelligenceStore.shared
        let startedVector = CFAbsoluteTimeGetCurrent()
        for i in 0..<80 { _ = intelligence.vector(for: "NEXUS benchmark semantic retrieval local model performance \(i)") }
        let vectorMS = (CFAbsoluteTimeGetCurrent() - startedVector) * 1000
        let startedSearch = CFAbsoluteTimeGetCurrent(); _ = intelligence.search("important recent projects and recurring patterns", limit: 20)
        let searchMS = (CFAbsoluteTimeGetCurrent() - startedSearch) * 1000
        var modelSeconds: Double?; var chars = 0
        if !NexusPortableModelStore.shared.activeModelID.isEmpty {
            let start = CFAbsoluteTimeGetCurrent()
            if let answer = await NexusPortableModelStore.shared.respond("Reply with one concise sentence explaining that this is a local NEXUS performance benchmark.") { chars = answer.count }
            modelSeconds = CFAbsoluteTimeGetCurrent() - start
        }
        let ram = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return NexusV9BenchmarkResult(vectorMS: vectorMS, searchMS: searchMS, modelSeconds: modelSeconds, modelCharacters: chars, memoryGB: ram)
    }
}

@MainActor
final class NexusV9VoiceController: ObservableObject {
    @Published var transcript = ""
    @Published var listening = false
    @Published var status = "Ready"
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        SFSpeechRecognizer.requestAuthorization { auth in
            Task { @MainActor in
                guard auth == .authorized else { self.status = "Speech recognition permission was not granted."; return }
                self.beginAudio()
            }
        }
    }

    func stop() {
        engine.stop(); engine.inputNode.removeTap(onBus: 0); request?.endAudio(); task?.cancel(); task = nil; request = nil; listening = false; status = "Ready"
    }

    private func beginAudio() {
        stop()
        do {
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.record, mode: .measurement, options: [.duckOthers]); try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
            let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true; self.request = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            task = recognizer?.recognitionTask(with: request) { result, error in
                Task { @MainActor in
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
            engine.prepare(); try engine.start(); listening = true; status = "Listening…"
        } catch { status = error.localizedDescription; stop() }
    }
}

struct NexusV9VoiceView: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var voice = NexusV9VoiceController()
    @State private var answer = ""
    var body: some View {
        List {
            Section { Text(voice.transcript.isEmpty ? "Tap the microphone and speak naturally." : voice.transcript).textSelection(.enabled); Button { voice.listening ? voice.stop() : voice.start() } label: { Label(voice.listening ? "Stop" : "Start listening", systemImage: voice.listening ? "stop.circle.fill" : "mic.circle.fill") }; Text(voice.status).font(.caption).foregroundStyle(.secondary) }
            Section("Ask NEXUS") { Button("Send transcript") { ask() }.disabled(voice.transcript.isEmpty); if !answer.isEmpty { Text(answer).textSelection(.enabled) } }
        }.navigationTitle("Voice Conversation")
    }
    private func ask() { let q = voice.transcript; Task { let result = await NexusV9Assistant.shared.answer(question: q, records: model.records, history: model.chatMessages); await MainActor.run { answer = result.text } } }
}

struct NexusV9DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController { let c = VNDocumentCameraViewController(); c.delegate = context.coordinator; return c }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: NexusV9DocumentScanner; init(parent: NexusV9DocumentScanner) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) { var images:[UIImage]=[]; for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }; controller.dismiss(animated: true); parent.onScan(images) }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { controller.dismiss(animated: true) }
    }
}

struct NexusV9CaptureView: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var scanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var result = ""
    var body: some View {
        List {
            Section("Camera intelligence") { Button { scanner = true } label: { Label("Scan a document", systemImage: "doc.viewfinder") }; Text("Scans are saved into NEXUS Files, indexed, OCR-readable and available to Chat/Graph/Search.").font(.caption).foregroundStyle(.secondary) }
            Section("Photo intelligence") { PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose a photo", systemImage: "photo.on.rectangle") }; Text("Selected photos are copied into the local NEXUS file library before analysis.").font(.caption).foregroundStyle(.secondary) }
            if !result.isEmpty { Section("Status") { Text(result) } }
        }.navigationTitle("Camera & Photos")
        .sheet(isPresented: $scanner) { NexusV9DocumentScanner { images in scanner = false; save(images) } }
        .onChange(of: photoItem) { _, newValue in guard let newValue else { return }; Task { if let data = try? await newValue.loadTransferable(type: Data.self), let image = UIImage(data: data) { await MainActor.run { save([image]) } } } }
    }
    private func save(_ images: [UIImage]) {
        var urls:[URL]=[]; let temp = FileManager.default.temporaryDirectory
        for (i,image) in images.enumerated() { let url = temp.appendingPathComponent("NEXUS-Capture-\(UUID().uuidString)-\(i+1).jpg"); if let data = image.jpegData(compressionQuality: 0.92) { try? data.write(to: url); urls.append(url) } }
        do { let imported = try library.importURLs(urls); result = "Imported \(imported.count) image(s)."; Task { await NexusV9IntelligenceStore.shared.index(records: model.records, files: library.files) } } catch { result = error.localizedDescription }
    }
}

@MainActor
final class NexusV9ResearchCapture: ObservableObject {
    static let shared = NexusV9ResearchCapture()
    @Published var status = "Ready"
    func capture(urlString: String) async -> NexusV8FileItem? {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), ["http","https"].contains(scheme) else { status = "Enter a valid HTTPS/HTTP URL."; return nil }
        status = "Saving offline research snapshot…"
        do {
            let (data,response) = try await URLSession.shared.data(from: url)
            let title = (response as? HTTPURLResponse)?.suggestedFilename ?? url.host ?? "webpage"
            let safe = title.replacingOccurrences(of: "/", with: "-")
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe)-\(UUID().uuidString).html")
            try data.write(to: temp)
            let imported = try NexusV8FileLibrary.shared.importURLs([temp])
            status = "Captured offline snapshot from \(url.host ?? "web")"
            return imported.first
        } catch { status = error.localizedDescription; return nil }
    }
}

struct NexusV9ResearchView: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var capture = NexusV9ResearchCapture.shared
    @State private var url = ""
    var body: some View {
        List {
            Section("Safari / web research capture") { TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never); Button("Capture offline") { Task { if let _ = await capture.capture(urlString: url) { await NexusV9IntelligenceStore.shared.index(records: model.records, files: NexusV8FileLibrary.shared.files) } } }; Text(capture.status).font(.caption).foregroundStyle(.secondary) }
            Section("How it is stored") { Text("NEXUS saves the fetched page as a local HTML snapshot so future file search and AI analysis do not depend on the webpage remaining online. The Share extension can hand URLs/text into the same capture flow.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Research Capture")
    }
}

struct NexusV9WatchedFolder: Identifiable, Codable, Hashable { let id: UUID; var path: String; var name: String; var knownNames: Set<String> }

@MainActor
final class NexusV9WatchFolderStore: ObservableObject {
    static let shared = NexusV9WatchFolderStore()
    @Published var folders:[NexusV9WatchedFolder] = []
    @Published var status = "No folders watched"
    private let key = "nexus.v9.watchfolders"
    private init() { if let data = UserDefaults.standard.data(forKey: key), let x = try? JSONDecoder().decode([NexusV9WatchedFolder].self, from: data) { folders = x } }
    func add(_ url: URL) { let names = Set(((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])); folders.append(.init(id: UUID(), path: url.path, name: url.lastPathComponent, knownNames: names)); persist(); status = "Watching \(url.lastPathComponent) while access remains available" }
    func scan() -> [URL] {
        var found:[URL]=[]
        for i in folders.indices { let url = URL(fileURLWithPath: folders[i].path); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; let names = Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []); for name in names.subtracting(folders[i].knownNames) { found.append(url.appendingPathComponent(name)) }; folders[i].knownNames = names }
        persist(); status = found.isEmpty ? "No new files" : "Found \(found.count) new file(s)"; return found
    }
    private func persist() { if let data = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(data, forKey: key) } }
}

struct NexusV9FolderPicker: UIViewControllerRepresentable {
    let onPick:(URL)->Void
    func makeCoordinator() -> Coordinator { Coordinator(parent:self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { let c = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false); c.delegate=context.coordinator; return c }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator:NSObject,UIDocumentPickerDelegate { let parent:NexusV9FolderPicker; init(parent:NexusV9FolderPicker){self.parent=parent}; func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls:[URL]) { if let u=urls.first { parent.onPick(u) } } }
}

struct NexusV9WatchFoldersView: View {
    @EnvironmentObject var model:NexusModel
    @ObservedObject private var watch = NexusV9WatchFolderStore.shared
    @State private var picker=false
    var body: some View {
        List { Section { Button("Add watch folder") { picker=true }; Button("Scan now") { let urls=watch.scan(); if !urls.isEmpty { do { _ = try NexusV8FileLibrary.shared.importURLs(urls); Task { await NexusV9IntelligenceStore.shared.index(records:model.records, files:NexusV8FileLibrary.shared.files) } } catch { } } }; Text(watch.status).font(.caption).foregroundStyle(.secondary) }; Section("Folders") { ForEach(watch.folders) { f in Label(f.name, systemImage:"folder.badge.gearshape") } } }.navigationTitle("Watch Folders").sheet(isPresented:$picker) { NexusV9FolderPicker { watch.add($0); picker=false } }
    }
}

enum NexusV9ReportExporter {
    static func markdown(title:String, body:String, citations:[NexusV9Citation]) throws -> URL {
        let text = "# \(title)\n\n\(body)\n\n## Sources\n" + citations.map { "- \($0.sourceName) — \($0.location): \($0.excerpt)" }.joined(separator:"\n")
        return try write(text.data(using:.utf8) ?? Data(), ext:"md", title:title)
    }
    static func html(title:String, body:String, citations:[NexusV9Citation]) throws -> URL {
        let escaped = body.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:"\n",with:"<br>")
        let html = "<html><meta name='viewport' content='width=device-width'><body><h1>\(title)</h1><p>\(escaped)</p><h2>Sources</h2><ul>" + citations.map { "<li><b>\($0.sourceName)</b> \($0.location): \($0.excerpt)</li>" }.joined() + "</ul></body></html>"
        return try write(html.data(using:.utf8) ?? Data(),ext:"html",title:title)
    }
    static func pdf(title:String, body:String, citations:[NexusV9Citation]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe(title)+"-report.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792))
        try renderer.writePDF(to:url) { context in
            let content = title+"\n\n"+body+"\n\nSources\n"+citations.map { "• \($0.sourceName) — \($0.location)\n\($0.excerpt)" }.joined(separator:"\n\n")
            let attr = NSAttributedString(string:content,attributes:[.font:UIFont.systemFont(ofSize:11),.foregroundColor:UIColor.label])
            var offset=0
            while offset < attr.length { context.beginPage(); let framesetter = CTFramesetterCreateWithAttributedString(attr); let path=CGPath(rect:CGRect(x:45,y:45,width:522,height:702),transform:nil); let frame=CTFramesetterCreateFrame(framesetter,CFRange(location:offset,length:0),path,nil); CTFrameDraw(frame,context.cgContext); let visible=CTFrameGetVisibleStringRange(frame); if visible.length == 0 { break }; offset += visible.length }
        }
        return url
    }
    static func package(title:String, body:String, citations:[NexusV9Citation], files:[NexusV8FileItem]) throws -> URL {
        let fm=FileManager.default; let folder=fm.temporaryDirectory.appendingPathComponent("NEXUS-Package-\(UUID().uuidString)",isDirectory:true); try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let md=try markdown(title:title,body:body,citations:citations); try fm.copyItem(at:md,to:folder.appendingPathComponent("report.md"))
        let meta = try JSONEncoder().encode(citations); try meta.write(to:folder.appendingPathComponent("citations.json"))
        let originals=folder.appendingPathComponent("Originals",isDirectory:true); try fm.createDirectory(at:originals,withIntermediateDirectories:true)
        for file in files.prefix(30) { let target=originals.appendingPathComponent(file.name); if !fm.fileExists(atPath:target.path) { try? fm.copyItem(at:file.url,to:target) } }
        let zip=fm.temporaryDirectory.appendingPathComponent(safe(title)+"-NEXUS.zip"); try? fm.removeItem(at:zip); try fm.zipItem(at:folder,to:zip); return zip
    }
    private static func write(_ data:Data,ext:String,title:String)throws->URL { let u=FileManager.default.temporaryDirectory.appendingPathComponent(safe(title)+"-report."+ext); try data.write(to:u,options:.atomic); return u }
    private static func safe(_ s:String)->String { String(s.prefix(50)).replacingOccurrences(of:"/",with:"-").replacingOccurrences(of:":",with:"-") }
}

struct NexusV9ExportView: View {
    @ObservedObject private var assistant=NexusV9Assistant.shared
    @ObservedObject private var files=NexusV8FileLibrary.shared
    @State private var title="NEXUS Intelligence Report"
    @State private var body=""
    @State private var exportURL:URL?
    var body: some View {
        List { Section { TextField("Report title",text:$title); TextEditor(text:$body).frame(minHeight:150) }; Section("Export") { Button("Markdown") { exportURL=try? NexusV9ReportExporter.markdown(title:title,body:body,citations:assistant.lastCitations) }; Button("HTML") { exportURL=try? NexusV9ReportExporter.html(title:title,body:body,citations:assistant.lastCitations) }; Button("PDF") { exportURL=try? NexusV9ReportExporter.pdf(title:title,body:body,citations:assistant.lastCitations) }; Button("Portable intelligence package") { exportURL=try? NexusV9ReportExporter.package(title:title,body:body,citations:assistant.lastCitations,files:files.files) } }; if let exportURL { Section("Ready") { ShareLink(item:exportURL) { Label("Share \(exportURL.lastPathComponent)",systemImage:"square.and.arrow.up") } } } }.navigationTitle("Reports & Export")
    }
}

struct NexusV9SecurityView: View {
    @ObservedObject private var store=NexusV9IntelligenceStore.shared
    @State private var status=""
    var body: some View {
        List { Section("Vault lock") { Button("Authenticate with device security") { Task { let ok=await store.authenticateVault(); status=ok ? "Vault unlocked" : "Authentication failed" } }; Text(status).font(.caption); Toggle("Private chat session",isOn:$store.privateMode); Text("Private sessions are not added to the V9 semantic response cache.").font(.caption).foregroundStyle(.secondary) }; Section("Encrypted vault primitive") { Button("Test local encryption") { do { let sample=Data("NEXUS local encryption test".utf8); let encrypted=try store.encrypt(sample); let decrypted=try store.decrypt(encrypted); status=String(data:decrypted,encoding:.utf8)==nil ? "Encryption test failed" : "AES-GCM + device-only Keychain key verified" } catch { status=error.localizedDescription } }; Text("NEXUS uses a random AES-256 key stored in the iOS Keychain with this-device-only accessibility for encrypted exports/state that opt into vault protection.").font(.caption).foregroundStyle(.secondary) } }.navigationTitle("Privacy & Security")
    }
}

struct NexusV9StorageView: View {
    @State private var snap=NexusV9StorageEngine.snapshot()
    @ObservedObject private var models=NexusPortableModelStore.shared
    var body: some View { List { Section("Storage") { row("Models",snap.models); row("Imported files",snap.files); row("Indexes/state",snap.indexes); row("Other cache",snap.caches); row("Total",snap.total) }; Section("Model storage intelligence") { Text(models.memorySummary).font(.caption); ForEach(models.models.filter { models.isDownloaded($0) }) { model in HStack { VStack(alignment:.leading){Text(model.name);Text(model.approximateSize).font(.caption).foregroundStyle(.secondary)};Spacer(); if models.activeModelID != model.id { Button("Remove") { models.removeDownloadedWeights(model); snap=NexusV9StorageEngine.snapshot() } } } } }; Section { Button("Refresh") { snap=NexusV9StorageEngine.snapshot() } } }.navigationTitle("Storage Manager") }
    private func row(_ name:String,_ bytes:Int64)->some View { LabeledContent(name,value:ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)) }
}

struct NexusV9PerformanceView: View {
    @ObservedObject private var store=NexusV9IntelligenceStore.shared
    @State private var result:NexusV9BenchmarkResult?
    @State private var running=false
    var body: some View { List { Section("Adaptive performance") { Picker("Mode",selection:$store.performanceMode){ForEach(NexusV9PerformanceMode.allCases){Text($0.rawValue).tag($0)}}; Text("Battery Saver reduces retrieval/context and avoids automatic model warming. Maximum increases context and retrieval depth when the device can support it.").font(.caption).foregroundStyle(.secondary); Button("Warm best downloaded model") { Task { await store.warmBestLocalModel() } } }; Section("Device benchmark") { Button(running ? "Running…":"Run benchmark") { running=true; Task { let r=await NexusV9Benchmark.run(); await MainActor.run { result=r;running=false } } }.disabled(running); if let result { LabeledContent("Physical RAM",value:String(format:"%.1f GB",result.memoryGB)); LabeledContent("80 embeddings",value:String(format:"%.0f ms",result.vectorMS)); LabeledContent("Hybrid search",value:String(format:"%.1f ms",result.searchMS)); if let seconds=result.modelSeconds { LabeledContent("Local model pass",value:String(format:"%.2f s / %d chars",seconds,result.modelCharacters)) } else { Text("Load a local model to include inference in the benchmark.").font(.caption).foregroundStyle(.secondary) } } }; Section("Developer diagnostics") { LabeledContent("Indexed chunks",value:"\(store.diagnostics.indexedChunks)"); LabeledContent("Last retrieval",value:"\(store.diagnostics.lastRetrievalCount)"); LabeledContent("Last context",value:"\(store.diagnostics.lastContextCharacters) chars"); LabeledContent("Query latency",value:String(format:"%.1f ms",store.diagnostics.lastQueryMilliseconds)); LabeledContent("Cache",value:"\(store.diagnostics.cacheHits) hits / \(store.diagnostics.cacheMisses) misses"); LabeledContent("Route",value:store.diagnostics.lastRoute) } }.navigationTitle("Performance & Diagnostics") }
}

@MainActor
final class NexusV9DeepLink: ObservableObject {
    static let shared=NexusV9DeepLink(); @Published var lastRoute=""
    func handle(_ url:URL, model:NexusModel) {
        guard url.scheme?.lowercased()=="nexus" else{return}; lastRoute=url.host ?? ""
        if url.host=="capture" { let text=UIPasteboard.general.string ?? ""; if !text.isEmpty { let r=KnowledgeRecord(id:"share:\(UUID().uuidString)",source:"Share to NEXUS",kind:.note,timestamp:Date(),title:"Shared capture",text:text,metadata:["via":"share extension/deep link"]); model.merge([r],sourceName:"Share to NEXUS") } }
    }
}

struct AskNexusShortcutIntent: AppIntent {
    static var title: LocalizedStringResource="Ask NEXUS"
    static var description=IntentDescription("Open NEXUS with a question copied for local personal-intelligence chat.")
    @Parameter(title:"Question") var question:String
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { UIPasteboard.general.string=question }
        return .result(dialog:"Your question is ready. Open NEXUS Chat to answer it with your local indexed context.")
    }
}

struct CaptureToNexusShortcutIntent: AppIntent {
    static var title: LocalizedStringResource="Capture to NEXUS"
    @Parameter(title:"Text") var text:String
    func perform() async throws -> some IntentResult & ProvidesDialog { await MainActor.run { UIPasteboard.general.string=text }; return .result(dialog:"Copied into the NEXUS capture handoff.") }
}

struct NexusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] { AppShortcut(intent:AskNexusShortcutIntent(),phrases:["Ask \(.applicationName)","Ask my \(.applicationName)"],shortTitle:"Ask NEXUS",systemImageName:"brain.head.profile"); AppShortcut(intent:CaptureToNexusShortcutIntent(),phrases:["Capture to \(.applicationName)"],shortTitle:"Capture to NEXUS",systemImageName:"square.and.arrow.down") }
}
