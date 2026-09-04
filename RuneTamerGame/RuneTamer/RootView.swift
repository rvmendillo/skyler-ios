import SwiftUI

struct RootView: View {
    @EnvironmentObject var game: GameState
    @State private var showSplash = true

    var body: some View {
        ZStack {
            switch game.screen {
            case .world: WorldView()
            case .collection: CollectionView()
            case .quests: QuestView()
            }

            if showSplash {
                RuneTamerSplash()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .zIndex(10)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                withAnimation(.easeInOut(duration: 0.55)) {
                    showSplash = false
                }
            }
        }
    }
}
