import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootV4View: View {
    @EnvironmentObject var model: NexusModel

    var body: some View {
        TabView {
            NavigationStack { HomeV4View() }
                .tabItem { Label("Home", systemImage: "sparkles") }
            NavigationStack { ConnectionsV4View() }
                .tabItem { Label("Connect", systemImage: "square.and.arrow.down.on.square") }
            NavigationStack { DiscoverV4View() }
                .tabItem { Label("Discover", systemImage: "scope") }
            NavigationStack { KnowledgeGraphV3View() }
                .tabItem { Label("Graph", systemImage: "point.3.filled.connected.trianglepath.dotted") }
            NavigationStack { AskV3View() }
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right.fill") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
}

struct HomeV4View: View {
    @EnvironmentObject var model: NexusModel

    var body: some View {
        let report = model.comprehensiveReport
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("NEXUS").font(.system(size: 40, weight: .black, design: .rounded)).tracking(7)
                    Text("PERSONAL KNOWLEDGE INTELLIGENCE").font(.caption.bold()).foregroundStyle(.cyan)
                    Text("Evidence-weighted analysis with uncertainty, source-bias checks and on-device intelligence.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    metric("Records", "\(model.records.count)", "doc.text.magnifyingglass")
                    metric("Sources", "\(Set(model.records.map(\.source)).count)", "square.stack.3d.up")
                    metric("Confidence", "\(Int(report.confidence * 100))%", "gauge.with.dots.needle.50percent")
                }

                panel {
                    HStack(spacing: 12) {
                        Image(systemName: NexusIntelligenceEngine.appleIntelligenceAvailable ? "apple.intelligence" : "brain.head.profile.fill")
                            .font(.title2).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Intelligence engine").font(.headline)
                            Text(model.v3AIStatus).font(.subheadline).foregroundStyle(.secondary)
                            Text(NexusIntelligenceEngine.appleIntelligenceAvailable ? "Apple's built-in on-device foundation model is available." : "NEXUS local retrieval and analytics are active; no bundled model weights are required.")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }

                panel {
                    Text("Overall assessment").font(.headline)
                    Text(report.overall).foregroundStyle(.secondary)
                }

                panel {
                    Text("Evidence quality").font(.headline)
                    Text(report.qualitySummary).font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: report.confidence)
                }

                if let first = report.sections.first(where: { $0.title == "Interests & sustained attention" }) {
                    panel {
                        Label("Strongest current pattern", systemImage: "scope").font(.headline)
                        Text(first.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                panel {
                    Label("NEXUS now reduces confidence when one app dominates, timestamps are sparse, the timeline is short, or mixed-participant messages could distort personality analysis.", systemImage: "checkmark.shield.fill")
                        .font(.subheadline).foregroundStyle(.green)
                }
            }
            .padding()
        }
    }

    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).foregroundStyle(.cyan)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) { content() }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Native document picker

private enum NexusPickerMode {
    case archive
    case folder
}

private struct NexusNativeDocumentPicker: UIViewControllerRepresentable {
    let mode: NexusPickerMode
    let onPicked: ([URL]) -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        switch mode {
        case .archive:
            let types: [UTType] = [.zip, .json, .plainText, .commaSeparatedText, .html, .xml, .data]
            picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.allowsMultipleSelection = true
        case .folder:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.allowsMultipleSelection = false
        }
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NexusNativeDocumentPicker
        init(parent: NexusNativeDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPicked(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancelled()
        }
    }
}

struct ConnectionsV4View: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var hub = DeviceConnectorHub()
    @State private var target = "Imported Files"
    @State private var showArchivePicker = false
    @State private var showFolderPicker = false
    @State private var importBusy = false
    @State private var progressText = ""
    @State private var nativeBusy = ""

    var body: some View {
        List {
            if importBusy || !progressText.isEmpty || !model.importStatus.isEmpty {
                Section("Import status") {
                    if importBusy { ProgressView(progressText.isEmpty ? "Preparing import…" : progressText) }
                    if !model.importStatus.isEmpty {
                        Label(model.importStatus, systemImage: model.importStatus.lowercased().contains("imported") ? "checkmark.circle.fill" : "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(model.importStatus.lowercased().contains("imported") ? Color.green : Color.secondary)
                    }
                }
            }

            Section("Archive imports") {
                importRow(title: "Instagram", detail: "Select the original Instagram ZIP or JSON export", symbol: "camera.circle.fill")
                importRow(title: "Facebook / Messenger", detail: "Select the original Meta ZIP or JSON export", symbol: "bubble.left.and.bubble.right.fill")
                importRow(title: "Files / iCloud Drive", detail: "ZIP, JSON, CSV, TXT, HTML or XML", symbol: "doc.zipper")
            }

            Section("Extracted folders") {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").frame(width: 26).foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Import an extracted folder").font(.headline)
                        Text("Separate folder picker avoids iOS disabling Open for ZIP files in mixed file/folder mode.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Folder") {
                        target = "Imported Files"
                        showFolderPicker = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(importBusy)
                }
                .padding(.vertical, 4)
            }

            Section("On-device sources") {
                ForEach(model.connectors.filter { $0.mode == .native }) { connector in
                    HStack(spacing: 12) {
                        Image(systemName: connector.symbol).frame(width: 26).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connector.name).font(.headline)
                            Text(connector.detail).font(.caption).foregroundStyle(.secondary)
                            Text(connector.status).font(.caption2)
                                .foregroundStyle(connector.status.contains("Connected") || connector.status.contains("records") ? Color.green : Color.secondary)
                        }
                        Spacer()
                        Button(nativeBusy == connector.id ? "…" : "Connect") {
                            nativeBusy = connector.id
                            hub.connect(connector.id) { records, status in
                                if !records.isEmpty { model.merge(records, sourceName: connector.name) }
                                model.setStatus(id: connector.id, status: records.isEmpty ? "No accessible data" : status)
                                nativeBusy = ""
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(importBusy || !nativeBusy.isEmpty)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Importer behavior") {
                Text("Archive files now use Apple's native document picker in copy mode. NEXUS receives its own local copy, then streams supported JSON/text entries directly from ZIP archives without extracting photos and videos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connections")
        .sheet(isPresented: $showArchivePicker) {
            NexusNativeDocumentPicker(mode: .archive, onPicked: { urls in
                showArchivePicker = false
                process(urls)
            }, onCancelled: {
                showArchivePicker = false
            })
        }
        .sheet(isPresented: $showFolderPicker) {
            NexusNativeDocumentPicker(mode: .folder, onPicked: { urls in
                showFolderPicker = false
                process(urls)
            }, onCancelled: {
                showFolderPicker = false
            })
        }
    }

    private func importRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 26).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Import") {
                target = title
                showArchivePicker = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(importBusy)
        }
        .padding(.vertical, 4)
    }

    private func process(_ urls: [URL]) {
        guard !urls.isEmpty else {
            model.reportImportError("Nothing was selected.")
            return
        }
        let selectedTarget = target
        importBusy = true
        progressText = "Copying \(urls.count) selection\(urls.count == 1 ? "" : "s") into NEXUS…"
        Task {
            let result = await NexusImportCoordinator.importURLs(urls, target: selectedTarget)
            progressText = "Indexing \(result.records.count) discovered records…"
            if !result.records.isEmpty {
                model.merge(result.records, sourceName: selectedTarget)
                if !result.errors.isEmpty {
                    model.reportImportError(model.importStatus + " Skipped: " + result.errors.joined(separator: " • "))
                }
            } else {
                let message = result.errors.isEmpty ? "The file opened, but no usable records were found." : result.errors.joined(separator: " • ")
                model.reportImportError(message)
            }
            progressText = ""
            importBusy = false
        }
    }
}

struct DiscoverV4View: View {
    @EnvironmentObject var model: NexusModel
    @State private var selectedDiscovery: NexusDiscovery?

    var body: some View {
        let report = model.comprehensiveReport
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Overall analysis").font(.title2.bold())
                        Spacer()
                        Text("\(Int(report.confidence * 100))% evidence confidence")
                            .font(.caption.bold()).foregroundStyle(.cyan)
                    }
                    Text(report.overall).foregroundStyle(.secondary)
                    ProgressView(value: report.confidence)
                }
                .analysisPanel()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Personality — behavioral evidence").font(.title3.bold())
                    Text("Ranges are intentionally wider when evidence is sparse. Mixed-participant message text is excluded from personality scoring unless self-authorship can be established.")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(report.traits) { trait in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(trait.name).font(.headline)
                                Spacer()
                                if let estimate = trait.estimate, let low = trait.low, let high = trait.high {
                                    Text("\(estimate)  [\(low)–\(high)]").font(.subheadline.bold()).foregroundStyle(.cyan)
                                } else {
                                    Text("Insufficient evidence").font(.caption.bold()).foregroundStyle(.orange)
                                }
                            }
                            if let estimate = trait.estimate {
                                ProgressView(value: Double(estimate), total: 100)
                            }
                            Text(trait.rationale).font(.caption).foregroundStyle(.secondary)
                            Text("Confidence: \(Int(trait.confidence * 100))%").font(.caption2).foregroundStyle(.tertiary)
                            DisclosureGroup("Evidence") {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(trait.evidence, id: \.self) { Text("• \($0)").font(.caption2).foregroundStyle(.secondary) }
                                }.padding(.top, 4)
                            }
                            .font(.caption).tint(.cyan)
                        }
                        .padding(.vertical, 5)
                    }
                }
                .analysisPanel()

                Text("Comprehensive model").font(.title3.bold())
                ForEach(report.sections) { section in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(section.title).font(.headline)
                            Spacer()
                            Text("\(Int(section.confidence * 100))%")
                                .font(.caption.bold()).foregroundStyle(.cyan)
                        }
                        ProgressView(value: section.confidence)
                        Text(section.summary).font(.subheadline).foregroundStyle(.secondary)
                        DisclosureGroup("Evidence & methodology") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.details, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.top, 5)
                        }
                        .tint(.cyan)
                    }
                    .analysisPanel()
                }

                if !model.v3Discoveries.isEmpty {
                    Text("Discovery lab").font(.title3.bold())
                    ForEach(model.v3Discoveries) { discovery in
                        Button { selectedDiscovery = discovery } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: discovery.symbol).font(.title2).foregroundStyle(.cyan).frame(width: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(discovery.title).font(.headline); Spacer(); Text(discovery.value).font(.caption.bold()).foregroundStyle(.cyan).lineLimit(1) }
                                    Text(discovery.explanation).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .analysisPanel()
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("What NEXUS still cannot know", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                    ForEach(report.limitations, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                }
                .analysisPanel()
            }
            .padding()
        }
        .navigationTitle("Discover")
        .sheet(item: $selectedDiscovery) { discovery in
            NavigationStack {
                List {
                    Section { Text(discovery.explanation) }
                    Section("Evidence") { ForEach(discovery.evidence, id: \.self) { Text($0) } }
                }
                .navigationTitle(discovery.title)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private extension View {
    func analysisPanel() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
