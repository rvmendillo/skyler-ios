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
                NavigationStack { AskV7View() }
                    .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right.fill") }
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
                    Image(systemName: "eye.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .offset(x: 31, y: 31)
                }
                .scaleEffect(pulse ? 1.04 : 0.96)

                Text("NEXUS")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .tracking(8)
                Text("V8 • LOCAL MULTIMODAL INTELLIGENCE")
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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("NEXUS")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .tracking(7)
                        Text("V8")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.cyan)
                    }
                    Text("YOUR PERSONAL MULTIMODAL UNIVERSE")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                    Text("Text, conversations, files, images and PDFs can now converge inside the same private local-first knowledge system.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 9) {
                    metric("Vault", "\(model.records.count)", "externaldrive.fill")
                    metric("Build", "V8", "hammer.fill")
                    metric("Vision", multimodal.activePresetID.isEmpty ? "Ready" : "Loaded", "eye.fill")
                }

                NavigationLink { MultimodalLabV8View() } label: {
                    feature("Multimodal Files", "Analyze images, PDFs, text/code and system-renderable files with optional local vision-language models.", "eye.trianglebadge.exclamationmark.fill", .cyan)
                }
                .buttonStyle(.plain)

                NavigationLink { AskV7View() } label: {
                    feature("Ask NEXUS", "Ask questions across the personal vault with evidence-grounded answers.", "bubble.left.and.text.bubble.right.fill", .mint)
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

                NavigationLink { PortableModelsV7View() } label: {
                    feature("Portable Local LLMs", "Download and run optional GGUF language models directly on iPhone.", "cpu.fill", .yellow)
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
            Section("V8 multimodal") {
                NavigationLink { MultimodalLabV8View() } label: {
                    row("Multimodal Files", "Local vision for images and rendered pages, PDF text + visuals, text/code extraction and safe fallbacks", "eye.fill", .cyan)
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
                NavigationLink { PortableModelsV7View() } label: { row("Portable GGUF LLMs", "Optional llama.cpp models on iPhone", "cpu.fill", .yellow) }
                NavigationLink { DecisionLabV6View() } label: { row("Decision Lab", "Stress-test choices against evidence", "scale.3d", .mint) }
                NavigationLink { DiscoverV4View() } label: { row("Deep Analysis", "Comprehensive evidence and uncertainty", "scope", .indigo) }
            }
        }
        .navigationTitle("Explore V8")
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
