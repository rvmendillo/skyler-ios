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
                currentEvent = IndustryEvent(id: UUID(), title: "Home Base", body: "You trade liquidity for a more stable asset.", cashDelta: -cost, reputationDelta: 0, wellbeingDelta: 3, equityPercentChange: 0)
            }
        case .skill:
            players[currentPlayerIndex].skill += 2
            players[currentPlayerIndex].cash -= min(players[currentPlayerIndex].cash, 3_000)
            currentEvent = IndustryEvent(id: UUID(), title: "Skill Upgrade", body: "You invest time and money into a capability that compounds.", cashDelta: -3_000, reputationDelta: 0, wellbeingDelta: -1, equityPercentChange: 0)
        case .sideProject:
            players[currentPlayerIndex].recurringIncome += 1_500
            players[currentPlayerIndex].reputation += 1
            players[currentPlayerIndex].wellbeing -= 2
            currentEvent = IndustryEvent(id: UUID(), title: "Side Project", body: "A small build starts generating recurring income.", cashDelta: 0, reputationDelta: 1, wellbeingDelta: -2, equityPercentChange: 0)
        case .event:
            triggerRandomEvent()
        case .wellbeing:
            players[currentPlayerIndex].wellbeing = min(100, players[currentPlayerIndex].wellbeing + 10)
            players[currentPlayerIndex].cash -= min(players[currentPlayerIndex].cash, 2_000)
            currentEvent = IndustryEvent(id: UUID(), title: "Reset Week", body: "You step back before burnout becomes expensive.", cashDelta: -2_000, reputationDelta: 0, wellbeingDelta: 10, equityPercentChange: 0)
        case .openSource:
            players[currentPlayerIndex].reputation += 3
            players[currentPlayerIndex].skill += 1
            currentEvent = IndustryEvent(id: UUID(), title: "Open Source Win", body: "A useful contribution earns trust across the ecosystem.", cashDelta: 0, reputationDelta: 3, wellbeingDelta: 0, equityPercentChange: 0)
        case .aiFrontier:
            players[currentPlayerIndex].skill += 1
            let delta = era == .aiAcceleration ? 12_000 : 4_000
            players[currentPlayerIndex].cash += delta
            currentEvent = IndustryEvent(id: UUID(), title: "AI Leverage", body: "You turn new tooling into a real productivity advantage.", cashDelta: delta, reputationDelta: 1, wellbeingDelta: 0, equityPercentChange: 0)
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
            IndustryEvent(id: UUID(), title: "Acquisition Offer", body: "A fictional platform acquires a small product you backed.", cashDelta: 25_000, reputationDelta: 2, wellbeingDelta: 3, equityPercentChange: 20),
            IndustryEvent(id: UUID(), title: "Framework Migration", body: "A major platform shift forces a rewrite, but your new skills become more valuable.", cashDelta: -4_000, reputationDelta: 2, wellbeingDelta: -3, equityPercentChange: 3),
            IndustryEvent(id: UUID(), title: "Remote Work Boom", body: "Global hiring opens a better-paying role without a relocation.", cashDelta: 10_000, reputationDelta: 1, wellbeingDelta: 5, equityPercentChange: 4),
            IndustryEvent(id: UUID(), title: "Security Incident", body: "A supply-chain vulnerability hits the industry and valuations wobble.", cashDelta: -3_000, reputationDelta: 0, wellbeingDelta: -5, equityPercentChange: -8)
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
            .init(id: 0, title: "Launch Pad", kind: .skill, subtitle: "Choose your first specialization"),
            .init(id: 1, title: "Internship", kind: .career, subtitle: "Turn learning into leverage"),
            .init(id: 2, title: "Hackathon", kind: .sideProject, subtitle: "Build something in a weekend"),
            .init(id: 3, title: "First Job", kind: .career, subtitle: "Ship, learn, negotiate"),
            .init(id: 4, title: "Rent & Bills", kind: .property, subtitle: "Real life starts charging monthly"),
            .init(id: 5, title: "Open Source", kind: .openSource, subtitle: "Reputation compounds publicly"),
            .init(id: 6, title: "Startup Offer", kind: .startup, subtitle: "Salary versus upside"),
            .init(id: 7, title: "Market Rally", kind: .market, subtitle: "Risk assets wake up"),
            .init(id: 8, title: "Certification", kind: .skill, subtitle: "Upgrade your toolkit"),
            .init(id: 9, title: "Production Fire", kind: .event, subtitle: "Everything is urgent now"),
            .init(id: 10, title: "Promotion", kind: .career, subtitle: "More scope, more pay"),
            .init(id: 11, title: "Wellbeing Park", kind: .wellbeing, subtitle: "Recover before burnout"),
            .init(id: 12, title: "AI Boom", kind: .aiFrontier, subtitle: "Automation changes the field"),
            .init(id: 13, title: "Side SaaS", kind: .sideProject, subtitle: "Recurring revenue begins"),
            .init(id: 14, title: "Home Base", kind: .property, subtitle: "Build stability outside work"),
            .init(id: 15, title: "Layoff Wave", kind: .event, subtitle: "Cash reserves suddenly matter"),
            .init(id: 16, title: "Job Hop", kind: .career, subtitle: "Trade comfort for acceleration"),
            .init(id: 17, title: "Seed Round", kind: .startup, subtitle: "Ownership gets diluted or multiplied"),
            .init(id: 18, title: "Cloud Migration", kind: .skill, subtitle: "Learn the new stack"),
            .init(id: 19, title: "Open Source Fame", kind: .openSource, subtitle: "Your name travels farther than you do"),
            .init(id: 20, title: "Tech Correction", kind: .market, subtitle: "Valuations reset"),
            .init(id: 21, title: "Sabbatical", kind: .wellbeing, subtitle: "Time can be an asset too"),
            .init(id: 22, title: "Founder Path", kind: .startup, subtitle: "Control rises, certainty falls"),
            .init(id: 23, title: "Security Crisis", kind: .event, subtitle: "A zero-day reshuffles priorities"),
            .init(id: 24, title: "Staff Engineer", kind: .career, subtitle: "Influence without leaving the craft"),
            .init(id: 25, title: "AI Platform", kind: .aiFrontier, subtitle: "Build on the new primitive"),
            .init(id: 26, title: "Investment District", kind: .market, subtitle: "Capital starts working for you"),
            .init(id: 27, title: "Property Upgrade", kind: .property, subtitle: "Turn income into durable assets"),
            .init(id: 28, title: "Acquisition", kind: .event, subtitle: "A strategic buyer comes calling"),
            .init(id: 29, title: "Legacy Summit", kind: .openSource, subtitle: "Wealth, impact, health, and craft all count")
        ]

        let names = ["You", "Mika", "Andre", "Lia"]
        let startingPositions = [0, 0, 0, 0]
        let players = names.enumerated().map { index, name in
            Player(id: UUID(), name: name, cash: 60_000, salary: 35_000, reputation: 5, wellbeing: 80, skill: 3, position: startingPositions[index], recurringIncome: 0, equityValue: 20_000, propertyValue: 0)
        }
        return GameState(players: players, board: tiles)
    }
}
