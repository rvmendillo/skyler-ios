import SwiftUI

// MARK: - V5 shell

struct RootV5View: View {
    var body: some View {
        TabView {
            NavigationStack { HomeV5View() }
                .tabItem { Label("Home", systemImage: "sparkles") }
            NavigationStack { ConnectionsV4View() }
                .tabItem { Label("Connect", systemImage: "square.and.arrow.down.on.square") }
            NavigationStack { JourneyHubV5View() }
                .tabItem { Label("Journey", systemImage: "book.pages.fill") }
            NavigationStack { KnowledgeGraphV3View() }
                .tabItem { Label("Graph", systemImage: "point.3.filled.connected.trianglepath.dotted") }
            NavigationStack { AskV3View() }
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right.fill") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
}

struct HomeV5View: View {
    @EnvironmentObject var model: NexusModel

    var body: some View {
        let report = model.comprehensiveReport
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXUS").font(.system(size: 40, weight: .black, design: .rounded)).tracking(7)
                    Text("YOUR PERSONAL UNIVERSE").font(.caption.bold()).foregroundStyle(.cyan)
                    Text("Explore your life as data, stories, timelines, relationships, interests and changing chapters.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    metric("Records", "\(model.records.count)", "doc.text.magnifyingglass")
                    metric("Years", "\(model.journeyYears.count)", "calendar")
                    metric("Evidence", "\(Int(report.confidence * 100))%", "checkmark.shield")
                }

                NavigationLink { JourneyHubV5View(startMode: .storybook) } label: {
                    heroCard(title: "Your living storybook", subtitle: "Turn real memories, interests, people and places into playful narrated chapters.", symbol: "book.pages.fill")
                }.buttonStyle(.plain)

                NavigationLink { JourneyHubV5View(startMode: .timeline) } label: {
                    heroCard(title: "Travel through your timeline", subtitle: "Search, filter and zoom through months and years of captured life evidence.", symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }.buttonStyle(.plain)

                if !model.journeyOnThisDay.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("On this day", systemImage: "calendar.badge.clock").font(.headline)
                        Text("NEXUS found \(model.journeyOnThisDay.count) older record\(model.journeyOnThisDay.count == 1 ? "" : "s") from this calendar day.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(model.journeyOnThisDay.prefix(3)) { record in
                            compactMemory(record)
                        }
                    }.journeyPanel()
                }

                NavigationLink { DiscoverV4View() } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Label("Deep analysis", systemImage: "scope").font(.headline); Spacer(); Image(systemName: "chevron.right") }
                        Text(report.overall).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
                    }.journeyPanel()
                }.buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Intelligence engine", systemImage: NexusIntelligenceEngine.appleIntelligenceAvailable ? "apple.intelligence" : "brain.head.profile.fill")
                        .font(.headline)
                    Text(model.v3AIStatus).font(.subheadline).foregroundStyle(.secondary)
                    Text("Storybook narration stays evidence-grounded. Apple Intelligence is used only when available and requested for a page rewrite.")
                        .font(.caption).foregroundStyle(.tertiary)
                }.journeyPanel()
            }
            .padding()
        }
    }

    private func metric(_ label: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol).foregroundStyle(.cyan)
            Text(value).font(.headline).minimumScaleFactor(0.65)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func heroCard(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(.cyan.opacity(0.16)).frame(width: 62, height: 62)
                Image(systemName: symbol).font(.title2).foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.journeyPanel()
    }

    private func compactMemory(_ record: KnowledgeRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.timestamp?.formatted(date: .abbreviated, time: .omitted) ?? "Undated").font(.caption2).foregroundStyle(.cyan)
            Text(record.text.isEmpty ? record.title : record.text).font(.caption).lineLimit(2)
        }
    }
}

// MARK: - Journey hub

enum JourneyHubMode: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case storybook = "Storybook"
    case playground = "Playground"
    var id: String { rawValue }
}

