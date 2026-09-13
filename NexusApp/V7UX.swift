import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit

@MainActor
final class NexusOperationCenter: ObservableObject {
    static let shared = NexusOperationCenter()
    @Published var active = false
    @Published var progress: Double = 0
    @Published var title = ""
    @Published var detail = ""

    func begin(_ title: String, detail: String = "") {
        self.title = title
        self.detail = detail
        progress = 0.02
        active = true
    }

    func update(_ value: Double, _ detail: String? = nil) {
        progress = min(1, max(0, value))
        if let detail { self.detail = detail }
    }

    func finish(_ detail: String) {
        progress = 1
        self.detail = detail
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if self.progress >= 1 { self.active = false }
        }
    }
}

struct NexusMergeSummary: Hashable {
    let incoming: Int
    let newCount: Int
    let updatedCount: Int
    let unchangedCount: Int

    var text: String {
        "\(newCount) new • \(updatedCount) updated • \(unchangedCount) unchanged/duplicate"
    }
}

extension NexusModel {
    @discardableResult
    func mergeV7(_ incoming: [KnowledgeRecord], sourceName: String) -> NexusMergeSummary {
        let uniqueIncoming = Array(Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values)
        let existing = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
        var inserted = 0
        var updated = 0
        var unchanged = 0
        for record in uniqueIncoming {
            if let old = existing[record.id] {
                if old == record { unchanged += 1 } else { updated += 1 }
            } else { inserted += 1 }
        }
        merge(uniqueIncoming, sourceName: sourceName)
        let summary = NexusMergeSummary(incoming: uniqueIncoming.count, newCount: inserted, updatedCount: updated, unchangedCount: unchanged)
        importStatus = "\(sourceName): \(summary.text). Vault total: \(records.count)."
        activityLog.insert(importStatus, at: 0)
        return summary
    }
}

enum NexusImportLedger {
    private static let defaultsKey = "nexus.import.ledger.v1"

    static func status(for urls: [URL], target: String) -> (alreadySeen: Bool, fingerprints: [String:String]) {
        var existing = load()
        var result: [String:String] = [:]
        var allSeen = !urls.isEmpty
        for url in urls {
            let key = target + "|" + url.lastPathComponent
            let fingerprint = fingerprint(url)
            result[key] = fingerprint
            if existing[key] != fingerprint { allSeen = false }
        }
        return (allSeen, result)
    }

    static func commit(_ fingerprints: [String:String]) {
        var existing = load()
        for (key, value) in fingerprints { existing[key] = value }
        if let data = try? JSONEncoder().encode(existing) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    private static func load() -> [String:String] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey), let decoded = try? JSONDecoder().decode([String:String].self, from: data) else { return [:] }
        return decoded
    }

    private static func fingerprint(_ url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var hasher = SHA256()
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            while autoreleasepool(invoking: {
                guard let data = try? handle.read(upToCount: 1_048_576), let data, !data.isEmpty else { return false }
                hasher.update(data: data)
                return true
            }) {}
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "fallback:\(values?.fileSize ?? -1):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }
}

private struct NexusV7Picker: UIViewControllerRepresentable {
    let folder: Bool
    let onPicked: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        if folder {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
            picker.allowsMultipleSelection = false
        } else {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .json, .plainText, .commaSeparatedText, .html, .xml, .data], asCopy: true)
            picker.allowsMultipleSelection = true
        }
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NexusV7Picker
        init(parent: NexusV7Picker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { parent.onPicked(urls) }
    }
}

struct NexusSplashV7: View {
    @State private var pulse = false
    @State private var progress = 0.08

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color.indigo.opacity(0.55), .black], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Circle().fill(.cyan.opacity(0.16)).frame(width: 330, height: 330).blur(radius: 30).scaleEffect(pulse ? 1.10 : 0.88)
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30).fill(.ultraThinMaterial).frame(width: 112, height: 112)
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted").font(.system(size: 52, weight: .bold)).foregroundStyle(.cyan)
                }
                .scaleEffect(pulse ? 1.04 : 0.96)
                Text("NEXUS").font(.system(size: 40, weight: .black, design: .rounded)).tracking(8)
                Text("PREPARING YOUR PERSONAL UNIVERSE").font(.caption.bold()).tracking(1.4).foregroundStyle(.cyan)
                ProgressView(value: progress).frame(width: 220).tint(.cyan)
                Text("Local-first • private • evidence-grounded").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeOut(duration: 1.25)) { progress = 1 }
        }
    }
}

