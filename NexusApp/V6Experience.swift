import SwiftUI

struct RootV6View: View {
    var body: some View {
        TabView {
            NavigationStack { HomeV6View() }
                .tabItem { Label("Home", systemImage: "sparkles") }
            NavigationStack { ConnectHubV6View() }
                .tabItem { Label("Connect", systemImage: "point.3.connected.trianglepath.dotted") }
            NavigationStack { ExploreHubV6View() }
                .tabItem { Label("Explore", systemImage: "book.pages.fill") }
            NavigationStack { KnowledgeGraphV3View() }
                .tabItem { Label("Graph", systemImage: "network") }
            NavigationStack { AskV6View() }
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right.fill") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
}

struct HomeV6View: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        let life = model.lifeAnalysis
        let standardized = model.standardizedReport
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NEXUS").font(.system(size: 42, weight: .black, design: .rounded)).tracking(7)
                    Text("PERSONAL UNIVERSE • LOCAL-FIRST").font(.caption.bold()).foregroundStyle(.cyan)
                    Text("One evidence model for your data, patterns, story, goals and direction.").foregroundStyle(.secondary)
                }

                HStack(spacing: 9) {
                    metric("Records", "\(model.records.count)", "doc.text.magnifyingglass")
                    metric("Signals", "\(standardized.signalCount)", "waveform.path.ecg")
                    metric("Quality", "\(Int(life.evidenceQuality*100))%", "checkmark.shield.fill")
                }

                NavigationLink { LifeAnalysisV6View() } label: {
                    premiumHero("Life Compass", life.overall, "location.north.circle.fill")
                }.buttonStyle(.plain)

                NavigationLink { ExploreHubV6View(start: .storybook) } label: {
                    premiumHero("Living Storybook", "Turn real timeline evidence into colorful, narrated chapters without inventing life events.", "book.pages.fill")
                }.buttonStyle(.plain)

                NavigationLink { StandardizationLabV6View() } label: {
                    premiumHero("Universal Patterns", "See what remains consistent after Instagram, messages, calendar, files and other sources are standardized into the same signal language.", "point.3.filled.connected.trianglepath.dotted")
                }.buttonStyle(.plain)

                NavigationLink { AIModelLabV6View() } label: {
                    premiumHero("Local AI Ensemble", "Inspect agreement and disagreement among Apple Intelligence, embeddings, sentiment, entities, statistical patterns and cross-source consensus.", "cpu.fill")
                }.buttonStyle(.plain)

                if let direction = life.recommendedDirections.first {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Current evidence-backed direction", systemImage: "arrow.up.right.circle.fill").font(.headline).foregroundStyle(.cyan)
                        Text(direction.title).font(.title3.bold())
                        Text(direction.summary).font(.subheadline).foregroundStyle(.secondary)
                        HStack { Text("Confidence"); Spacer(); Text("\(Int(direction.confidence*100))%") }.font(.caption)
                        ProgressView(value: direction.confidence)
                    }.v6Panel()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("No API keys for AI", systemImage: "lock.shield.fill").font(.headline)
                    Text("The analysis stack uses on-device/system models and deterministic local engines. Apple Intelligence is used when available; otherwise NEXUS still works locally.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.v6Panel()
            }.padding()
        }
    }

    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Image(systemName: symbol).foregroundStyle(.cyan); Text(value).font(.headline).minimumScaleFactor(0.6); Text(label).font(.caption2).foregroundStyle(.secondary) }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func premiumHero(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 14) {
            ZStack { RoundedRectangle(cornerRadius: 18).fill(.cyan.opacity(0.15)).frame(width: 58, height: 58); Image(systemName: symbol).font(.title2).foregroundStyle(.cyan) }
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.v6Panel()
    }
}

enum ExploreV6Mode: String, CaseIterable, Identifiable { case timeline = "Timeline", storybook = "Storybook", labs = "Labs"; var id: String { rawValue } }

struct ExploreHubV6View: View {
    @State private var mode: ExploreV6Mode
    init(start: ExploreV6Mode = .timeline) { _mode = State(initialValue: start) }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Explore", selection: $mode) { ForEach(ExploreV6Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding()
            switch mode {
            case .timeline: TimelineV6View()
            case .storybook: StorybookV6View()
            case .labs: ExplorationLabsV6View()
            }
        }.navigationTitle("Explore").navigationBarTitleDisplayMode(.inline)
    }
}

struct TimelineV6View: View {
    @EnvironmentObject var model: NexusModel
    @State private var query = ""
    @State private var year: Int? = nil
    @State private var kind: KnowledgeRecord.Kind? = nil
    @State private var selected: KnowledgeRecord?