struct JourneyHubV5View: View {
    @State private var mode: JourneyHubMode

    init(startMode: JourneyHubMode = .timeline) { _mode = State(initialValue: startMode) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Journey mode", selection: $mode) {
                ForEach(JourneyHubMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            switch mode {
            case .timeline: TimelineV5View()
            case .storybook: StorybookV5View()
            case .playground: PlaygroundV5View()
            }
        }
        .navigationTitle("Journey")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Immersive timeline

struct TimelineV5View: View {
    @EnvironmentObject var model: NexusModel
    @State private var selectedYear: Int? = nil
    @State private var selectedKind: KnowledgeRecord.Kind? = nil
    @State private var query = ""
    @State private var expandedRecord: KnowledgeRecord?

    var body: some View {
        let buckets = model.journeyTimelineBuckets(year: selectedYear, query: query, kind: selectedKind)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                timelineHeader
                ActivityHeatmapV5(records: model.journeyDatedRecords)
                    .journeyPanel()

                if model.journeyYears.isEmpty {
                    ContentUnavailableView("No dated memories yet", systemImage: "clock.badge.questionmark", description: Text("Import data with timestamps to build your life timeline."))
                        .padding(.top, 50)
                } else if buckets.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
                } else {
                    ForEach(buckets) { bucket in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(bucket.title).font(.title3.bold())
                            Text(bucket.subtitle).font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 5)

                        ForEach(bucket.records.prefix(250)) { record in
                            Button { expandedRecord = record } label: {
                                TimelineRecordCardV5(record: record)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding()
        }
        .sheet(item: $expandedRecord) { record in RecordDetailV5(record: record) }
    }

    private var timelineHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Life timeline").font(.title2.bold())
                    Text("\(model.journeyDatedRecords.count) time-anchored records").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("All activity") { selectedKind = nil }
                    ForEach(KnowledgeRecord.Kind.allCases, id: \.self) { kind in Button(kind.rawValue.capitalized) { selectedKind = kind } }
                } label: { Label(selectedKind?.rawValue.capitalized ?? "All", systemImage: "line.3.horizontal.decrease.circle") }
            }

            TextField("Search your timeline", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    yearChip("All", active: selectedYear == nil) { selectedYear = nil }
                    ForEach(model.journeyYears, id: \.self) { year in
                        yearChip(String(year), active: selectedYear == year) { selectedYear = year }
                    }
                }
            }
        }.journeyPanel()
    }

    private func yearChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(label).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7) }
            .buttonStyle(.plain)
            .background(active ? Color.cyan.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(active ? Color.cyan.opacity(0.7) : Color.clear))
    }
}

struct TimelineRecordCardV5: View {
    let record: KnowledgeRecord
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(.cyan).frame(width: 10, height: 10)
                Rectangle().fill(.cyan.opacity(0.25)).frame(width: 2, height: 74)
            }.padding(.top, 8)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(record.kind.rawValue.capitalized, systemImage: journeySymbol(record.kind)).font(.caption.bold()).foregroundStyle(.cyan)
                    Spacer()
                    Text(record.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(record.title.isEmpty ? record.source : record.title).font(.subheadline.bold()).lineLimit(1)
                let body = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { Text(body).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                Text(record.source).font(.caption2).foregroundStyle(.tertiary)
            }.padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
        }
    }

    private func journeySymbol(_ kind: KnowledgeRecord.Kind) -> String {
        switch kind {
        case .message, .comment: return "bubble.left.fill"
        case .reaction, .saved: return "heart.fill"
        case .search: return "magnifyingglass"
        case .post, .media: return "photo.fill.on.rectangle.fill"
        case .event, .reminder: return "calendar"
        case .contact, .follow: return "person.fill"
        case .location: return "mappin.circle.fill"
        case .music: return "music.note"
        case .health: return "heart.text.square.fill"
        case .file, .note: return "doc.text.fill"
        default: return "circle.grid.2x2.fill"
        }
    }
}

