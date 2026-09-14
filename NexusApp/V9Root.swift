import SwiftUI
import UniformTypeIdentifiers

struct RootV9View: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @State private var showSplash = true
    @State private var palette = false

    var body: some View {
        ZStack {
            TabView {
                NavigationStack { HomeV9View(showPalette: $palette) }.tabItem { Label("Home", systemImage: "sparkles") }
                NavigationStack { NexusV9GlobalSearchView() }.tabItem { Label("Search", systemImage: "magnifyingglass") }
                NavigationStack { NexusV9FilesHubView() }.tabItem { Label("Files", systemImage: "folder.fill") }
                NavigationStack { NexusV9InsightInboxView() }.tabItem { Label("Insights", systemImage: "lightbulb.max.fill") }
                NavigationStack { AskV9View() }.tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right.fill") }
            }
            .tint(.cyan)
            .preferredColorScheme(.dark)
            if showSplash { NexusSplashV9().transition(.opacity) }
        }
        .task {
            await intelligence.index(records: model.records, files: NexusV8FileLibrary.shared.files)
            if intelligence.performanceMode != .battery { await intelligence.warmBestLocalModel() }
            try? await Task.sleep(for: .seconds(1.15)); withAnimation(.easeOut(duration: 0.3)) { showSplash = false }
        }
        .onOpenURL { NexusV9DeepLink.shared.handle($0, model: model) }
        .sheet(isPresented: $palette) { NavigationStack { NexusV9CommandPaletteView() } }
    }
}

struct NexusSplashV9: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .indigo.opacity(0.72), .cyan.opacity(0.18), .black], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Circle().fill(.cyan.opacity(0.16)).frame(width: 380, height: 380).blur(radius: 40).scaleEffect(pulse ? 1.10 : 0.86)
            VStack(spacing: 18) {
                ZStack { RoundedRectangle(cornerRadius: 32).fill(.ultraThinMaterial).frame(width: 120,height:120); Image(systemName:"brain.head.profile.fill").font(.system(size:50,weight:.bold)).foregroundStyle(.cyan); Image(systemName:"network").foregroundStyle(.white).offset(x:33,y:35) }
                Text("NEXUS").font(.system(size:42,weight:.black,design:.rounded)).tracking(8)
                Text("\(NexusBuildInfo.versionLabel) • \(NexusBuildInfo.productSubtitle)").font(.caption.bold()).tracking(1.3).foregroundStyle(.cyan)
                Text("Memory • files • models • actions • provenance").font(.caption2).foregroundStyle(.secondary)
            }
        }.onAppear { withAnimation(.easeInOut(duration:1).repeatForever(autoreverses:true)){pulse=true} }
    }
}