    var body: some View {
        let buckets = model.journeyTimelineBuckets(year: year, query: query, kind: kind)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Text("Life timeline").font(.title2.bold()); Spacer(); Menu { Button("All types") { kind = nil }; ForEach(KnowledgeRecord.Kind.allCases, id: \.self) { item in Button(item.rawValue.capitalized) { kind = item } } } label: { Label(kind?.rawValue.capitalized ?? "All", systemImage: "line.3.horizontal.decrease.circle") } }
                    TextField("Search events, people, topics…", text: $query).textFieldStyle(.roundedBorder)
                    ScrollView(.horizontal, showsIndicators: false) { HStack { chip("All", active: year == nil) { year = nil }; ForEach(model.journeyYears, id: \.self) { y in chip(String(y), active: year == y) { year = y } } } }
                }.v6Panel()

                if buckets.isEmpty { ContentUnavailableView("No matching timeline evidence", systemImage: "clock.badge.questionmark") }
                ForEach(buckets) { bucket in
                    VStack(alignment: .leading, spacing: 2) { Text(bucket.title).font(.title3.bold()); Text(bucket.subtitle).font(.caption).foregroundStyle(.secondary) }.padding(.top, 6)
                    ForEach(Array(bucket.records.prefix(180))) { record in
                        Button { selected = record } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Circle().fill(.cyan).frame(width: 8, height: 8).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(record.kind.rawValue.capitalized).font(.caption.bold()).foregroundStyle(.cyan); Spacer(); Text(record.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "").font(.caption2).foregroundStyle(.tertiary) }
                                    Text(record.title.isEmpty ? record.source : record.title).font(.subheadline.bold()).lineLimit(1)
                                    if !record.text.isEmpty { Text(record.text).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                }
                            }.padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding()
        }.sheet(item: $selected) { record in NavigationStack { List { Section { Text(record.text.isEmpty ? record.title : record.text) }; Section("Provenance") { LabeledContent("Source", value: record.source); LabeledContent("Type", value: record.kind.rawValue.capitalized); if let d = record.timestamp { LabeledContent("Date", value: d.formatted(date: .long, time: .standard)) } } }.navigationTitle("Evidence") } }
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(.caption.bold()).padding(.horizontal, 11).padding(.vertical, 7) }.buttonStyle(.plain).background(active ? Color.cyan.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
    }
}

struct StorybookV6View: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var narrator = NexusStoryNarrator()
    @State private var mode: JourneyStoryMode = .journey
    @State private var index = 0
    @State private var rewrites: [String:String] = [:]
    @State private var busy = false

    var body: some View {
        let pages = model.storyPages(mode: mode)
        ScrollView {
            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(JourneyStoryMode.allCases) { item in Button { mode = item; index = 0; narrator.stop() } label: { Label(item.rawValue, systemImage: item.symbol).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 7) }.buttonStyle(.plain).background(mode == item ? Color.cyan.opacity(0.23) : Color.secondary.opacity(0.10), in: Capsule()) } } }.padding(.horizontal)
                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                        V6StoryCard(page: page, storyText: rewrites[page.id] ?? page.body).padding(.horizontal).tag(i)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .always)).frame(height: 480)
                if pages.indices.contains(index) {
                    let page = pages[index]
                    HStack {
                        Button { narrator.isSpeaking ? narrator.stop() : narrator.speak(rewrites[page.id] ?? page.body) } label: { Label(narrator.isSpeaking ? "Stop" : "Read aloud", systemImage: narrator.isSpeaking ? "stop.fill" : "speaker.wave.2.fill") }.buttonStyle(.borderedProminent)
                        if NexusIntelligenceEngine.appleIntelligenceAvailable {
                            Button { rewrite(page) } label: { Group { if busy { ProgressView().controlSize(.small) } else { Label("Magic", systemImage: "apple.intelligence") } } }.buttonStyle(.bordered).disabled(busy)
                        }
                    }
                    DisclosureGroup("Evidence • \(page.evidence.count)") { ForEach(page.evidence, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) } }.font(.caption.bold()).tint(.cyan).padding(.horizontal)
                }
            }.padding(.vertical)
        }
    }

    private func rewrite(_ page: NexusStoryPage) {
        busy = true
        Task {
            let context = ([page.body] + page.evidence).joined(separator: "\n")
            let result = await NexusIntelligenceEngine.respond(question: "Rewrite this evidence-backed personal-memory page in a warm, playful, colorful children's-TV-inspired tone for an adult reader. Preserve facts exactly; invent no events, motives or relationships.", context: context)
            if let result { rewrites[page.id] = result }
            busy = false
        }
    }
}

