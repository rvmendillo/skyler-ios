import SwiftUI
import UniformTypeIdentifiers

struct RootV3View: View {
    @EnvironmentObject var model: NexusModel

    var body: some View {
        TabView {
            NavigationStack { HomeV3View() }
                .tabItem { Label("Home", systemImage: "sparkles") }
            NavigationStack { ConnectionsV3View() }
                .tabItem { Label("Connect", systemImage: "square.and.arrow.down.on.square") }
            NavigationStack { DiscoverV3View() }
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

// MARK: - Home

struct HomeV3View: View {
    @EnvironmentObject var model: NexusModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("NEXUS").font(.system(size: 40, weight: .black, design: .rounded)).tracking(7)
                    Text("PERSONAL KNOWLEDGE INTELLIGENCE").font(.caption.bold()).foregroundStyle(.cyan)
                    Text("A local-first model of your interests, behavior, personality, people, routines and long-term change.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    metric("Records", "\(model.records.count)", "doc.text.magnifyingglass")
                    metric("Sources", "\(Set(model.records.map(\.source)).count)", "square.stack.3d.up")
                    metric("Graph", "\(model.knowledgeGraph.nodes.count)", "point.3.connected.trianglepath.dotted")
                }

                card {
                    HStack(spacing: 12) {
                        Image(systemName: NexusIntelligenceEngine.appleIntelligenceAvailable ? "apple.intelligence" : "brain.head.profile.fill")
                            .font(.title2).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Intelligence engine").font(.headline)
                            Text(model.v3AIStatus).font(.subheadline).foregroundStyle(.secondary)
                            Text(NexusIntelligenceEngine.appleIntelligenceAvailable ? "Uses Apple's built-in on-device foundation model; no model download is added to the IPA." : "Uses NEXUS retrieval, analytics and iOS Natural Language with no bundled model weights.")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }

                card {
                    Text("Overall model").font(.headline)
                    Text(model.overallSummary).foregroundStyle(.secondary)
                }

                let personality = model.v3Personality
                if !personality.traits.isEmpty {
                    card {
                        HStack { Text("Personality from overall data").font(.headline); Spacer(); Text(personality.styleCode).font(.headline).foregroundStyle(.cyan) }
                        Text(personality.summary).font(.subheadline).foregroundStyle(.secondary)
                        ForEach(personality.traits.prefix(3)) { trait in
                            HStack {
                                Text(trait.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text("\(trait.score)").font(.caption.bold()).foregroundStyle(.cyan)
                            }
                            ProgressView(value: Double(trait.score), total: 100)
                        }
                    }
                }

                if !model.v3Discoveries.isEmpty {
                    Text("Fresh discoveries").font(.title3.bold()).padding(.top, 2)
                    ForEach(model.v3Discoveries.prefix(3)) { discovery in
                        discoveryCard(discovery)
                    }
                }

                card {
                    Label("Every inference can be traced back to records in your local vault. More independent sources increase confidence.", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding()
        }
        .navigationTitle("")
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

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) { content() }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func discoveryCard(_ discovery: NexusDiscovery) -> some View {
        card {
            HStack {
                Image(systemName: discovery.symbol).foregroundStyle(.cyan)
                Text(discovery.title).font(.headline)
                Spacer()
                Text(discovery.value).font(.caption.bold()).foregroundStyle(.cyan).lineLimit(1)
            }
            Text(discovery.explanation).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Connections and robust imports

struct ConnectionsV3View: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var hub = DeviceConnectorHub()
    @State private var target = "Imported Files"
    @State private var importing = false
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
                            .foregroundStyle(model.importStatus.lowercased().contains("imported") ? .green : .secondary)
                    }
                }
            }

            Section("Archive imports") {
                importRow(title: "Instagram", detail: "Original Meta ZIP, JSON, HTML or exported folder", symbol: "camera.circle.fill")
                importRow(title: "Facebook / Messenger", detail: "Original Facebook/Messenger ZIP, JSON, HTML or folder", symbol: "bubble.left.and.bubble.right.fill")
                importRow(title: "Files / iCloud Drive", detail: "ZIP, JSON, CSV, TXT, HTML, XML and folders", symbol: "folder.fill")
            }

            Section("On-device sources") {
                ForEach(model.connectors.filter { $0.mode == .native }) { connector in
                    HStack(spacing: 12) {
                        Image(systemName: connector.symbol).frame(width: 26).foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connector.name).font(.headline)
                            Text(connector.detail).font(.caption).foregroundStyle(.secondary)
                            Text(connector.status).font(.caption2).foregroundStyle(connector.status.contains("Connected") || connector.status.contains("records") ? .green : .tertiary)
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

            Section("Why this importer is different") {
                Text("NEXUS first copies the selected export into its own temporary sandbox while Files permission is active, then parses that local copy. This avoids losing access to large Instagram or Messenger exports after the document picker closes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Connections")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .failure(let error):
                model.reportImportError("Picker error: \(error.localizedDescription)")
            case .success(let urls):
                guard !urls.isEmpty else { model.reportImportError("Nothing was selected."); return }
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
                        let message = result.errors.isEmpty ? "The file opened, but no usable records were found. If this is a Meta export, select the original downloaded ZIP rather than an iCloud preview." : result.errors.joined(separator: " • ")
                        model.reportImportError(message)
                    }
                    progressText = ""
                    importBusy = false
                }
            }
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
                importing = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(importBusy)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Discover and personality

struct DiscoverV3View: View {
    @EnvironmentObject var model: NexusModel
    @State private var selectedDiscovery: NexusDiscovery?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Overall analysis").font(.title2.bold())
                    Text(model.overallSummary).foregroundStyle(.secondary)
                    Text("Regenerated from the full vault whenever data changes.").font(.caption).foregroundStyle(.cyan)
                }
                .panel()

                personalityPanel

                if !model.v3Discoveries.isEmpty {
                    Text("Discovery lab").font(.title3.bold())
                    Text("Patterns designed to surface connections you may not have explicitly asked NEXUS to look for.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(model.v3Discoveries) { discovery in
                        Button { selectedDiscovery = discovery } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: discovery.symbol).font(.title2).foregroundStyle(.cyan).frame(width: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(discovery.title).font(.headline); Spacer(); Text(discovery.value).font(.caption.bold()).foregroundStyle(.cyan).lineLimit(1) }
                                    Text(discovery.explanation).font(.subheadline).foregroundStyle(.secondary)
                                    Text("Tap for evidence").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .panel()
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Detailed evidence model").font(.title3.bold()).padding(.top, 3)
                ForEach(model.analysisSections) { section in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(section.title).font(.headline)
                            Spacer()
                            Text("\(Int(section.confidence * 100))% confidence").font(.caption.bold()).foregroundStyle(.cyan)
                        }
                        ProgressView(value: section.confidence)
                        Text(section.summary).font(.subheadline).foregroundStyle(.secondary)
                        DisclosureGroup("Details") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.details, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.top, 5)
                        }
                        .tint(.cyan)
                    }
                    .panel()
                }

                NavigationLink { TimelineView() } label: {
                    Label("Explore full life timeline", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                .buttonStyle(.plain)
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

    private var personalityPanel: some View {
        let report = model.v3Personality
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Personality from overall data").font(.title3.bold())
                    Text(report.coverage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(report.styleCode).font(.title2.bold()).foregroundStyle(.cyan)
            }
            Text(report.summary).font(.subheadline).foregroundStyle(.secondary)

            ForEach(report.traits) { trait in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(trait.name).font(.subheadline.bold())
                        Spacer()
                        Text("\(trait.score)/100").font(.subheadline.bold()).foregroundStyle(.cyan)
                        Text("\(Int(trait.confidence * 100))%").font(.caption2).foregroundStyle(.tertiary)
                    }
                    ProgressView(value: Double(trait.score), total: 100)
                    Text(trait.explanation).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Why NEXUS estimated this") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(trait.evidence, id: \.self) { Text("• \($0)").font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.top, 4)
                    }
                    .font(.caption).tint(.cyan)
                }
                .padding(.vertical, 4)
            }

            Text(report.caveat).font(.caption2).foregroundStyle(.tertiary)

            DisclosureGroup("Compare with my optional self-report") {
                VStack(alignment: .leading, spacing: 6) {
                    selfRow("Openness", model.personality.openness)
                    selfRow("Conscientiousness", model.personality.conscientiousness)
                    selfRow("Extraversion", model.personality.extraversion)
                    selfRow("Agreeableness", model.personality.agreeableness)
                    selfRow("Emotional sensitivity", model.personality.neuroticism)
                    if !model.personality.mbti.isEmpty { Text("Self-reported MBTI: \(model.personality.mbti)").font(.caption) }
                    Text("Self-report does not determine the data-driven scores above.").font(.caption2).foregroundStyle(.tertiary)
                }.padding(.top, 5)
            }
            .font(.caption.bold()).tint(.cyan)
        }
        .panel()
    }

    private func selfRow(_ label: String, _ value: Double) -> some View {
        HStack { Text(label).font(.caption); Spacer(); Text("\(Int(value))").font(.caption.bold()) }
    }
}

