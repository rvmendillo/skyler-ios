import SwiftUI

struct RootV8View: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TabView {
                NavigationStack { HomeV8View() }
                    .tabItem { Label("Home", systemImage: "sparkles") }
                NavigationStack { ConnectHubV7View() }
                    .tabItem { Label("Connect", systemImage: "arrow.triangle.2.circlepath.circle.fill") }
                NavigationStack { ExploreHubV8View() }
                    .tabItem { Label("Explore", systemImage: "book.pages.fill") }
                NavigationStack { KnowledgeGraphV3View() }
                    .tabItem { Label("Graph", systemImage: "network") }
                NavigationStack { AskV8FastView() }
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right.fill") }
            }
            .tint(.cyan)
            .preferredColorScheme(.dark)

            VStack { OperationBannerV7(); Spacer() }
                .allowsHitTesting(false)

            if showSplash {
                NexusSplashV8()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
    }
}

struct NexusSplashV8: View {
    @State private var pulse = false
    @State private var progress = 0.08

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color.indigo.opacity(0.62), Color.cyan.opacity(0.14), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.cyan.opacity(0.18))
                .frame(width: 350, height: 350)
                .blur(radius: 34)
                .scaleEffect(pulse ? 1.12 : 0.86)

            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(.ultraThinMaterial)
                        .frame(width: 116, height: 116)
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.cyan)
                    Image(systemName: "bolt.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .offset(x: 31, y: 31)
                }
                .scaleEffect(pulse ? 1.04 : 0.96)

                Text("NEXUS")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .tracking(8)
                Text("\(NexusBuildInfo.versionLabel) • SHARED AI")
                    .font(.caption.bold())
                    .tracking(1.2)
                    .foregroundStyle(.cyan)
                ProgressView(value: progress)
                    .frame(width: 230)
                    .tint(.cyan)
                Text("Private • local-first • evidence-grounded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeOut(duration: 1.25)) { progress = 1 }
        }
    }
}

struct HomeV8View: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var multimodal = NexusMultimodalStore.shared
    @ObservedObject private var language = NexusPortableModelStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("NEXUS")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .tracking(7)
                        Text(NexusBuildInfo.versionLabel)
                            .font(.headline.weight(.black))
                            .foregroundStyle(.cyan)
                    }
                    Text("YOUR PERSONAL MULTIMODAL UNIVERSE")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                    Text("Chat and files default to compact retrieval and one shared resident model pass, with deeper multi-engine analysis only when you ask for it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 9) {
                    metric("Vault", "\(model.records.count)", "externaldrive.fill")
                    metric("Build", NexusBuildInfo.versionLabel, "hammer.fill")
                    metric("AI", language.activeModelID.isEmpty && multimodal.activePresetID.isEmpty ? "Ready" : "Loaded", "brain.head.profile.fill")
                }

                NavigationLink { FilesV8FastView() } label: {
                    feature("Files", "Open images, text, PDFs and CSVs; cached extraction and compact retrieval keep file questions responsive.", "folder.fill.badge.gearshape", .cyan)
                }
                .buttonStyle(.plain)

                NavigationLink { AskV8FastView() } label: {
                    feature("NEXUS Chat", "Fast conversational answers with file attachments, compact retrieval and optional Deep mode.", "bolt.bubble.fill", .mint)
                }
                .buttonStyle(.plain)

                NavigationLink { StorybookV7View() } label: {
                    feature("Living Storybook", "Animated evidence-backed chapters with narration and locally generated music.", "play.square.stack.fill", .pink)
                }
                .buttonStyle(.plain)

                NavigationLink { ConversationTwinV7View() } label: {
                    feature("Conversation Twin", "Explore a clearly labeled simulation based on imported conversational patterns.", "person.2.wave.2.fill", .orange)
                }
                .buttonStyle(.plain)

                NavigationLink { PersonalityLabV7View() } label: {
                    feature("Personality Lab", "Behavioral traits, contradictions, confidence bands and source-backed observations.", "person.crop.circle.badge.checkmark", .purple)
                }
                .buttonStyle(.plain)

                NavigationLink { PortableModelsV8View() } label: {
                    feature("Shared AI Models", "Download once and keep one primary model resident for fast reuse across Chat and Files.", "cpu.fill", .yellow)
                }
                .buttonStyle(.plain)

                if !model.importStatus.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Latest vault update", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text(model.importStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .v7Panel()
                }
            }
            .padding()
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.55)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func feature(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(color.opacity(0.16))
                    .frame(width: 58, height: 58)
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .v7Panel()
    }
}

