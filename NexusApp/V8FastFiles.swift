import SwiftUI

struct FilesV8FastView: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @ObservedObject private var hub = NexusV8FastChatHub.shared
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
                Text("Files stay inside NEXUS after import. Open them directly, attach them in Chat, or analyze several formats together with the same fast shared AI used by Chat.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { showImporter = true } label: { Label("Import files", systemImage: "square.and.arrow.down") }
                if !importError.isEmpty { Text(importError).font(.caption).foregroundStyle(.red) }
            }

            Section("Response speed") {
                Picker("Mode", selection: $hub.mode) {
                    ForEach(NexusV8ChatSpeedMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                Text("Fast uses compact retrieval and one primary model pass. Auto stays fast for normal requests and escalates only clearly heavy analysis. Deep uses the broader multi-engine path.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Shared AI") {
                HStack {
                    Label("Language", systemImage: "text.bubble.fill")
                    Spacer()
                    Text(language.activeModelID.isEmpty ? "Not loaded" : "Loaded")
                        .foregroundStyle(language.activeModelID.isEmpty ? Color.secondary : Color.green)
                }
                HStack {
                    Label("Vision", systemImage: "eye.fill")
                    Spacer()
                    Text(vision.activePresetID.isEmpty ? "Not loaded" : "Loaded")
                        .foregroundStyle(vision.activePresetID.isEmpty ? Color.secondary : Color.green)
                }
                NavigationLink("Shared language models") { PortableModelsV8View() }
                NavigationLink("Vision model manager") { MultimodalLabV8View() }
            }

            Section("Imported files") {
                if library.files.isEmpty {
                    ContentUnavailableView("No files yet", systemImage: "folder", description: Text("Import images, PDFs, CSVs, text/code, or other documents."))
                }
                ForEach(library.files) { item in
                    HStack(spacing: 10) {
                        Button { toggle(item) } label: {
                            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIDs.contains(item.id) ? Color.cyan : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        NavigationLink { NexusV8FileViewer(item: item) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).lineLimit(1)
                                Text("\(item.kindLabel) • \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            selectedIDs.remove(item.id)
                            library.remove(item)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }

            Section("Ask about selected files") {
                TextField("What do you want to know?", text: $question, axis: .vertical).lineLimit(2...5)
                Button {
                    let files = selected
                    Task {
                        let result = await hub.answer(question: question,
                                                      records: model.records,
                                                      attachments: files,
                                                      history: model.chatMessages)
                        answer = result.text
                        evidence = result.evidence
                    }
                } label: {
                    Label(selected.isEmpty ? "Select files above" : "Analyze \(selected.count) file\(selected.count == 1 ? "" : "s")", systemImage: "bolt.fill")
                }
                .disabled(selected.isEmpty || hub.busy)
                if hub.busy { HStack { ProgressView(); Text(hub.status).font(.caption).foregroundStyle(.secondary) } }
            }

            if !answer.isEmpty {
                Section("Answer") {
                    Text(answer).textSelection(.enabled)
                    if !evidence.isEmpty {
                        DisclosureGroup("Sources & notes") {
                            ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                                Text("• \(item)").font(.caption).foregroundStyle(.secondary)
                            }
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
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func toggle(_ item: NexusV8FileItem) {
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
        else { selectedIDs.insert(item.id) }
    }
}