struct OperationBannerV7: View {
    @ObservedObject var center = NexusOperationCenter.shared
    var body: some View {
        if center.active {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(center.title).font(.caption.bold()); Spacer(); Text("\(Int(center.progress * 100))%").font(.caption2.monospacedDigit()) }
                ProgressView(value: center.progress).tint(.cyan)
                if !center.detail.isEmpty { Text(center.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct RootV7View: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TabView {
                NavigationStack { HomeV7View() }.tabItem { Label("Home", systemImage: "sparkles") }
                NavigationStack { ConnectHubV7View() }.tabItem { Label("Connect", systemImage: "arrow.triangle.2.circlepath.circle.fill") }
                NavigationStack { ExploreHubV7View() }.tabItem { Label("Explore", systemImage: "book.pages.fill") }
                NavigationStack { KnowledgeGraphV3View() }.tabItem { Label("Graph", systemImage: "network") }
                NavigationStack { AskV6View() }.tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right.fill") }
            }
            .tint(.cyan)
            .preferredColorScheme(.dark)

            VStack { OperationBannerV7(); Spacer() }.allowsHitTesting(false)

            if showSplash {
                NexusSplashV7().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
    }
}

struct HomeV7View: View {
    @EnvironmentObject var model: NexusModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NEXUS").font(.system(size: 42, weight: .black, design: .rounded)).tracking(7)
                    Text("YOUR PERSONAL UNIVERSE").font(.caption.bold()).foregroundStyle(.cyan)
                    Text("Fast entry points first; deeper analysis runs only when you open it.").font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 9) {
                    quickMetric("Vault", "\(model.records.count)", "externaldrive.fill")
                    quickMetric("Chats", "\(model.records.lazy.filter { $0.kind == .message }.prefix(99999).count)", "bubble.left.and.bubble.right.fill")
                    quickMetric("AI", NexusIntelligenceEngine.appleIntelligenceAvailable ? "Apple+" : "Local", "brain.head.profile")
                }

                NavigationLink { ConversationTwinV7View() } label: { hero("Conversation Twin", "Chat with a clearly labeled simulation derived from an imported speaker's conversational patterns.", "person.2.wave.2.fill", .orange) }.buttonStyle(.plain)
                NavigationLink { StorybookV7View() } label: { hero("Animated Storybook", "Cartoon companions, narration, evidence-backed chapters and locally generated background music.", "play.square.stack.fill", .pink) }.buttonStyle(.plain)
                NavigationLink { PortableModelsV7View() } label: { hero("Portable Local LLMs", "Add GGUF models such as a tiny Qwen model; Metal accelerated and no AI API key.", "cpu.fill", .cyan) }.buttonStyle(.plain)
                NavigationLink { LifeAnalysisV6View() } label: { hero("Life Compass", "Strengths, constraints, goals, directions and uncertainty from standardized evidence.", "location.north.circle.fill", .green) }.buttonStyle(.plain)

                if !model.importStatus.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Latest vault update", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                        Text(model.importStatus).font(.caption).foregroundStyle(.secondary)
                    }.v7Panel()
                }

                if !model.activityLog.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Recent activity", systemImage: "clock.arrow.circlepath").font(.headline)
                        ForEach(Array(model.activityLog.prefix(4).enumerated()), id: \.offset) { _, line in Text(line).font(.caption).foregroundStyle(.secondary) }
                    }.v7Panel()
                }
            }.padding()
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func quickMetric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Image(systemName: icon).foregroundStyle(.cyan); Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.55); Text(label).font(.caption2).foregroundStyle(.secondary) }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func hero(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 13) {
            ZStack { RoundedRectangle(cornerRadius: 18).fill(color.opacity(0.16)).frame(width: 58, height: 58); Image(systemName: symbol).font(.title2).foregroundStyle(color) }
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.v7Panel()
    }
}

