import SwiftUI

struct RootView: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        switch game.screen {
        case .world: WorldView()
        case .collection: CollectionView()
        case .quests: QuestView()
        }
    }
}
