import Foundation

extension GameState {
    /// Runs exactly one rival turn after a short presentation delay.
    /// GameRootView remains responsible for human decisions; the app-level
    /// task restarts whenever currentPlayerIndex changes, creating a clean
    /// chain through consecutive AI players without blocking the UI.
    func autoplayCurrentTurn() async {
        guard !isHumanTurn,
              gameOverMessage == nil,
              dealOffer == nil,
              !players.isEmpty else { return }

        let expectedPlayerID = currentPlayer.id

        // Keep the previous result visible long enough to read, similar to a
        // premium digital tabletop game's camera/action beat between turns.
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !Task.isCancelled,
              !isHumanTurn,
              gameOverMessage == nil,
              dealOffer == nil,
              currentPlayer.id == expectedPlayerID else { return }

        // Let each rival action get its own event card rather than stacking
        // over the previous player's result.
        currentEvent = nil
        rollAndAdvance()
    }
}