struct RecordDetailV5: View {
    let record: KnowledgeRecord
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(record.text.isEmpty ? record.title : record.text)
                    if !record.title.isEmpty && record.title != record.text { Text(record.title).foregroundStyle(.secondary) }
                }
                Section("Provenance") {
                    LabeledContent("Source", value: record.source)
                    LabeledContent("Type", value: record.kind.rawValue.capitalized)
                    if let date = record.timestamp { LabeledContent("Date", value: date.formatted(date: .long, time: .standard)) }
                }
                if !record.metadata.isEmpty {
                    Section("Metadata") { ForEach(record.metadata.keys.sorted(), id: \.self) { key in LabeledContent(key, value: record.metadata[key] ?? "") } }
                }
            }
            .navigationTitle("Evidence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Storybook

struct StorybookV5View: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var narrator = NexusStoryNarrator()
    @State private var storyMode: JourneyStoryMode = .journey
    @State private var pageIndex = 0
    @State private var selectedEvidence: NexusStoryPage?
    @State private var aiNarratives: [String:String] = [:]
    @State private var aiBusyID: String?

    var body: some View {
        let pages = model.storyPages(mode: storyMode)
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("My NEXUS Storybook").font(.title2.bold())
                            Text("Playful pages, grounded in your real vault").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "wand.and.stars").font(.title2).foregroundStyle(.yellow)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(JourneyStoryMode.allCases) { item in
                                Button {
                                    storyMode = item; pageIndex = 0; narrator.stop()
                                } label: {
                                    Label(item.rawValue, systemImage: item.symbol).font(.caption.bold()).padding(.horizontal, 11).padding(.vertical, 8)
                                }.buttonStyle(.plain)
                                    .background(storyMode == item ? Color.cyan.opacity(0.23) : Color.secondary.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }.padding(.horizontal)

                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        StorybookPageV5(page: page, narrative: aiNarratives[page.id])
                            .padding(.horizontal, 16).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 505)
                .onChange(of: pageIndex) { _, _ in narrator.stop() }

                if pages.indices.contains(pageIndex) {
                    let page = pages[pageIndex]
                    HStack(spacing: 9) {
                        Button {
                            narrator.isSpeaking ? narrator.stop() : narrator.speak(aiNarratives[page.id] ?? page.body)
                        } label: { Label(narrator.isSpeaking ? "Stop" : "Read aloud", systemImage: narrator.isSpeaking ? "stop.fill" : "speaker.wave.2.fill") }
                            .buttonStyle(.borderedProminent)

                        Button { selectedEvidence = page } label: { Label("Evidence", systemImage: "checkmark.shield.fill") }
                            .buttonStyle(.bordered)

                        if NexusIntelligenceEngine.appleIntelligenceAvailable {
                            Button { magicRewrite(page) } label: {
                                if aiBusyID == page.id { ProgressView().controlSize(.small) }
                                else { Image(systemName: "apple.intelligence") }
                            }.buttonStyle(.bordered).disabled(aiBusyID != nil)
                        }
                    }.padding(.horizontal)

                    Text(NexusIntelligenceEngine.appleIntelligenceAvailable ? "Magic rewrite uses Apple Intelligence on-device and is instructed to preserve the supplied facts." : "The built-in story remains available with zero model download.")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal)
                }
            }.padding(.vertical, 12)
        }
        .sheet(item: $selectedEvidence) { page in
            NavigationStack {
                List {
                    Section { Text("Every claim on this page should be traceable to these records. Storybook language may summarize, but should not invent life events.") }
                    Section("Evidence") { ForEach(page.evidence, id: \.self) { Text($0) } }
                }.navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func magicRewrite(_ page: NexusStoryPage) {
        aiBusyID = page.id
        Task {
            let context = ([page.body] + page.evidence).joined(separator: "\n")
            let request = "Rewrite this personal-memory page as a warm, playful, colorful children's-TV-style storybook narration for an adult reader. Keep every factual detail grounded in the supplied evidence. Do not invent events, relationships, emotions or motives. 120-220 words."
            let result = await NexusIntelligenceEngine.respond(question: request, context: context)
            aiNarratives[page.id] = result
            aiBusyID = nil
        }
    }
}

struct StorybookPageV5: View {
    let page: NexusStoryPage
    let narrative: String?
    private let palettes: [[Color]] = [
        [.blue, .cyan], [.purple, .pink], [.orange, .pink], [.green, .teal], [.indigo, .purple], [.mint, .blue]
    ]

    var body: some View {
        let palette = palettes[abs(page.accentIndex) % palettes.count]
        ZStack {
            RoundedRectangle(cornerRadius: 34).fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.13)).frame(width: 190).offset(x: 125, y: -180)
            Circle().fill(.white.opacity(0.09)).frame(width: 140).offset(x: -135, y: 175)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: page.symbol).font(.system(size: 42, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    HStack(spacing: 7) { Image(systemName: "star.fill"); Image(systemName: "sparkles"); Image(systemName: "cloud.fill") }.foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 8)
                Text(page.subtitle.uppercased()).font(.caption.bold()).tracking(1.5).foregroundStyle(.white.opacity(0.8))
                Text(page.title).font(.system(size: 31, weight: .black, design: .rounded)).foregroundStyle(.white)
                ScrollView {
                    Text(narrative ?? page.body).font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.96)).frame(maxWidth: .infinity, alignment: .leading)
                }.scrollIndicators(.hidden)
                Spacer(minLength: 3)
                HStack { Label("Evidence-backed", systemImage: "checkmark.shield.fill"); Spacer(); Text("\(page.evidence.count) traces") }
                    .font(.caption.bold()).foregroundStyle(.white.opacity(0.84))
            }.padding(26)
        }
        .shadow(radius: 15, y: 8)
    }
}

