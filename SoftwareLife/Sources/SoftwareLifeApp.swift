import SwiftUI

@main
struct SoftwareLifeApp: App {
    @StateObject private var game = GameState.demo()

    var body: some Scene {
        WindowGroup {
            GameRootView()
                .environmentObject(game)
                .task(id: game.currentPlayerIndex) {
                    await game.autoplayCurrentTurn()
                }
        }
    }
}