struct V6StoryCard: View {
    let page: NexusStoryPage
    let storyText: String
    private let palettes: [[Color]] = [[.blue,.cyan],[.purple,.pink],[.orange,.pink],[.green,.teal],[.indigo,.purple],[.mint,.blue]]
    var body: some View {
        let colors = palettes[abs(page.accentIndex) % palettes.count]
        ZStack {
            RoundedRectangle(cornerRadius: 32).fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.12)).frame(width: 170).offset(x: 130, y: -160)
            VStack(alignment: .leading, spacing: 13) {
                HStack { Image(systemName: page.symbol).font(.system(size: 40, weight: .bold)); Spacer(); Image(systemName: "sparkles") }.foregroundStyle(.white)
                Spacer()
                Text(page.subtitle.uppercased()).font(.caption.bold()).tracking(1.2).foregroundStyle(.white.opacity(0.78))
                Text(page.title).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(.white)
                ScrollView { Text(storyText).font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.95)).frame(maxWidth: .infinity, alignment: .leading) }.scrollIndicators(.hidden)
                HStack { Label("Evidence-backed", systemImage: "checkmark.shield.fill"); Spacer(); Text("\(page.evidence.count) traces") }.font(.caption.bold()).foregroundStyle(.white.opacity(0.82))
            }.padding(25)
        }.shadow(radius: 13, y: 7)
    }
}

struct ExplorationLabsV6View: View {
    var body: some View {
        List {
            NavigationLink { LifeAnalysisV6View() } label: { lab("Life Compass", "Goals, strengths, constraints, tensions and directions", "location.north.circle.fill") }
            NavigationLink { StandardizationLabV6View() } label: { lab("Universal Pattern Lab", "What survives normalization across unrelated data sources", "point.3.connected.trianglepath.dotted") }
            NavigationLink { AIModelLabV6View() } label: { lab("Local AI Ensemble", "Compare local model opinions and disagreement", "cpu.fill") }
            NavigationLink { DecisionLabV6View() } label: { lab("Decision Lab", "Stress-test a choice against the evidence-backed life model", "scale.3d") }
            NavigationLink { DiscoverV4View() } label: { lab("Analysis Lab", "Source bias, timeline coverage and comprehensive behavioral analysis", "scope") }
        }
    }
    private func lab(_ title: String, _ subtitle: String, _ symbol: String) -> some View { HStack(spacing: 12) { Image(systemName: symbol).foregroundStyle(.cyan).frame(width: 30); VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) } } }
}

struct LifeAnalysisV6View: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        let report = model.lifeAnalysis
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Life Compass", systemImage: "location.north.circle.fill").font(.largeTitle.bold()).foregroundStyle(.cyan)
                    Text(report.overall).foregroundStyle(.secondary)
                    HStack { Text("Evidence quality"); Spacer(); Text("\(Int(report.evidenceQuality*100))%") }.font(.caption.bold())
                    ProgressView(value: report.evidenceQuality)
                }.v6Panel()

                dimensionSection(report.dimensions)
                findings("Strengths", "What repeated evidence supports", "bolt.fill", report.strengths)
                findings("Constraints / weaknesses", "Data-backed friction or under-supported areas—not character judgments", "exclamationmark.triangle.fill", report.weaknesses)
                findings("Inferred overall goals", "Hypotheses from sustained attention, planning and recurring behavior", "target", report.inferredGoals)
                findings("Recommended direction", "Fit + optionality + cross-source consistency", "arrow.up.right.circle.fill", report.recommendedDirections)
                findings("Tensions to manage", "Strong priorities that can compete for time/resources", "arrow.left.arrow.right", report.tensions)
                findings("Blind spots", "Where NEXUS knows its evidence is weak", "eye.slash.fill", report.blindSpots)

                VStack(alignment: .leading, spacing: 8) { Text("Rationality rules").font(.headline); ForEach(report.principles, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) } }.v6Panel()
            }.padding()
        }.navigationTitle("Life Analysis").navigationBarTitleDisplayMode(.inline)
    }

    private func dimensionSection(_ values: [NexusLifeDimension]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Life-domain evidence map").font(.headline)
            ForEach(values) { d in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(d.name).font(.subheadline.bold()); Spacer(); Text("\(Int(d.score*100))").font(.caption.bold()).foregroundStyle(.cyan) }
                    ProgressView(value: d.score)
                    HStack { Text("\(d.trend) • \(d.sourceBreadth) sources • \(d.evidenceCount) signals"); Spacer(); Text("conf \(Int(d.confidence*100))%") }.font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.v6Panel()
    }

    private func findings(_ title: String, _ subtitle: String, _ symbol: String, _ values: [NexusLifeFinding]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            if values.isEmpty { Text("Insufficient evidence.").font(.subheadline).foregroundStyle(.tertiary) }
            ForEach(values) { item in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.summary).font(.subheadline)
                        if !item.rationale.isEmpty { Text("Evidence").font(.caption.bold()).foregroundStyle(.cyan); ForEach(item.rationale, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) } }
                        if !item.alternatives.isEmpty { Text("Alternative interpretation").font(.caption.bold()).foregroundStyle(.orange); ForEach(item.alternatives, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) } }
                    }.padding(.top, 5)
                } label: { HStack { VStack(alignment: .leading) { Text(item.title).font(.subheadline.bold()); Text("confidence \(Int(item.confidence*100))%").font(.caption2).foregroundStyle(.secondary) }; Spacer() } }
            }
        }.v6Panel()
    }
}

