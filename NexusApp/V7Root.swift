import SwiftUI

struct RootV7EnhancedView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TabView {
                NavigationStack { HomeV7View() }
                    .tabItem { Label("Home", systemImage: "sparkles") }
                NavigationStack { ConnectHubV7View() }
                    .tabItem { Label("Connect", systemImage: "arrow.triangle.2.circlepath.circle.fill") }
                NavigationStack { ExploreHubV7View() }
                    .tabItem { Label("Explore", systemImage: "book.pages.fill") }
                NavigationStack { KnowledgeGraphV3View() }
                    .tabItem { Label("Graph", systemImage: "network") }
                NavigationStack { AskV7View() }
                    .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right.fill") }
            }
            .tint(.cyan)
            .preferredColorScheme(.dark)

            VStack { OperationBannerV7(); Spacer() }.allowsHitTesting(false)

            if showSplash { NexusSplashV7().transition(.opacity) }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
    }
}