// MARK: - Interactive graph

struct KnowledgeGraphV3View: View {
    @EnvironmentObject var model: NexusModel
    @State private var filter: GraphV3Filter = .all
    @State private var search = ""

    enum GraphV3Filter: String, CaseIterable, Identifiable {
        case all = "All", interests = "Interests", people = "People", sources = "Sources", activities = "Activity"
        var id: String { rawValue }
    }

    private var filtered: KnowledgeGraph {
        let graph = model.knowledgeGraph
        let allowed: Set<KnowledgeGraphNode.Category>
        switch filter {
        case .all: allowed = [.selfNode,.interest,.person,.source,.activity,.place,.theme]
        case .interests: allowed = [.selfNode,.interest,.theme]
        case .people: allowed = [.selfNode,.person]
        case .sources: allowed = [.selfNode,.source]
        case .activities: allowed = [.selfNode,.activity,.place]
        }
        var nodes = graph.nodes.filter { allowed.contains($0.category) }
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = search.lowercased()
            let matches = Set(nodes.filter { $0.label.lowercased().contains(q) || $0.detail.lowercased().contains(q) }.map(\.id))
            let connected = Set(graph.edges.filter { matches.contains($0.from) || matches.contains($0.to) }.flatMap { [$0.from,$0.to] })
            nodes = nodes.filter { $0.id == "self" || matches.contains($0.id) || connected.contains($0.id) }
        }
        let ids = Set(nodes.map(\.id))
        let edges = graph.edges.filter { ids.contains($0.from) && ids.contains($0.to) }
        return KnowledgeGraph(nodes: nodes, edges: edges)
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                TextField("Search interests, people, sources…", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("Graph filter", selection: $filter) {
                    ForEach(GraphV3Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            InteractiveGraphCanvas(graph: filtered)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(colors: [Color.black, Color.cyan.opacity(0.055), Color.purple.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal)

            HStack(spacing: 14) {
                legend(.cyan, "You")
                legend(.purple, "Interest")
                legend(.green, "Person")
                legend(.blue, "Source")
                legend(.orange, "Activity")
            }
            .font(.caption2)
            .padding(.bottom, 8)
        }
        .navigationTitle("Knowledge Graph")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) { Circle().fill(color).frame(width: 7, height: 7); Text(text).foregroundStyle(.secondary) }
    }
}

struct InteractiveGraphCanvas: View {
    let graph: KnowledgeGraph
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var selected: KnowledgeGraphNode?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    drawBackground(context: &context, size: size)
                    let positions = layout(size: size)
                    context.translateBy(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
                    context.scaleBy(x: scale, y: scale)
                    context.translateBy(x: -size.width / 2, y: -size.height / 2)

                    for edge in graph.edges {
                        guard let a = positions[edge.from], let b = positions[edge.to] else { continue }
                        var path = Path(); path.move(to: a); path.addLine(to: b)
                        context.stroke(path, with: .color(.white.opacity(0.10 + edge.weight * 0.20)), lineWidth: 0.7 + edge.weight * 1.8)
                    }

                    for node in graph.nodes.sorted(by: { $0.weight < $1.weight }) {
                        guard let p = positions[node.id] else { continue }
                        let radius = radius(for: node)
                        let glow = CGRect(x: p.x-radius*1.45, y: p.y-radius*1.45, width: radius*2.9, height: radius*2.9)
                        context.fill(Path(ellipseIn: glow), with: .color(color(for: node.category).opacity(0.10)))
                        let rect = CGRect(x: p.x-radius, y: p.y-radius, width: radius*2, height: radius*2)
                        context.fill(Path(ellipseIn: rect), with: .color(color(for: node.category).opacity(0.92)))
                        context.stroke(Path(ellipseIn: rect), with: .color(selected?.id == node.id ? .white : .white.opacity(0.25)), lineWidth: selected?.id == node.id ? 2.5 : 0.8)
                        let label = node.label.count > 18 ? String(node.label.prefix(17)) + "…" : node.label
                        context.draw(Text(label).font(.system(size: node.category == .selfNode ? 11 : 8.5, weight: .semibold)).foregroundStyle(.white), at: CGPoint(x: p.x, y: p.y + radius + 9), anchor: .center)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture.simultaneously(with: magnifyGesture))
                .simultaneousGesture(SpatialTapGesture().onEnded { value in select(at: value.location, size: geo.size) })
                .simultaneousGesture(TapGesture(count: 2).onEnded { resetView() })

                VStack(spacing: 7) {
                    graphButton("plus.magnifyingglass") { scale = min(3.5, scale * 1.25); baseScale = scale }
                    graphButton("minus.magnifyingglass") { scale = max(0.5, scale / 1.25); baseScale = scale }
                    graphButton("arrow.counterclockwise") { resetView() }
                }
                .padding(10)

                if let selected {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Circle().fill(color(for: selected.category)).frame(width: 10, height: 10)
                            Text(selected.label).font(.headline).lineLimit(1)
                            Spacer()
                            Button { self.selected = nil } label: { Image(systemName: "xmark.circle.fill") }
                        }
                        Text(selected.category.rawValue.capitalized).font(.caption2).foregroundStyle(.cyan)
                        Text(selected.detail).font(.caption).foregroundStyle(.secondary)
                        Text("Evidence strength \(Int(selected.weight * 100))%").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(12)
                    .frame(maxWidth: 310)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in offset = CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height) }
            .onEnded { _ in baseOffset = offset }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = min(3.5, max(0.5, baseScale * value)) }
            .onEnded { _ in baseScale = scale }
    }

    private func graphButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .buttonStyle(.bordered).background(.ultraThinMaterial, in: Circle())
    }

    private func resetView() { withAnimation(.spring) { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero } }

    private func select(at location: CGPoint, size: CGSize) {
        let center = CGPoint(x: size.width/2, y: size.height/2)
        let local = CGPoint(x: (location.x - center.x - offset.width) / scale + center.x,
                            y: (location.y - center.y - offset.height) / scale + center.y)
        let positions = layout(size: size)
        let nearest = graph.nodes.compactMap { node -> (KnowledgeGraphNode, CGFloat)? in
            guard let p = positions[node.id] else { return nil }
            let d = hypot(p.x-local.x, p.y-local.y)
            return d <= radius(for: node) + 18 ? (node,d) : nil
        }.min { $0.1 < $1.1 }?.0
        withAnimation(.spring(response: 0.25)) { selected = nearest }
    }

    private func drawBackground(context: inout GraphicsContext, size: CGSize) {
        let step: CGFloat = 28
        var x: CGFloat = 0
        while x < size.width {
            var y: CGFloat = 0
            while y < size.height {
                let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.06)))
                y += step
            }
            x += step
        }
    }

    private func layout(size: CGSize) -> [String: CGPoint] {
        let center = CGPoint(x: size.width/2, y: size.height/2)
        var positions: [String:CGPoint] = ["self": center]
        let categories: [(KnowledgeGraphNode.Category, CGFloat)] = [(.interest,0.25),(.theme,0.34),(.person,0.42),(.source,0.48),(.activity,0.36),(.place,0.45)]
        var globalIndex = 0
        for (category, factor) in categories {
            let nodes = graph.nodes.filter { $0.category == category }.sorted { $0.weight > $1.weight }
            guard !nodes.isEmpty else { continue }
            for (index,node) in nodes.enumerated() {
                let golden = Double.pi * (3 - sqrt(5.0))
                let angle = Double(globalIndex + index) * golden + phase(category)
                let jitter = CGFloat(index % 3) * 14
                let r = min(size.width,size.height) * factor + jitter
                let x = center.x + cos(angle) * r
                let y = center.y + sin(angle) * r * 0.78
                positions[node.id] = CGPoint(x: max(36,min(size.width-36,x)), y: max(42,min(size.height-48,y)))
            }
            globalIndex += nodes.count
        }
        return positions
    }

    private func phase(_ category: KnowledgeGraphNode.Category) -> Double {
        switch category {
        case .interest: return -1.4
        case .theme: return -0.6
        case .person: return 0.1
        case .source: return 1.4
        case .activity: return 2.4
        case .place: return 3.2
        case .selfNode: return 0
        }
    }

    private func radius(for node: KnowledgeGraphNode) -> CGFloat { node.category == .selfNode ? 28 : 10 + CGFloat(node.weight) * 12 }

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

