import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "sparkles") }
            NavigationStack { ConnectionsView() }.tabItem { Label("Connect", systemImage: "point.3.connected.trianglepath.dotted") }
            NavigationStack { InsightsView() }.tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
            NavigationStack { TimelineView() }.tabItem { Label("Timeline", systemImage: "clock.arrow.circlepath") }
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
                    Text("A private personal knowledge intelligence system that turns authorized data into an evidence-backed model of you.").foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                HStack {
                    metric("Records", "\(model.records.count)")
                    metric("Sources", "\(Set(model.records.map(\.source)).count)")
                    metric("Insights", "\(model.insights.count)")
                }

                section("What NEXUS can analyze") {
                    Text("Personality • habits • productivity • interests • relationships • communication • learning • health • travel • life timeline • recurring themes • goals • strengths • blind spots • long-term change")
                        .foregroundStyle(.secondary)
                }

                section("Privacy") {
                    Label("Local-first vault. Every imported record keeps its source so insights remain explainable.", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)
                }

                if let first = model.activityLog.first {
                    section("Latest") { Text(first) }
                }
            }
            .padding()
        }
        .navigationTitle("")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
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
    @State private var target = "Meta Archive"
    @State private var busy = ""

    private var importTypes: [UTType] {
        [UTType(filenameExtension: "zip") ?? .data, .json, .folder]
    }

    var body: some View {
        List(model.connectors) { c in
            HStack(spacing: 14) {
                Image(systemName: c.symbol).frame(width: 30).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name).font(.headline)
                    Text(c.detail).font(.caption).foregroundStyle(.secondary)
                    Text(c.status).font(.caption2).foregroundStyle(c.status.contains("Connected") ? .green : .secondary)
                }
                Spacer()
                if c.mode == .native {
                    Button(busy == c.id ? "…" : "Connect") {
                        busy = c.id
                        hub.connect(c.id) { records, status in
                            model.merge(records, sourceName: c.name)
                            model.setStatus(id: c.id, status: status)
                            busy = ""
                        }
                    }
                    .buttonStyle(.bordered)
                } else if c.mode == .archive {
                    Button("Import") {
                        target = c.name
                        importing = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Set up").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Connections")
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes, allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task.detached {
                let records = (try? MetaArchiveImporter().importURL(url)) ?? []
                await MainActor.run { model.merge(records, sourceName: target) }
            }
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject var model: NexusModel
    @State private var selected: InsightCard?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                personality
                ForEach(model.insights) { i in
                    Button { selected = i } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(i.title).font(.headline)
                                Spacer()
                                Text(i.value).font(.headline).foregroundStyle(.cyan)
                            }
                            Text(i.explanation).font(.subheadline).foregroundStyle(.secondary)
                            Text("View evidence").font(.caption.bold()).foregroundStyle(.cyan)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Insights")
        .sheet(item: $selected) { i in
            NavigationStack {
                List(i.evidence, id: \.self) { Text($0) }
                    .navigationTitle(i.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var personality: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personality self-assessment").font(.headline)
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
    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                Text(model.answer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            HStack {
                TextField("Ask about your life…", text: $model.question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.ask() }
                Button { model.ask() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
            }
        }
        .padding()
        .navigationTitle("Personal AI")
    }
}