// MARK: - Playground / premium exploration

struct PlaygroundV5View: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Exploration playground").font(.title2.bold())
                Text("Tools for wandering through your archive instead of only reading a summary.").foregroundStyle(.secondary)

                NavigationLink { TimeMachineV5View() } label: { premiumLink("Time Machine", "Compare two years without mistaking export volume for behavior.", "arrow.left.and.right.circle.fill") }.buttonStyle(.plain)
                NavigationLink { MemoryDeckV5View() } label: { premiumLink("Memory Roulette", "Flip through unexpected moments and save favorites.", "rectangle.stack.fill") }.buttonStyle(.plain)
                NavigationLink { YearbookV5View() } label: { premiumLink("Personal Yearbook", "See each year's dominant activity, sources and recurring terms.", "books.vertical.fill") }.buttonStyle(.plain)
                NavigationLink { InterestTrailV5View() } label: { premiumLink("Interest Trails", "Type any idea, person or topic and follow it through time.", "point.topleft.down.to.point.bottomright.curvepath") }.buttonStyle(.plain)
                NavigationLink { VaultExplorerV5View() } label: { premiumLink("Vault Explorer", "Search the raw normalized knowledge records with filters.", "archivebox.fill") }.buttonStyle(.plain)
                NavigationLink { DiscoverV4View() } label: { premiumLink("Analysis Lab", "Return to the evidence-weighted comprehensive model.", "scope") }.buttonStyle(.plain)
                NavigationLink { KnowledgeGraphV3View() } label: { premiumLink("Graph Lab", "Explore the interactive network of interests, people, sources and activities.", "point.3.filled.connected.trianglepath.dotted") }.buttonStyle(.plain)
            }.padding()
        }
    }

    private func premiumLink(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.cyan).frame(width: 40)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.journeyPanel()
    }
}