struct StandardizationLabV6View: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        let report = model.standardizedReport
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) { Text("Universal Pattern Lab").font(.largeTitle.bold()); Text("NEXUS converts every source into a common signal vocabulary: subject, action, topic, time, entity, place, provenance and evidence quality.").foregroundStyle(.secondary) }.v6Panel()
                HStack { stat("Signals", report.signalCount); stat("Sources", report.sourceCount); stat("Dated", report.datedSignalCount) }
                VStack(alignment: .leading, spacing: 8) { Text("Common action families").font(.headline); ForEach(report.dominantActions.prefix(8)) { item in HStack { Text(item.label); Spacer(); Text("\(item.count)").foregroundStyle(.secondary) } } }.v6Panel()
                VStack(alignment: .leading, spacing: 9) {
                    Text("Patterns that generalize best").font(.headline)
                    if report.universalCharacteristics.isEmpty { Text("Connect more independent sources to discover cross-context characteristics.").foregroundStyle(.secondary) }
                    ForEach(report.universalCharacteristics) { pattern in
                        DisclosureGroup { Text(pattern.summary).font(.subheadline); ForEach(pattern.evidence, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) } } label: {
                            VStack(alignment: .leading) { HStack { Text(pattern.label).font(.subheadline.bold()); Spacer(); Text("\(Int(pattern.score*100))%").font(.caption).foregroundStyle(.cyan) }; Text("\(pattern.kind.rawValue) • \(pattern.sourceBreadth) sources • ~\(pattern.timeSpanDays)d").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }.v6Panel()
                VStack(alignment: .leading, spacing: 6) { Text("Interpretation limits").font(.headline); ForEach(report.caveats, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) } }.v6Panel()
            }.padding()
        }.navigationTitle("Patterns").navigationBarTitleDisplayMode(.inline)
    }
    private func stat(_ label: String, _ value: Int) -> some View { VStack { Text("\(value)").font(.headline); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17)) }
}

struct AIModelLabV6View: View {
    @EnvironmentObject var model: NexusModel
    @State private var result: NexusEnsembleResult?
    @State private var running = false

    var body: some View {
        List {
            Section("API-key-free model stack") {
                modelRow("Apple Foundation Model", NexusIntelligenceEngine.appleIntelligenceAvailable ? "Available • on-device" : "Unavailable on this device/settings", "apple.intelligence")
                modelRow("Apple Sentence Embeddings", "System Natural Language model", "text.magnifyingglass")
                modelRow("Apple Sentiment Model", "System Natural Language model", "face.smiling")
                modelRow("Apple Entity Tagger", "System Natural Language model", "person.text.rectangle")
                modelRow("NEXUS Statistical Pattern Model", "Local deterministic model", "chart.xyaxis.line")
                modelRow("NEXUS Cross-source Consensus", "Local agreement + evidence model", "checkmark.seal.fill")
            }
            Section("Consensus audit") {
                Button { audit() } label: { Label(running ? "Running local ensemble…" : "Audit my current life analysis", systemImage: "cpu") }.disabled(running || model.records.isEmpty)
                if let result {
                    LabeledContent("Consensus", value: "\(Int(result.consensus*100))%")
                    ForEach(result.opinions) { opinion in
                        DisclosureGroup { Text(opinion.finding).font(.subheadline); ForEach(opinion.evidence, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) } } label: { VStack(alignment: .leading) { Text(opinion.model).font(.subheadline.bold()); Text("\(opinion.role) • \(Int(opinion.confidence*100))%").font(.caption2).foregroundStyle(.secondary) } }
                    }
                    if !result.disagreements.isEmpty { DisclosureGroup("Disagreements / weak signals") { ForEach(result.disagreements, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.orange) } } }
                }
            }
            Section { Text("These local models are intentionally different. Agreement increases confidence; disagreement lowers it. NEXUS does not treat several outputs from the same model as independent evidence.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Local AI Ensemble")
    }

