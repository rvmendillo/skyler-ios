import SwiftUI

struct NexusAdvancedHubView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Advanced NEXUS")
                        .font(.title2.weight(.bold))
                    Text("The strongest newer systems live here so the classic Home / Connect / Explore / Graph / Chat experience stays familiar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Data & Portability") {
                NavigationLink { ConnectHubV7View() } label: {
                    row("Imports & Connectors", "Meta exports, files, extracted folders, native device connectors and OAuth/export sources", "arrow.down.doc.fill", .cyan)
                }
                NavigationLink { NexusV9BackupView() } label: {
                    row("Backup & Restore", "Create a portable validated NEXUS backup and non-destructively restore it later", "externaldrive.badge.timemachine", .green)
                }
                NavigationLink { NexusV9ExportView() } label: {
                    row("Export & Intelligence Package", "Export reports and portable intelligence output from your NEXUS data", "square.and.arrow.up.fill", .mint)
                }
                NavigationLink { FilesV8FastView() } label: {
                    row("Files", "Import once and keep files inside NEXUS for reuse", "folder.fill", .blue)
                }
                NavigationLink { NexusAnalyzedLibraryView() } label: {
                    row("Analyzed Library", "Cached multimodal analysis for every imported file without selecting each file again", "sparkles.rectangle.stack.fill", .purple)
                }
            }

            Section("Intelligence") {
                NavigationLink { AskV9View() } label: {
                    row("Universal AI Memory", "Hybrid local retrieval, evidence citations, projects and deeper memory reasoning", "brain.head.profile.fill", .cyan)
                }
                NavigationLink { NexusV9GlobalSearchView() } label: {
                    row("Semantic Search", "Search records, files and memory using semantic + keyword retrieval", "magnifyingglass.circle.fill", .mint)
                }
                NavigationLink { NexusV9InsightInboxView() } label: {
                    row("Insight Inbox", "Evidence-backed discoveries, provenance and evolving insights", "lightbulb.max.fill", .yellow)
                }
                NavigationLink { NexusV9WorkspacesView() } label: {
                    row("Projects & Conversation Branches", "Organize files, memory and conversations into focused workspaces", "square.stack.3d.up.fill", .orange)
                }
                NavigationLink { NexusV9Graph2View() } label: {
                    row("Knowledge Graph 2.0", "Explore entities and relationships across your local knowledge", "network", .cyan)
                }
                NavigationLink { NexusV9Timeline2View() } label: {
                    row("Universal Timeline", "Chronological evidence and events across sources", "clock.fill", .blue)
                }
                NavigationLink { NexusV9ChangeDetectionView() } label: {
                    row("Personal Change Detection", "Surface meaningful changes and evolving patterns over time", "waveform.path.ecg.rectangle.fill", .pink)
                }
                NavigationLink { NexusV9DashboardView() } label: {
                    row("Dashboards & Mini Apps", "Generate trackers, timelines, calculators, quizzes and comparisons", "rectangle.3.group.fill", .purple)
                }
            }

            Section("Files & Productivity") {
                NavigationLink { NexusV9FilesHubView() } label: {
                    row("File Intelligence", "Compare files, watch folders, capture photos/documents and research", "folder.badge.gearshape", .blue)
                }
                NavigationLink { NexusProductivityHubView() } label: {
                    row("Productivity Hub", "Favorites, recents, tags, data health and maintenance", "bolt.horizontal.circle.fill", .green)
                }
            }

            Section("Automation & Actions") {
                NavigationLink { NexusV9AutomationsView() } label: {
                    row("Natural-language Automations", "Create local rules that react to NEXUS events", "gearshape.2.fill", .orange)
                }
                NavigationLink { NexusV9AgentView() } label: {
                    row("Local Agent Actions", "Organize and act on local data with undo-aware actions", "wand.and.stars.inverse", .mint)
                }
            }

            Section("AI Models & Multimodal") {
                NavigationLink { SharedModelsV8EnhancedView() } label: {
                    row("Shared AI Models", "Download, load, cross-check, delete downloads or delete models", "cpu.fill", .yellow)
                }
                NavigationLink { MultimodalLabV8View() } label: {
                    row("Vision Model Manager", "Manage local multimodal models for images, scans and document pages", "eye.fill", .cyan)
                }
                NavigationLink { NexusV9VoiceView() } label: {
                    row("Voice Conversation", "Talk with NEXUS using the newer voice experience", "mic.fill", .pink)
                }
            }

            Section("Privacy & System") {
                NavigationLink { NexusV9SecurityView() } label: {
                    row("Privacy & Security", "Review local-first privacy and security controls", "lock.shield.fill", .green)
                }
                NavigationLink { NexusV9StorageView() } label: {
                    row("Storage Manager", "Inspect and manage local NEXUS storage", "internaldrive.fill", .blue)
                }
                NavigationLink { NexusV9PerformanceView() } label: {
                    row("Performance & Diagnostics", "Benchmark and inspect the newer runtime systems", "gauge.with.dots.needle.67percent", .orange)
                }
                NavigationLink { NexusV9MoreView() } label: {
                    row("All New Systems", "Open the complete V9 systems directory", "square.grid.3x3.fill", .secondary)
                }
            }
        }
        .navigationTitle("Advanced")
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SharedModelsV8EnhancedView: View {
    @ObservedObject private var store = NexusPortableModelStore.shared
    @State private var picker = false
    @State private var deleteTarget: NexusPortableModel?

    var body: some View {
        List {
            Section {
                Text("Shared language models are reused by Chat, Files and NEXUS intelligence. Model storage can now be removed directly from this page.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(store.memorySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if store.busy || store.progress > 0 {
                    ProgressView(value: store.progress) {
                        Text(store.status).font(.caption)
                    }
                    if store.downloadSnapshot.totalBytes > 0 {
                        Text(store.downloadSnapshot.detailText)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
                if !store.lastError.isEmpty {
                    Text(store.lastError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Verified presets") {
                ForEach(NexusPortableModelStore.v8VerifiedPresets) { preset in
                    presetRow(preset)
                }
            }

            Section("Your models") {
                Button { picker = true } label: {
                    Label("Import GGUF from Files", systemImage: "square.and.arrow.down")
                }
                ForEach(store.models) { model in
                    modelRow(model)
                }
            }

            Section("Storage behavior") {
                Text("Delete download removes downloaded preset weights but keeps the model in your catalog. Delete model removes the model from your catalog and deletes its local weights/file. Verified presets remain available above so you can add them again later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Shared AI Models")
        .sheet(isPresented: $picker) {
            NexusGGUFDocumentPicker { url in
                picker = false
                Task { await store.importGGUF(url) }
            }
        }
        .confirmationDialog(
            deleteTarget.map { "Delete \($0.name)?" } ?? "Delete model?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = deleteTarget {
                Button("Delete model and local file", role: .destructive) {
                    store.delete(target)
                    deleteTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This removes the model from NEXUS and deletes its locally stored weights. Verified presets can be added and downloaded again later.")
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: NexusPortableModel) -> some View {
        let existing = store.models.first(where: { $0.id == preset.id })
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).font(.headline)
                    Text("\(preset.approximateSize) • \(preset.source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let model = existing, store.activeModelID == model.id {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let model = existing, store.isDownloaded(model) {
                    Label("On device", systemImage: "internaldrive.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let model = existing {
                HStack {
                    if !store.isDownloaded(model) {
                        Button("Download") { Task { await store.download(model) } }
                            .buttonStyle(.bordered)
                            .disabled(store.busy)
                    }
                    Button(store.activeModelID == model.id ? "Reload" : "Load") {
                        Task { await store.load(model) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.busy)
                    Button(model.enabledForEnsemble ? "Cross-check on" : "Cross-check off") {
                        store.toggleEnsemble(model)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.busy)
                }

                HStack {
                    if store.isDownloaded(model) {
                        Button(role: .destructive) {
                            store.removeDownloadedWeights(model)
                        } label: {
                            Label("Delete download", systemImage: "internaldrive.badge.minus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.busy)
                    }
                    Button(role: .destructive) {
                        deleteTarget = model
                    } label: {
                        Label("Delete model", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.busy)
                }
            } else {
                Button("Add model") { store.addPreset(preset) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func modelRow(_ model: NexusPortableModel) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.headline)
                    Text("\(model.approximateSize) • \(model.source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.activeModelID == model.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if store.isDownloaded(model) {
                    Image(systemName: "internaldrive.fill").foregroundStyle(.secondary)
                }
            }

            HStack {
                if model.isPreset && !store.isDownloaded(model) {
                    Button("Download") { Task { await store.download(model) } }
                        .buttonStyle(.bordered)
                        .disabled(store.busy)
                }
                Button(store.activeModelID == model.id ? "Reload" : "Load") {
                    Task { await store.load(model) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.busy)
                Button(model.enabledForEnsemble ? "Cross-check on" : "Cross-check off") {
                    store.toggleEnsemble(model)
                }
                .buttonStyle(.bordered)
                .disabled(store.busy)
            }

            HStack {
                if model.isPreset && store.isDownloaded(model) {
                    Button(role: .destructive) {
                        store.removeDownloadedWeights(model)
                    } label: {
                        Label("Delete download", systemImage: "internaldrive.badge.minus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.busy)
                }
                Button(role: .destructive) {
                    deleteTarget = model
                } label: {
                    Label("Delete model", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(store.busy)
            }
        }
        .padding(.vertical, 3)
    }
}
