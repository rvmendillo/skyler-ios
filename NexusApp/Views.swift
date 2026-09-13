import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "sparkles") }
            NavigationStack { ConnectionsView() }.tabItem { Label("Connect", systemImage: "point.3.connected.trianglepath.dotted") }
            NavigationStack { AnalysisView() }.tabItem { Label("Analysis", systemImage: "waveform.path.ecg.rectangle") }
            NavigationStack { KnowledgeGraphView() }.tabItem { Label("Graph", systemImage: "point.3.filled.connected.trianglepath.dotted") }
            NavigationStack { AskView() }.tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right.fill") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
}

struct HomeView: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEXUS").font(.system(size: 38, weight: .black, design: .rounded)).tracking(8)
                    Text("YOUR LIFE. CONNECTED. INTELLIGENT.").font(.caption.bold()).foregroundStyle(.cyan)
                    Text("A local-first personal knowledge system that connects your authorized data, discovers recurring patterns and keeps the evidence behind every inference.").foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                HStack {
                    metric("Records", "\(model.records.count)")
                    metric("Sources", "\(Set(model.records.map(\.source)).count)")
                    metric("Graph", "\(model.knowledgeGraph.nodes.count) nodes")
                }

                card("Overall model") {
                    Text(model.overallSummary).foregroundStyle(.secondary)
                }

                card("What NEXUS can discover") {
                    Text("Interests • emerging topics • people • relationships • communication style • activity footprint • routines • temporal patterns • places • media • learning • finance • technology • music • travel • health • creativity • long-term change")
                        .foregroundStyle(.secondary)
                }

                card("Privacy & evidence") {
                    Label("Your normalized vault stays on-device. Analysis is deterministic and evidence-linked; NEXUS does not pretend an inference is a fact.", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)
                }

                if let first = model.activityLog.first {
                    card("Latest") { Text(first) }
                }
            }
            .padding()
        }
        .navigationTitle("")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.headline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ConnectionsView: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var hub = DeviceConnectorHub()
    @State private var importing = false
    @State private var target = "Imported Files"
    @State private var busy = ""
    @State private var importBusy = false
    @State private var showImportResult = false

    private var importTypes: [UTType] {
        [
            UTType(filenameExtension: "zip") ?? .data,
            .json,
            .plainText,
            .commaSeparatedText,
            .html,
            .xml,
            .folder
        ]
    }

    var body: some View {
        List {
            if !model.importStatus.isEmpty {
                Section {
                    Label(model.importStatus, systemImage: model.importStatus.lowercased().contains("imported") ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(model.importStatus.lowercased().contains("imported") ? .green : .secondary)
                }
            }

            Section("Data sources") {
                ForEach(model.connectors) { c in
                    HStack(spacing: 14) {
                        Image(systemName: c.symbol).frame(width: 30).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.name).font(.headline)
                            Text(c.detail).font(.caption).foregroundStyle(.secondary)
                            Text(c.status).font(.caption2).foregroundStyle(c.status.contains("Connected") || c.status.contains("records") ? .green : .secondary)
                        }
                        Spacer()
                        if c.mode == .native {
                            Button(busy == c.id ? "…" : "Connect") {
                                busy = c.id
                                hub.connect(c.id) { records, status in
                                    if !records.isEmpty { model.merge(records, sourceName: c.name) }
                                    model.setStatus(id: c.id, status: records.isEmpty ? "No accessible data" : status)
                                    busy = ""
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!busy.isEmpty || importBusy)
                        } else if c.mode == .archive {
                            Button("Import") {
                                target = c.name
                                importing = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(importBusy)
                        } else {
                            Text("Needs OAuth").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("How import works") {
                Text("Choose the original exported ZIP/JSON file from Meta, or select text/CSV/HTML/XML files. NEXUS parses supported files immediately after selection. You can select multiple files at once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connections")
        .overlay {
            if importBusy {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Importing and indexing…").font(.headline)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let error):
                model.reportImportError("Import picker failed: \(error.localizedDescription)")
            case .success(let urls):
                guard !urls.isEmpty else {
                    model.reportImportError("Nothing was selected.")
                    return
                }
                importBusy = true
                let selectedTarget = target
                Task {
                    var all: [KnowledgeRecord] = []
                    var errors: [String] = []
                    for url in urls {
                        do {
                            let parsed = try await Task.detached(priority: .userInitiated) {
                                try MetaArchiveImporter().importURL(url)
                            }.value
                            all.append(contentsOf: parsed)
                        } catch {
                            errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                    if !all.isEmpty {
                        model.merge(all, sourceName: selectedTarget)
                        if !errors.isEmpty { model.reportImportError(model.importStatus + " Some files were skipped: " + errors.joined(separator: " • ")) }
                    } else {
                        model.reportImportError(errors.isEmpty ? "No supported records were found in the selected files." : errors.joined(separator: " • "))
                    }
                    importBusy = false
                }
            }
        }
    }
}

struct AnalysisView: View {
    @EnvironmentObject var model: NexusModel
    @State private var expanded = Set<UUID>()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                overallCard
                personality

                ForEach(model.analysisSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(section.title).font(.headline)
                            Spacer()
                            Text("\(Int(section.confidence * 100))%")
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                        }
                        ProgressView(value: section.confidence)
                        Text(section.summary).font(.subheadline).foregroundStyle(.secondary)
                        DisclosureGroup("Details & evidence") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(section.details, id: \.self) { detail in
                                    Label(detail, systemImage: "circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 6)
                        }
                        .tint(.cyan)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }

                NavigationLink {
                    TimelineView()
                } label: {
                    Label("Open life timeline", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle("Analysis")
    }

    private var overallCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall analysis").font(.title2.bold())
            Text(model.overallSummary).foregroundStyle(.secondary)
            Text("Analysis updates automatically whenever new evidence is imported or connected.")
                .font(.caption)
                .foregroundStyle(.cyan)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var personality: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personality self-assessment").font(.headline)
            Text("Kept separate from behavioral inference so your own view of yourself is not mistaken for observed evidence.")
                .font(.caption)
                .foregroundStyle(.secondary)
            trait("Openness", $model.personality.openness)
            trait("Conscientiousness", $model.personality.conscientiousness)
            trait("Extraversion", $model.personality.extraversion)
            trait("Agreeableness", $model.personality.agreeableness)
            trait("Emotional sensitivity", $model.personality.neuroticism)
            TextField("MBTI (optional)", text: $model.personality.mbti).textFieldStyle(.roundedBorder)
            Button("Save assessment") { model.saveProfile() }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func trait(_ name: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack { Text(name); Spacer(); Text("\(Int(value.wrappedValue))") }
            Slider(value: value, in: 0...100)
        }
    }
}

struct KnowledgeGraphView: View {
    @EnvironmentObject var model: NexusModel
    @State private var filter: GraphFilter = .all

    enum GraphFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case interests = "Interests"
        case people = "People"
        case sources = "Sources"
        case activities = "Activities"
        var id: String { rawValue }
    }

    private var filteredGraph: KnowledgeGraph {
        let graph = model.knowledgeGraph
        guard filter != .all else { return graph }
        let allowed: Set<KnowledgeGraphNode.Category>
        switch filter {
        case .all: allowed = Set(KnowledgeGraphNode.Category.allCases)
        case .interests: allowed = [.selfNode, .interest, .theme]
        case .people: allowed = [.selfNode, .person]
        case .sources: allowed = [.selfNode, .source]
        case .activities: allowed = [.selfNode, .activity, .place]
        }
        let nodes = graph.nodes.filter { allowed.contains($0.category) }
        let ids = Set(nodes.map(\.id))
        let edges = graph.edges.filter { ids.contains($0.from) && ids.contains($0.to) }
        return KnowledgeGraph(nodes: nodes, edges: edges)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Knowledge graph").font(.title2.bold())
                    Text("A live map of what NEXUS currently knows: evidence sources, recurring interests, people and activity types. Node size reflects evidence strength; cross-links show which sources support an interest.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Graph", selection: $filter) {
                    ForEach(GraphFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                GraphCanvas(graph: filteredGraph)
                    .frame(height: 520)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nodes").font(.headline)
                    ForEach(filteredGraph.nodes.sorted { $0.weight > $1.weight }) { node in
                        HStack {
                            Circle().fill(color(for: node.category)).frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(node.label).font(.subheadline.bold())
                                Text(node.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(node.category.rawValue).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding()
        }
        .navigationTitle("Graph")
    }

    private func color(for category: KnowledgeGraphNode.Category) -> Color {
        switch category {
        case .selfNode: return .cyan
        case .interest: return .purple
        case .person: return .green
        case .source: return .blue
        case .activity: return .orange
        case .place: return .pink
        case .theme: return .indigo
        }
    }
}

extension KnowledgeGraphNode.Category: CaseIterable {
    static var allCases: [KnowledgeGraphNode.Category] { [.selfNode, .interest, .person, .source, .activity, .place, .theme] }
}

struct GraphCanvas: View {
    let graph: KnowledgeGraph

    var body: some View {
        Canvas { context, size in
            let positions = layout(size: size)
            for edge in graph.edges {
                guard let a = positions[edge.from], let b = positions[edge.to] else { continue }
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(.secondary.opacity(0.25 + edge.weight * 0.35)), lineWidth: 0.8 + edge.weight * 1.4)
            }

            for node in graph.nodes {
                guard let p = positions[node.id] else { continue }
                let radius = node.category == .selfNode ? 29.0 : 12.0 + node.weight * 11.0
                let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color(for: node.category).opacity(0.9)))
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.25)), lineWidth: 1)
                let label = node.label.count > 15 ? String(node.label.prefix(14)) + "…" : node.label
                context.draw(Text(label).font(.system(size: node.category == .selfNode ? 12 : 9, weight: .semibold)).foregroundStyle(.white), at: CGPoint(x: p.x, y: p.y + radius + 9), anchor: .center)
            }
        }
    }

    private func layout(size: CGSize) -> [String: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var out: [String: CGPoint] = ["self": center]
        let minDim = min(size.width, size.height)
        let specs: [(KnowledgeGraphNode.Category, Double, Double)] = [
            (.interest, -Double.pi / 2, 0.28),
            (.person, 0, 0.37),
            (.source, Double.pi / 2, 0.45),
            (.activity, Double.pi, 0.34),
            (.place, Double.pi / 4, 0.42),
            (.theme, -Double.pi / 4, 0.40)
        ]
        for (category, base, factor) in specs {
            let nodes = graph.nodes.filter { $0.category == category }
            guard !nodes.isEmpty else { continue }
            let spread = min(Double.pi * 1.45, 0.65 + Double(nodes.count) * 0.34)
            for (index, node) in nodes.enumerated() {
                let fraction = nodes.count == 1 ? 0.5 : Double(index) / Double(nodes.count - 1)
                let angle = base - spread / 2 + spread * fraction
                let radius = minDim * factor
                let x = center.x + CGFloat(cos(angle) * radius)
                let y = center.y + CGFloat(sin(angle) * radius * 1.18)
                out[node.id] = CGPoint(x: max(28, min(size.width - 28, x)), y: max(30, min(size.height - 38, y)))
            }
        }
        return out
    }

    private func color(for category: KnowledgeGraphNode.Category) -> Color {
        switch category {
        case .selfNode: return .cyan
        case .interest: return .purple
        case .person: return .green
        case .source: return .blue
        case .activity: return .orange
        case .place: return .pink
        case .theme: return .indigo
        }
    }
}

struct TimelineView: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        List(model.records.prefix(1000)) { r in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.title.isEmpty ? r.kind.rawValue.capitalized : r.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text(r.source).font(.caption).foregroundStyle(.cyan)
                }
                if !r.text.isEmpty { Text(r.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                if let d = r.timestamp { Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary) }
            }
            .padding(.vertical, 3)
        }
        .navigationTitle("Life Timeline")
    }
}

struct AskView: View {
    @EnvironmentObject var model: NexusModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.chatMessages) { message in
                            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                                Text(message.text)
                                    .padding(12)
                                    .background(message.role == .user ? Color.cyan.opacity(0.25) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                                if !message.evidence.isEmpty {
                                    DisclosureGroup("Evidence (\(message.evidence.count))") {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(message.evidence, id: \.self) { item in
                                                Text(item).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                    .font(.caption.bold())
                                    .tint(.cyan)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: model.chatMessages.count) { _, _ in
                    if let id = model.chatMessages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }

            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask NEXUS anything about your data…", text: $model.question, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { model.ask() }
                Button {
                    model.ask()
                    focused = true
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Personal AI")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Analyze me overall") { model.question = "Give me an overall analysis"; model.ask() }
                    Button("What are my interests?") { model.question = "What are my strongest interests and recurring topics?"; model.ask() }
                    Button("Analyze communication") { model.question = "Analyze my communication style"; model.ask() }
                    Divider()
                    Button("Clear chat", role: .destructive) { model.clearChat() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}