    private func audit() {
        running = true
        Task {
            let q = "What are my strongest life patterns, goals, strengths, constraints and most rational next direction?"
            let package = NexusReasoner.package(question: q, records: model.records, overallSummary: model.comprehensiveReport.overall, personality: model.v3Personality)
            result = await NexusLocalEnsemble.analyze(question: q, records: model.records, base: package, life: model.lifeAnalysis, standardized: model.standardizedReport)
            running = false
        }
    }
    private func modelRow(_ title: String, _ subtitle: String, _ symbol: String) -> some View { HStack { Image(systemName: symbol).foregroundStyle(.cyan).frame(width: 28); VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) } } }
}

struct DecisionLabV6View: View {
    @EnvironmentObject var model: NexusModel
    @State private var optionA = ""
    @State private var optionB = ""
    var body: some View {
        let dimensions = model.lifeAnalysis.dimensions.prefix(6)
        Form {
            Section("Compare two directions") { TextField("Option A", text: $optionA); TextField("Option B", text: $optionB); Text("NEXUS won't pretend to know utility it cannot observe. This lab shows which current evidence-backed domains each option appears to align with, then leaves the decision to you.").font(.caption).foregroundStyle(.secondary) }
            if !optionA.isEmpty || !optionB.isEmpty {
                Section("Current priorities to test against") { ForEach(Array(dimensions)) { d in LabeledContent(d.name, value: "\(Int(d.score*100)) / conf \(Int(d.confidence*100))%") } }
                Section("Prompts for rational comparison") {
                    Text("• Which option strengthens your top two persistent domains rather than only a recent spike?")
                    Text("• Which preserves more future options if your current assumptions are wrong?")
                    Text("• Which addresses a real constraint instead of merely adding novelty?")
                    Text("• What evidence would falsify your preference for either option?")
                }.font(.subheadline)
            }
        }.navigationTitle("Decision Lab")
    }
}

struct AskV6View: View {
    @EnvironmentObject var model: NexusModel
    @State private var draft = ""
    @State private var thinking = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "cpu.fill"); Text("Local ensemble • no API key").font(.caption.bold()); Spacer(); if thinking { ProgressView().controlSize(.small) } }.foregroundStyle(.cyan).padding(.horizontal).padding(.vertical, 8).background(.thinMaterial)
            ScrollViewReader { proxy in
                ScrollView { LazyVStack(spacing: 11) { ForEach(model.chatMessages) { message in VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) { Text(message.text).textSelection(.enabled).padding(12).background(message.role == .user ? Color.cyan.opacity(0.22) : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16)).frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading); if !message.evidence.isEmpty { DisclosureGroup("Evidence / model audit • \(message.evidence.count)") { ForEach(message.evidence, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) } }.font(.caption.bold()).tint(.cyan) } }.id(message.id) }; if thinking { HStack { ProgressView(); Text("Running local ensemble…").font(.caption).foregroundStyle(.secondary); Spacer() } } }.padding() }.onChange(of: model.chatMessages.count) { _, _ in if let id = model.chatMessages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) { TextField("Ask about life direction, goals, patterns…", text: $draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder).focused($focused).onSubmit { send() }; Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(thinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding().background(.bar)
        }.navigationTitle("Personal AI").toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("Life analysis") { prompt("Analyze my life direction, goals, strengths and constraints rationally from the data.") }; Button("Find universal patterns") { prompt("What patterns remain after standardizing all my data sources?") }; Button("Challenge your conclusion") { prompt("Give the strongest alternative interpretations and contradictions to your current model of me.") }; Button("What should I prioritize?") { prompt("What should I prioritize next, based only on repeated evidence and explicit uncertainty?") }; Divider(); Button("Clear chat", role: .destructive) { model.clearChat() } } label: { Image(systemName: "ellipsis.circle") } } }
    }
    private func prompt(_ value: String) { draft = value; send() }
    private func send() { let text = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty, !thinking else { return }; draft = ""; thinking = true; focused = false; Task { await model.askV6(text); thinking = false; focused = true } }
}

private extension View {
    func v6Panel() -> some View { self.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20)) }
}