struct TimeMachineV5View: View {
    @EnvironmentObject var model: NexusModel
    @State private var firstYear = 0
    @State private var secondYear = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Time Machine").font(.largeTitle.bold())
                Text("Compare captured periods while keeping source coverage and export bias visible.").foregroundStyle(.secondary)
                if model.journeyYears.count < 2 {
                    ContentUnavailableView("Two years needed", systemImage: "calendar.badge.exclamationmark", description: Text("Import dated data spanning at least two years."))
                } else {
                    HStack {
                        Picker("From", selection: $firstYear) { ForEach(model.journeyYears, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.menu)
                        Image(systemName: "arrow.right")
                        Picker("To", selection: $secondYear) { ForEach(model.journeyYears, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.menu)
                    }.journeyPanel()

                    if let result = model.compareYears(firstYear, secondYear) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Comparison").font(.headline); Text(result.summary).foregroundStyle(.secondary)
                            ForEach(result.details, id: \.self) { Text("• \($0)").font(.caption) }
                        }.journeyPanel()
                        HStack(spacing: 10) { snapshotCard(result.first); snapshotCard(result.second) }
                    }
                }
            }.padding()
        }
        .navigationTitle("Time Machine").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if firstYear == 0 { firstYear = model.journeyYears.dropFirst().first ?? model.journeyYears.first ?? 0 }
            if secondYear == 0 { secondYear = model.journeyYears.first ?? 0 }
        }
    }

    private func snapshotCard(_ snap: NexusYearSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(snap.year)).font(.title2.bold()).foregroundStyle(.cyan)
            Text("\(snap.recordCount) records").font(.headline)
            Text("\(snap.sourceCount) sources").font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(snap.topTerms.prefix(4), id: \.0) { term in Text(term.0).font(.caption) }
        }.frame(maxWidth: .infinity, alignment: .leading).journeyPanel()
    }
}

struct MemoryDeckV5View: View {
    @EnvironmentObject var model: NexusModel
    @State private var index = 0
    @AppStorage("nexus.bookmarks.v1") private var bookmarkBlob = ""

    var body: some View {
        let deck = model.journeyMemoryDeck
        VStack(spacing: 18) {
            if deck.isEmpty {
                ContentUnavailableView("No memory deck yet", systemImage: "rectangle.stack.badge.questionmark", description: Text("Import dated text/activity data first."))
            } else {
                let record = deck[index % deck.count]
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Label(record.kind.rawValue.capitalized, systemImage: "sparkles").foregroundStyle(.cyan); Spacer(); Text("\(index + 1)/\(deck.count)").foregroundStyle(.secondary) }
                    Text(record.timestamp?.formatted(date: .long, time: .shortened) ?? "Undated").font(.title2.bold())
                    Text(record.title).font(.headline).foregroundStyle(.secondary)
                    ScrollView { Text(record.text.isEmpty ? record.title : record.text).font(.body).frame(maxWidth: .infinity, alignment: .leading) }
                    Divider(); Text(record.source).font(.caption).foregroundStyle(.tertiary)
                }.padding(24).frame(maxWidth: .infinity, minHeight: 390, alignment: .topLeading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
                HStack {
                    Button { index = (index + deck.count - 1) % deck.count } label: { Image(systemName: "chevron.left") }.buttonStyle(.bordered)
                    Button { toggleBookmark(record.id) } label: { Label(isBookmarked(record.id) ? "Saved" : "Save", systemImage: isBookmarked(record.id) ? "bookmark.fill" : "bookmark") }.buttonStyle(.borderedProminent)
                    Button { index = (index + 1) % deck.count } label: { Image(systemName: "chevron.right") }.buttonStyle(.bordered)
                }
                Spacer()
            }
        }.padding().navigationTitle("Memory Roulette")
    }

    private var bookmarkIDs: Set<String> { Set(bookmarkBlob.split(separator: "\n").map(String.init)) }
    private func isBookmarked(_ id: String) -> Bool { bookmarkIDs.contains(id) }
    private func toggleBookmark(_ id: String) {
        var set = bookmarkIDs
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        bookmarkBlob = set.sorted().joined(separator: "\n")
    }
}