struct ConnectHubV7View: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var hub = DeviceConnectorHub()
    @State private var pickerTarget: String?
    @State private var folderPicker = false
    @State private var nativeBusy = ""

    var body: some View {
        List {
            Section {
                Text("Re-importing is safe: NEXUS verifies the selected file, rescans it for updates, replaces changed records with stable IDs, and skips exact duplicates.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Section("Meta + files") {
                importRow("Instagram", "Original ZIP/JSON export", "camera.circle.fill")
                importRow("Facebook / Messenger", "Original Meta ZIP/JSON export", "bubble.left.and.bubble.right.fill")
                importRow("Files / iCloud Drive", "ZIP, JSON, CSV, TXT, HTML, XML", "doc.zipper")
                Button { folderPicker = true } label: { Label("Import extracted folder", systemImage: "folder.fill") }
            }

            Section("On-device connectors • update anytime") {
                ForEach(model.connectors.filter { $0.mode == .native }) { connector in
                    HStack(spacing: 11) {
                        Image(systemName: connector.symbol).foregroundStyle(.cyan).frame(width: 27)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connector.name).font(.headline)
                            Text(connector.detail).font(.caption).foregroundStyle(.secondary)
                            Text(connector.status).font(.caption2).foregroundStyle(connector.status.contains("record") || connector.status.contains("Connected") ? .green : .secondary)
                        }
                        Spacer()
                        Button(connector.status.contains("record") || connector.status.contains("Connected") ? "Update" : "Connect") { sync(connector) }
                            .buttonStyle(.bordered).disabled(!nativeBusy.isEmpty)
                    }.padding(.vertical, 3)
                }
            }

            Section("More connectors") {
                NavigationLink { ConnectHubV6View() } label: { Label("OAuth + export connectors", systemImage: "link.circle.fill") }
                Text("Includes GitHub device OAuth plus ChatGPT, Google Takeout, Spotify, Discord, LinkedIn, browser, finance and notes export imports.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connections")
        .sheet(item: $pickerTarget) { target in
            NexusV7Picker(folder: false) { urls in pickerTarget = nil; importFiles(urls, target: target) }
        }
        .sheet(isPresented: $folderPicker) {
            NexusV7Picker(folder: true) { urls in folderPicker = false; importFiles(urls, target: "Imported Files") }
        }
    }

    private func importRow(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).foregroundStyle(.cyan).frame(width: 27)
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Button("Import / Update") { pickerTarget = title }.buttonStyle(.borderedProminent)
        }.padding(.vertical, 3)
    }

    private func importFiles(_ urls: [URL], target: String) {
        guard !urls.isEmpty else { return }
        let center = NexusOperationCenter.shared
        center.begin("Importing \(target)", detail: "Checking whether this export was imported before…")
        Task {
            center.update(0.08, "Fingerprinting selected file\(urls.count == 1 ? "" : "s")…")
            let ledger = await Task.detached { NexusImportLedger.status(for: urls, target: target) }.value
            center.update(0.16, ledger.alreadySeen ? "Already imported • rescanning for updates…" : "New or changed export detected…")
            let result = await NexusImportCoordinator.importURLs(urls, target: target)
            center.update(0.74, "Comparing \(result.records.count) parsed records with your vault…")
            if result.records.isEmpty {
                let message = result.errors.first ?? "No supported records found."
                model.reportImportError(message)
                center.finish(message)
                return
            }
            let summary = model.mergeV7(result.records, sourceName: target)
            NexusImportLedger.commit(ledger.fingerprints)
            center.update(0.92, "Saving deduplicated vault…")
            let final = (ledger.alreadySeen ? "Verified existing import • " : "Import complete • ") + summary.text
            center.finish(final)
            if !result.errors.isEmpty { model.reportImportError(model.importStatus + " Warnings: " + result.errors.joined(separator: " • ")) }
        }
    }

    private func sync(_ connector: ConnectorState) {
        nativeBusy = connector.id
        let center = NexusOperationCenter.shared
        center.begin("Updating \(connector.name)", detail: "Requesting authorized local data…")
        center.update(0.15)
        hub.connect(connector.id) { records, status in
            if records.isEmpty {
                model.setStatus(id: connector.id, status: "No accessible data / permission not granted")
                center.finish("No accessible records returned")
            } else {
                center.update(0.72, "Comparing \(records.count) local records with the vault…")
                let summary = model.mergeV7(records, sourceName: connector.name)
                model.setStatus(id: connector.id, status: "Connected • \(records.count) records • \(summary.updatedCount) updated")
                center.finish(summary.text)
            }
            nativeBusy = ""
        }
    }
}

struct ExploreHubV7View: View {
    var body: some View {
        List {
            Section("Immersive") {
                NavigationLink { StorybookV7View() } label: { row("Animated Storybook", "Cartoon scenes, narration, music and evidence", "play.square.stack.fill", .pink) }
                NavigationLink { TimelineV6View() } label: { row("Life Timeline", "Searchable chronological evidence", "clock.arrow.trianglehead.counterclockwise.rotate.90", .cyan) }
                NavigationLink { ConversationTwinV7View() } label: { row("Conversation Twin", "Style simulation from imported conversations", "person.2.wave.2.fill", .orange) }
            }
            Section("Reasoning labs") {
                NavigationLink { LifeAnalysisV6View() } label: { row("Life Compass", "Goals, strengths, weaknesses and direction", "location.north.circle.fill", .green) }
                NavigationLink { StandardizationLabV6View() } label: { row("Universal Patterns", "Patterns standardized across unrelated sources", "point.3.connected.trianglepath.dotted", .cyan) }
                NavigationLink { AIModelLabV6View() } label: { row("AI Ensemble", "Agreement and disagreement between local engines", "brain.head.profile", .purple) }
                NavigationLink { PortableModelsV7View() } label: { row("Portable GGUF LLMs", "Optional llama.cpp models on iPhone", "cpu.fill", .yellow) }
                NavigationLink { DecisionLabV6View() } label: { row("Decision Lab", "Stress-test choices against evidence", "scale.3d", .mint) }
                NavigationLink { DiscoverV4View() } label: { row("Deep Analysis", "Comprehensive evidence and uncertainty", "scope", .indigo) }
            }
        }
        .navigationTitle("Explore")
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) { Image(systemName: symbol).foregroundStyle(color).frame(width: 30); VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) } }
    }
}

extension View {
    func v7Panel() -> some View {
        self.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