struct HomeV9View: View {
    @EnvironmentObject var model: NexusModel
    @ObservedObject private var intelligence = NexusV9IntelligenceStore.shared
    @ObservedObject private var files = NexusV8FileLibrary.shared
    @Binding var showPalette: Bool
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:14) {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        HStack(alignment:.firstTextBaseline,spacing:10) {
                            Text("NEXUS").font(.largeTitle.weight(.black))
                            NexusVersionBadge()
                        }
                        Text(NexusBuildInfo.productSubtitle).font(.caption.bold()).foregroundStyle(.cyan)
                        Text("One local-first memory and reasoning layer across files, conversations, projects, graph, timeline and actions.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showPalette=true } label: { Image(systemName:"command.circle.fill").font(.largeTitle) }
                }
                HStack(spacing:8){metric("Evidence","\(intelligence.chunks.count)","square.stack.3d.up.fill");metric("Files","\(files.files.count)","folder.fill");metric("Insights","\(intelligence.insights.count)","lightbulb.fill");metric("Build",NexusBuildInfo.versionLabel,"hammer.fill")}
                NavigationLink { AskV9View() } label: { card("Universal AI Memory","Fast streaming chat over compact hybrid retrieval, semantic caching, context tray, projects and evidence citations.","brain.head.profile.fill",.cyan) }.buttonStyle(.plain)
                NavigationLink { NexusV9GlobalSearchView() } label: { card("Semantic Search","Search files, records and memory using embeddings + keywords + recency + learned reranking.","magnifyingglass.circle.fill",.mint) }.buttonStyle(.plain)
                NavigationLink { NexusProductivityHubView() } label: { card("Productivity Hub","Pin important files, browse recents, use tags, capture clipboard text, check data health and reach backup/maintenance tools quickly.","bolt.horizontal.circle.fill",.green) }.buttonStyle(.plain)
                NavigationLink { NexusV9InsightInboxView() } label: { card("Insight Inbox","Deduplicated evolving insights, evidence strength, provenance and change detection.","sparkles.rectangle.stack.fill",.yellow) }.buttonStyle(.plain)
                NavigationLink { NexusV9DashboardView() } label: { card("Generated Dashboards & Mini Apps","Turn local evidence into trackers, timelines, calculators, quizzes, comparisons and dashboards.","rectangle.3.group.fill",.purple) }.buttonStyle(.plain)
                NavigationLink { NexusV9MoreView() } label: { card("All Systems","Graph 2.0, timeline, automation, capture, voice, privacy, exports, performance, agent actions and platform tools.","square.grid.3x3.fill",.orange) }.buttonStyle(.plain)
                if !model.importStatus.isEmpty { Text(model.importStatus).font(.caption).foregroundStyle(.green).v7Panel() }
            }.padding()
        }.navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
    }
    private func metric(_ title:String,_ value:String,_ symbol:String)->some View { VStack(alignment:.leading,spacing:4){Image(systemName:symbol).foregroundStyle(.cyan);Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.5);Text(title).font(.caption2).foregroundStyle(.secondary)}.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.thinMaterial,in:RoundedRectangle(cornerRadius:17)) }
    private func card(_ title:String,_ detail:String,_ symbol:String,_ color:Color)->some View { HStack(spacing:12){ZStack{RoundedRectangle(cornerRadius:18).fill(color.opacity(0.16)).frame(width:58,height:58);Image(systemName:symbol).font(.title2).foregroundStyle(color)};VStack(alignment:.leading,spacing:3){Text(title).font(.headline);Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)};Spacer();Image(systemName:"chevron.right").foregroundStyle(.tertiary)}.v7Panel() }
}

struct NexusV9FilesHubView: View {
    @EnvironmentObject var model:NexusModel
    @ObservedObject private var library=NexusV8FileLibrary.shared
    @ObservedObject private var intelligence=NexusV9IntelligenceStore.shared
    @ObservedObject private var metadata=NexusFileMetadataStore.shared
    @State private var importer=false
    @State private var errorText=""
    @State private var pendingDelete:NexusV8FileItem?