struct YearbookV5View: View {
    @EnvironmentObject var model: NexusModel
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(model.journeyYearSnapshots) { snap in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text(String(snap.year)).font(.largeTitle.bold()).foregroundStyle(.cyan); Spacer(); Text("\(snap.recordCount) records").font(.caption.bold()) }
                        Text("Captured across \(snap.sourceCount) sources. Top activity: \(snap.topKinds.prefix(3).map { $0.0.capitalized }.joined(separator: ", ")).")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !snap.topTerms.isEmpty {
                            Text("Recurring terms").font(.caption.bold()).foregroundStyle(.tertiary)
                            FlowTermsV5(terms: snap.topTerms.map(\.0))
                        }
                    }.journeyPanel()
                }
            }.padding()
        }.navigationTitle("Personal Yearbook")
    }
}

struct InterestTrailV5View: View {
    @EnvironmentObject var model: NexusModel
    @State private var query = ""
    var body: some View {
        let matches = query.count < 2 ? [] : model.journeyTimelineRecords(year: nil, query: query, kind: nil)
        List {
            Section {
                TextField("Topic, person, place, project…", text: $query)
                Text("Follow any recurring term through your dated evidence. Search is literal and local.").font(.caption).foregroundStyle(.secondary)
            }
            if !query.isEmpty {
                Section("\(matches.count) matches") {
                    ForEach(matches.prefix(300)) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.timestamp?.formatted(date: .abbreviated, time: .omitted) ?? "Undated").font(.caption2).foregroundStyle(.cyan)
                            Text(record.text.isEmpty ? record.title : record.text).lineLimit(3)
                            Text(record.source).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("Interest Trails")
    }
}

struct VaultExplorerV5View: View {
    @EnvironmentObject var model: NexusModel
    @State private var query = ""
    @State private var kind: KnowledgeRecord.Kind? = nil
    var body: some View {
        let q = query.lowercased()
        let filtered = model.records.lazy.filter { record in
            if let kind, record.kind != kind { return false }
            if q.isEmpty { return true }
            return (record.title + " " + record.text + " " + record.source).lowercased().contains(q)
        }.prefix(1000).map { $0 }
        List {
            Section {
                TextField("Search normalized records", text: $query)
                Picker("Type", selection: $kind) {
                    Text("All").tag(KnowledgeRecord.Kind?.none)
                    ForEach(KnowledgeRecord.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }
            }
            Section("Results") {
                ForEach(filtered) { record in
                    NavigationLink { RecordDetailV5(record: record) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title.isEmpty ? record.kind.rawValue.capitalized : record.title).font(.subheadline.bold()).lineLimit(1)
                            Text(record.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(record.source).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }.navigationTitle("Vault Explorer")
    }
}

// MARK: - Supporting visual components

struct ActivityHeatmapV5: View {
    let records: [KnowledgeRecord]
    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<140).compactMap { calendar.date(byAdding: .day, value: -139 + $0, to: today) }
        let counts = Dictionary(grouping: records.compactMap { $0.timestamp }.map { calendar.startOfDay(for: $0) }, by: { $0 }).mapValues(\.count)
        let maxCount = max(1, counts.values.max() ?? 1)
        VStack(alignment: .leading, spacing: 9) {
            HStack { Label("Activity texture", systemImage: "square.grid.3x3.fill").font(.headline); Spacer(); Text("last 140 days").font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 14), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let count = counts[day] ?? 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(count == 0 ? Color.secondary.opacity(0.10) : Color.cyan.opacity(0.22 + 0.75 * Double(count) / Double(maxCount)))
                        .frame(height: 14)
                        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)): \(count) records")
                }
            }
            Text("Density shows captured records, not a productivity score.").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct FlowTermsV5: View {
    let terms: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(terms, id: \.self) { term in Text(term).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6).background(.cyan.opacity(0.14), in: Capsule()) }
            }
        }
    }
}

private extension View {
    func journeyPanel() -> some View {
        self.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