// MARK: - Smooth chat

struct AskV3View: View {
    @EnvironmentObject var model: NexusModel
    @State private var draft = ""
    @State private var thinking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: NexusIntelligenceEngine.appleIntelligenceAvailable ? "apple.intelligence" : "brain")
                Text(model.v3AIStatus).font(.caption.bold())
                Spacer()
                if thinking { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(.cyan)
            .padding(.horizontal).padding(.vertical, 8)
            .background(.thinMaterial)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.chatMessages) { message in
                            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                                Text(message.text)
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .background(message.role == .user ? Color.cyan.opacity(0.22) : Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                                if !message.evidence.isEmpty {
                                    DisclosureGroup("Evidence • \(message.evidence.count)") {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(message.evidence, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                        }.padding(.top,4)
                                    }
                                    .font(.caption.bold()).tint(.cyan)
                                }
                            }
                            .id(message.id)
                        }
                        if thinking {
                            HStack(spacing: 8) { ProgressView(); Text("Synthesizing from your vault…").font(.caption).foregroundStyle(.secondary); Spacer() }
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: model.chatMessages.count) { _, _ in
                    if let id = model.chatMessages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }

            Divider()
            HStack(alignment: .bottom, spacing: 9) {
                TextField("Ask about your interests, personality, changes…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { send() }
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(thinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Personal AI")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Analyze me overall") { sendPrompt("Give me a comprehensive overall analysis of me from all available data.") }
                    Button("Analyze my personality") { sendPrompt("Analyze my personality from the overall data and explain the evidence for each trait.") }
                    Button("What changed recently?") { sendPrompt("What has changed in my interests or behavior recently?") }
                    Button("Find surprising connections") { sendPrompt("Find surprising cross-source connections in my knowledge graph.") }
                    Divider()
                    Button("Clear chat", role: .destructive) { model.clearChat() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func sendPrompt(_ text: String) { draft = text; send() }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        draft = ""
        thinking = true
        focused = false
        Task {
            await model.askV3(text)
            thinking = false
            focused = true
        }
    }
}

private extension View {
    func panel() -> some View {
        self.padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