struct ExploreHubV8View: View {
    var body: some View {
        List {
            Section("Shared AI") {
                NavigationLink { FilesV8FastView() } label: {
                    row("Files + Multimodal AI", "View images, PDFs, text and CSV; analyze them with cached extraction and fast shared AI", "folder.fill.badge.gearshape", .cyan)
                }
                NavigationLink { AskV8FastView() } label: {
                    row("NEXUS Chat", "Fast answers with compact retrieval, file attachments and optional Deep mode", "bolt.bubble.fill", .mint)
                }
                NavigationLink { PortableModelsV8View() } label: {
                    row("Shared AI Models", "One resident primary model reused across Chat and Files", "cpu.fill", .yellow)
                }
                NavigationLink { MultimodalLabV8View() } label: {
                    row("Vision Model Manager", "Local vision for images and visual PDF/page analysis", "eye.fill", .cyan)
                }
            }

            Section("Immersive") {
                NavigationLink { StorybookV7View() } label: { row("Animated Storybook", "Cartoon scenes, narration, music and evidence", "play.square.stack.fill", .pink) }
                NavigationLink { TimelineV6View() } label: { row("Life Timeline", "Searchable chronological evidence", "clock.arrow.trianglehead.counterclockwise.rotate.90", .cyan) }
                NavigationLink { ConversationTwinV7View() } label: { row("Conversation Twin", "Style simulation from imported conversations", "person.2.wave.2.fill", .orange) }
            }

            Section("Reasoning labs") {
                NavigationLink { PersonalityLabV7View() } label: { row("Personality Lab", "Traits, behavior axes, contradictions, self-voice and confidence bands", "person.crop.circle.badge.checkmark", .purple) }
                NavigationLink { LifeAnalysisV6View() } label: { row("Life Compass", "Goals, strengths, weaknesses and direction", "location.north.circle.fill", .green) }
                NavigationLink { StandardizationLabV6View() } label: { row("Universal Patterns", "Patterns standardized across unrelated sources", "point.3.connected.trianglepath.dotted", .cyan) }
                NavigationLink { AIModelLabV6View() } label: { row("AI Ensemble", "Agreement and disagreement between local engines", "brain.head.profile", .purple) }
                NavigationLink { DecisionLabV6View() } label: { row("Decision Lab", "Stress-test choices against evidence", "scale.3d", .mint) }
                NavigationLink { DiscoverV4View() } label: { row("Deep Analysis", "Comprehensive evidence and uncertainty", "scope", .indigo) }
            }

            Section("Advanced Systems") {
                NavigationLink { AskV9View() } label: { row("Universal AI Memory", "The newer V9 assistant with hybrid retrieval, citations and projects", "brain.head.profile.fill", .cyan) }
                NavigationLink { NexusV9GlobalSearchView() } label: { row("Semantic Search", "Search across local records, files and memory", "magnifyingglass.circle.fill", .mint) }
                NavigationLink { NexusV9FilesHubView() } label: { row("File Intelligence", "New file library, capture, compare and research tools", "folder.badge.gearshape", .blue) }
                NavigationLink { NexusV9InsightInboxView() } label: { row("Insight Inbox", "Evidence-backed discoveries, provenance and change detection", "lightbulb.max.fill", .yellow) }
                NavigationLink { NexusProductivityHubView() } label: { row("Productivity Hub", "Pins, recents, tags, data health, backup and maintenance", "bolt.horizontal.circle.fill", .green) }
                NavigationLink { NexusV9DashboardView() } label: { row("Dashboards & Mini Apps", "Generated trackers, timelines, calculators and comparisons", "rectangle.3.group.fill", .purple) }
                NavigationLink { NexusV9MoreView() } label: { row("All New Systems", "Automation, agent actions, voice, privacy, storage, exports and platform tools", "square.grid.3x3.fill", .orange) }
            }
        }
        .navigationTitle("Explore")
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
