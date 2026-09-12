import Foundation

@MainActor
final class GameState: ObservableObject {
    @Published var players: [Player]
    @Published var currentPlayerIndex: Int = 0
    @Published var era: IndustryEra = .hiringBoom
    @Published var lastRoll: Int = 0
    @Published var turn: Int = 1
    @Published var currentEvent: IndustryEvent?

    let board: [BoardTile]

    init(players: [Player], board: [BoardTile]) {
        self.players = players
        self.board = board
    }

    var currentPlayer: Player { players[currentPlayerIndex] }

    func rollAndAdvance() {
        let roll = Int.random(in: 1...6)
        lastRoll = roll
        players[currentPlayerIndex].position = (players[currentPlayerIndex].position + roll) % board.count
        resolve(tile: board[players[currentPlayerIndex].position])
        advanceTurn()
    }

    private func resolve(tile: BoardTile) {
        switch tile.kind {
        case .career:
            let gain = Int(Double(8_000) * era.salaryMultiplier)
            players[currentPlayerIndex].salary += gain
            players[currentPlayerIndex].cash += gain
            players[currentPlayerIndex].skill += 1
            currentEvent = IndustryEvent(id: UUID(), title: "Promotion Cycle", body: "A strong review turns into a better compensation package.", cashDelta: gain, reputationDelta: 1, wellbeingDelta: -1, equityPercentChange: 0)
        case .startup:
            let change = Int(Double.random(in: -0.25...0.60) * 100)
            applyEquity(percent: change)
            currentEvent = IndustryEvent(id: UUID(), title: change >= 0 ? "Funding Round" : "Runway Crisis", body: change >= 0 ? "A fictional startup in your portfolio closes a strong round." : "A portfolio startup misses growth targets and is repriced.", cashDelta: 0, reputationDelta: change >= 0 ? 1 : 0, wellbeingDelta: -1, equityPercentChange: change)
        case .market:
            let change = Int.random(in: -18...24)
            applyEquity(percent: change)
            currentEvent = IndustryEvent(id: UUID(), title: "Market Repricing", body: "Software valuations move as rates, growth expectations, and investor appetite change.", cashDelta: 0, reputationDelta: 0, wellbeingDelta: 0, equityPercentChange: change)
        case .property:
            let cost = 20_000
            if players[currentPlayerIndex].cash >= cost {
                players[currentPlayerIndex].cash -= cost
                players[currentPlayerIndex].propertyValue += 24_000
            }
        case .skill:
            players[currentPlayerIndex].skill += 2
            players[currentPlayerIndex].cash -= min(players[currentPlayerIndex].cash, 3_000)
        case .sideProject:
            players[currentPlayerIndex].recurringIncome += 1_500
            players[currentPlayerIndex].reputation += 1
            players[currentPlayerIndex].wellbeing -= 2
        case .event:
            triggerRandomEvent()
        case .wellbeing:
            players[currentPlayerIndex].wellbeing = min(100, players[currentPlayerIndex].wellbeing + 10)
            players[currentPlayerIndex].cash -= min(players[currentPlayerIndex].cash, 2_000)
        case .openSource:
            players[currentPlayerIndex].reputation += 3
            players[currentPlayerIndex].skill += 1
        case .aiFrontier:
            players[currentPlayerIndex].skill += 1
            let delta = era == .aiAcceleration ? 12_000 : 4_000
            players[currentPlayerIndex].cash += delta
        }
    }

    private func applyEquity(percent: Int) {
        let value = players[currentPlayerIndex].equityValue
        players[currentPlayerIndex].equityValue = max(0, value + (value * percent / 100))
    }

    private func triggerRandomEvent() {
        let events = [
            IndustryEvent(id: UUID(), title: "Production Outage", body: "A cascading incident consumes the weekend. Reputation survives, wellbeing does not.", cashDelta: -2_000, reputationDelta: 1, wellbeingDelta: -8, equityPercentChange: -3),
            IndustryEvent(id: UUID(), title: "Viral Launch", body: "Your side project catches attention and recurring revenue jumps.", cashDelta: 12_000, reputationDelta: 4, wellbeingDelta: -2, equityPercentChange: 5),
            IndustryEvent(id: UUID(), title: "Layoff Wave", body: "A broad restructuring hits the sector. Cash buffer matters more than title.", cashDelta: -8_000, reputationDelta: 0, wellbeingDelta: -7, equityPercentChange: -10),
            IndustryEvent(id: UUID(), title: "Open Source Breakthrough", body: "A library contribution becomes widely adopted.", cashDelta: 2_000, reputationDelta: 6, wellbeingDelta: 2, equityPercentChange: 2),
            IndustryEvent(id: UUID(), title: "Acquisition Offer", body: "A fictional platform acquires a small product you backed.", cashDelta: 25_000, reputationDelta: 2, wellbeingDelta: 3, equityPercentChange: 20)
        ]
        let event = events.randomElement()!
        players[currentPlayerIndex].cash = max(0, players[currentPlayerIndex].cash + event.cashDelta)
        players[currentPlayerIndex].reputation += event.reputationDelta
        players[currentPlayerIndex].wellbeing = max(0, min(100, players[currentPlayerIndex].wellbeing + event.wellbeingDelta))
        applyEquity(percent: event.equityPercentChange)
        currentEvent = event
    }

    private func advanceTurn() {
        players[currentPlayerIndex].cash += players[currentPlayerIndex].recurringIncome
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
        if currentPlayerIndex == 0 {
            turn += 1
            if turn % 6 == 0 {
                era = IndustryEra.allCases.randomElement() ?? era
            }
        }
    }

    static func demo() -> GameState {
        let tiles: [BoardTile] = [
            .init(id: 0, title: "Campus Row", kind: .skill, subtitle: "Learn something that compounds"),
            .init(id: 1, title: "First Job", kind: .career, subtitle: "Ship, learn, negotiate"),
            .init(id: 2, title: "Startup Alley", kind: .startup, subtitle: "High variance, high upside"),
            .init(id: 3, title: "Open Source Commons", kind: .openSource, subtitle: "Reputation can become leverage"),
            .init(id: 4, title: "Market Exchange", kind: .market, subtitle: "Valuations move faster than fundamentals"),
            .init(id: 5, title: "Residential Loop", kind: .property, subtitle: "Stability has an opportunity cost"),
            .init(id: 6, title: "Creator Quarter", kind: .sideProject, subtitle: "Build recurring income"),
            .init(id: 7, title: "Industry Event", kind: .event, subtitle: "The market does not ask permission"),
            .init(id: 8, title: "Cloud Heights", kind: .career, subtitle: "Scale brings rewards and incidents"),
            .init(id: 9, title: "Wellbeing Park", kind: .wellbeing, subtitle: "Burnout is a balance-sheet liability"),
            .init(id: 10, title: "AI Frontier", kind: .aiFrontier, subtitle: "Adapt or become commoditized"),
            .init(id: 11, title: "Platform Shift", kind: .event, subtitle: "The rules change again")
        ]

        let names = ["You", "Mika", "Andre", "Lia"]
        let players = names.enumerated().map { index, name in
            Player(id: UUID(), name: name, cash: 60_000, salary: 35_000, reputation: 5, wellbeing: 80, skill: 3, position: index * 2, recurringIncome: 0, equityValue: 20_000, propertyValue: 0)
        }
        return GameState(players: players, board: tiles)
    }
}