    var body: some View {
        List {
            Section {
                Button { importer=true } label:{Label("Import files",systemImage:"square.and.arrow.down")}
                NavigationLink("Organized Library"){NexusOrganizedLibraryView()}
                NavigationLink("Compare / What Changed?"){NexusV9CompareFilesView()}
                NavigationLink("Watch folders"){NexusV9WatchFoldersView()}
                NavigationLink("Camera & Photos"){NexusV9CaptureView()}
                NavigationLink("Research capture"){NexusV9ResearchView()}
                Text(intelligence.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("Library") {
                if library.files.isEmpty {
                    ContentUnavailableView("No files yet", systemImage:"folder", description:Text("Import files, scan a document, add photos, or capture research to start building your local library."))
                }
                ForEach(library.files) { file in
                    NavigationLink {
                        NexusV9FileIntelligenceView(item:file).onAppear { metadata.markRecent(file) }
                    } label:{
                        HStack{
                            Image(systemName:file.kindLabel=="Image" ? "photo.fill" : file.ext=="pdf" ? "doc.richtext.fill" : ["csv","tsv"].contains(file.ext) ? "tablecells.fill" : "doc.fill").foregroundStyle(.cyan)
                            VStack(alignment:.leading){Text(file.name).font(.headline);Text(NexusV8FileSupport.metadata(file)).font(.caption).foregroundStyle(.secondary)}
                        }
                    }
                }.onDelete { offsets in
                    for i in offsets where i < library.files.count {
                        let file=library.files[i]
                        if metadata.confirmDestructiveActions { pendingDelete=file }
                        else { deleteFile(file) }
                    }
                }
            }
            Section("File actions") {
                NavigationLink("Productivity Hub"){NexusProductivityHubView()}
                NavigationLink("Local Agent organization"){NexusV9AgentView()}
                NavigationLink("Storage Manager"){NexusV9StorageView()}
            }
        }.navigationTitle("Files")
        .fileImporter(isPresented:$importer,allowedContentTypes:[.data,.image,.pdf,.plainText,.commaSeparatedText],allowsMultipleSelection:true){result in do{let urls=try result.get();let imported=try library.importURLs(urls);intelligence.runAutomations(for:.fileImport,importedNames:imported.map(\.name));Task{await intelligence.index(records:model.records,files:library.files)}}catch{errorText=error.localizedDescription}}
        .alert("Import failed",isPresented:Binding(get:{!errorText.isEmpty},set:{if !$0{errorText=""}})){Button("OK"){errorText=""}}message:{Text(errorText)}
        .alert("Delete imported file?",isPresented:Binding(get:{pendingDelete != nil},set:{if !$0{pendingDelete=nil}})){
            Button("Delete",role:.destructive){if let file=pendingDelete{deleteFile(file)};pendingDelete=nil}
            Button("Cancel",role:.cancel){pendingDelete=nil}
        }message:{Text("This removes NEXUS’s local copy and its search evidence. The original source outside NEXUS is not deleted.")}
    }

    private func deleteFile(_ file:NexusV8FileItem){
        intelligence.forgetSource(file.id.uuidString)
        library.remove(file)
        let valid=Set(library.files.map{$0.id.uuidString})
        NexusNiceFeaturesStore.shared.favoriteFileIDs=NexusNiceFeaturesStore.shared.favoriteFileIDs.intersection(valid)
        metadata.prune(validIDs:valid)
    }
}

struct NexusV9MoreView: View {
    var body: some View {
        List {
            Section("Productivity") { NavigationLink("Productivity Hub"){NexusProductivityHubView()};NavigationLink("Organized Library"){NexusOrganizedLibraryView()};NavigationLink("Recent Files"){NexusRecentFilesView()};NavigationLink("Tags"){NexusTagBrowserView()};NavigationLink("Settings & Maintenance"){NexusSettingsHubView()} }
            Section("Knowledge OS") { NavigationLink("Projects & conversation branches"){NexusV9WorkspacesView()};NavigationLink("Knowledge Graph 2.0"){NexusV9Graph2View()};NavigationLink("Universal Timeline"){NexusV9Timeline2View()};NavigationLink("Personal Change Detection"){NexusV9ChangeDetectionView()};NavigationLink("Dashboards & Mini Apps"){NexusV9DashboardView()} }
            Section("Files & capture") { NavigationLink("Compare / What Changed?"){NexusV9CompareFilesView()};NavigationLink("Watch Folders"){NexusV9WatchFoldersView()};NavigationLink("Camera & Photos"){NexusV9CaptureView()};NavigationLink("Web Research Capture"){NexusV9ResearchView()} }
            Section("Automation & actions") { NavigationLink("Natural-language Automations"){NexusV9AutomationsView()};NavigationLink("Local Agent Actions + Undo"){NexusV9AgentView()};NavigationLink("Plugin Architecture"){NexusV9PluginView()} }
            Section("Multimodal & models") { NavigationLink("Voice Conversation"){NexusV9VoiceView()};NavigationLink("Shared Language Models"){PortableModelsV8View()};NavigationLink("Vision Model Manager"){MultimodalLabV8View()};NavigationLink("Performance & Diagnostics"){NexusV9PerformanceView()} }
            Section("Privacy & portability") { NavigationLink("Privacy & Security"){NexusV9SecurityView()};NavigationLink("Storage Manager"){NexusV9StorageView()};NavigationLink("Backup & Restore"){NexusPortableBackupView()};NavigationLink("Reports & Intelligence Package"){NexusV9ExportView()} }
            Section("Legacy deep labs") { NavigationLink("Personality Lab"){PersonalityLabV7View()};NavigationLink("Living Storybook"){StorybookV7View()};NavigationLink("Conversation Twin"){ConversationTwinV7View()};NavigationLink("Decision Lab"){DecisionLabV6View()} }
        }.navigationTitle("All Systems")
    }
}

struct NexusV9Command: Identifiable { let id=UUID();let title:String;let subtitle:String;let symbol:String;let destination:AnyView }
struct NexusV9CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    private var commands:[NexusV9Command] {[
        .init(title:"Chat",subtitle:"Ask across local memory",symbol:"bubble.left.fill",destination:AnyView(AskV9View())),
        .init(title:"Search Everything",subtitle:"Hybrid semantic search",symbol:"magnifyingglass",destination:AnyView(NexusV9GlobalSearchView())),
        .init(title:"Productivity Hub",subtitle:"Favorites, recents, tags, backup and maintenance",symbol:"bolt.horizontal.circle.fill",destination:AnyView(NexusProductivityHubView())),
        .init(title:"Organized Library",subtitle:"Search, pin, tag and sort local files",symbol:"folder.badge.gearshape",destination:AnyView(NexusOrganizedLibraryView())),
        .init(title:"Files",subtitle:"View and analyze local files",symbol:"folder.fill",destination:AnyView(NexusV9FilesHubView())),
        .init(title:"Insights",subtitle:"Evidence-backed discoveries",symbol:"lightbulb.fill",destination:AnyView(NexusV9InsightInboxView())),
        .init(title:"Graph 2.0",subtitle:"Entities and relationships",symbol:"network",destination:AnyView(NexusV9Graph2View())),
        .init(title:"Timeline",subtitle:"Chronological evidence",symbol:"clock.fill",destination:AnyView(NexusV9Timeline2View())),
        .init(title:"Dashboards",subtitle:"Generated mini apps",symbol:"chart.bar.fill",destination:AnyView(NexusV9DashboardView())),
        .init(title:"Automations",subtitle:"Local rules and actions",symbol:"gearshape.2.fill",destination:AnyView(NexusV9AutomationsView())),
        .init(title:"Capture",subtitle:"Camera, photos and documents",symbol:"camera.fill",destination:AnyView(NexusV9CaptureView())),
        .init(title:"Research",subtitle:"Save webpages offline",symbol:"safari.fill",destination:AnyView(NexusV9ResearchView())),
        .init(title:"Voice",subtitle:"Speak to NEXUS",symbol:"mic.fill",destination:AnyView(NexusV9VoiceView())),
        .init(title:"Backup & Restore",subtitle:"Portable validated NEXUS backup",symbol:"archivebox.fill",destination:AnyView(NexusPortableBackupView())),
        .init(title:"Performance",subtitle:"Benchmark and diagnostics",symbol:"gauge.with.dots.needle.67percent",destination:AnyView(NexusV9PerformanceView()))]}
    var body: some View { List { Section { TextField("Type a command",text:$query).textInputAutocapitalization(.never) }; ForEach(filtered) { command in NavigationLink { command.destination } label:{Label{VStack(alignment:.leading){Text(command.title).font(.headline);Text(command.subtitle).font(.caption).foregroundStyle(.secondary)}}icon:{Image(systemName:command.symbol).foregroundStyle(.cyan)}} } }.navigationTitle("Command Palette").toolbar{ToolbarItem(placement:.topBarTrailing){Button("Done"){dismiss()}}} }
    private var filtered:[NexusV9Command] { query.isEmpty ? commands : commands.filter { ($0.title+" "+$0.subtitle).localizedCaseInsensitiveContains(query) } }
}
