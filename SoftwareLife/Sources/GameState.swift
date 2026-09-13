import SwiftUI

@MainActor
final class GameState: ObservableObject {
    @Published var players: [Player]
    @Published var currentPlayerIndex: Int = 0
    @Published var era: IndustryEra = .hiringBoom
    @Published var lastRoll: Int = 0
    @Published var turn: Int = 1
    @Published var currentEvent: IndustryEvent?
    @Published var dealOffer: DealOffer?
    @Published var owners: [Int: UUID] = [:]
    @Published var scaleLevels: [Int: Int] = [:]
    @Published var gameOverMessage: String?

    let board: [BoardTile]

    init(players: [Player], board: [BoardTile]) {
        self.players = players
        self.board = board
    }

    var currentPlayer: Player { players[currentPlayerIndex] }
    var currentTile: BoardTile { board[currentPlayer.position] }
    var isHumanTurn: Bool { currentPlayerIndex == 0 }

    func netWorth(for player: Player) -> Int {
        player.cash + player.equityValue + player.propertyValue + portfolioValue(for: player.id)
    }

    func legacyScore(for player: Player) -> Int {
        netWorth(for: player)
        + player.reputation * 1_000
        + player.wellbeing * 700
        + player.skill * 900
        + player.recurringIncome * 10
    }

    func portfolioValue(for playerID: UUID) -> Int {
        board.filter { owners[$0.id] == playerID }.reduce(0) { partial, tile in
            let level = scaleLevels[tile.id, default: 0]
            let upgradeValue = (0..<level).reduce(0) { sum, step in
                sum + scaleCost(for: tile, nextLevel: step + 1)
            }
            return partial + tile.purchasePrice + upgradeValue
        }
    }

    func ownedProjects(for playerID: UUID) -> [BoardTile] {
        board.filter { owners[$0.id] == playerID }
    }

    func ownerName(for tileID: Int) -> String? {
        guard let ownerID = owners[tileID] else { return nil }
        return players.first(where: { $0.id == ownerID })?.name
    }

    func scaleLevel(for tileID: Int) -> Int {
        scaleLevels[tileID, default: 0]
    }

    func ownsDistrict(playerID: UUID, district: TechDistrict) -> Bool {
        let districtTiles = board.filter { $0.district == district && $0.isOwnable }
        return !districtTiles.isEmpty && districtTiles.allSatisfy { owners[$0.id] == playerID }
    }

    func revenue(for tile: BoardTile, levelOverride: Int? = nil) -> Int {
        guard tile.isOwnable else { return 0 }
        let level = levelOverride ?? scaleLevels[tile.id, default: 0]
        var multiplier = 1.0 + Double(level) * 1.65
        if let district = tile.district,
           let ownerID = owners[tile.id],
           ownsDistrict(playerID: ownerID, district: district) {
            multiplier *= 2.0
        }
        return max(tile.baseRevenue, Int(Double(tile.baseRevenue) * multiplier * era.revenueMultiplier))
    }

    func scaleCost(for tile: BoardTile, nextLevel: Int? = nil) -> Int {
        let targetLevel = nextLevel ?? (scaleLevels[tile.id, default: 0] + 1)
        return max(10_000, tile.purchasePrice / 2 + (targetLevel - 1) * tile.purchasePrice / 5)
    }

    func rollAndAdvance() {
        guard dealOffer == nil, gameOverMessage == nil, !players.isEmpty else { return }

        if players[currentPlayerIndex].bankrupt {
            advanceTurn()
            return
        }

        if players[currentPlayerIndex].skippedTurns > 0 {
            players[currentPlayerIndex].skippedTurns -= 1
            currentEvent = event(
                title: "On-Call Recovery",
                body: "A brutal incident rotation consumes this sprint. You recover instead of moving.",
                wellbeing: 4
            )
            finishTurn()
            return
        }

        let roll = Int.random(in: 1...6)
        lastRoll = roll
        let oldPosition = players[currentPlayerIndex].position
        let rawPosition = oldPosition + roll

        if rawPosition >= board.count {
            collectLaunchPayout()
        }

        players[currentPlayerIndex].position = rawPosition % board.count
        resolveLanding(on: board[players[currentPlayerIndex].position])
    }

    func acceptDeal() {
        guard let offer = dealOffer,
              let tile = board.first(where: { $0.id == offer.tileID }),
              !players[currentPlayerIndex].bankrupt else {
            dealOffer = nil
            return
        }

        switch offer.kind {
        case .acquire:
            guard owners[tile.id] == nil, players[currentPlayerIndex].cash >= offer.cost else {
                currentEvent = event(title: "Deal Fell Through", body: "The acquisition could not be funded.")
                dealOffer = nil
                finishTurn()
                return
            }
            players[currentPlayerIndex].cash -= offer.cost
            players[currentPlayerIndex].reputation += 1
            owners[tile.id] = players[currentPlayerIndex].id
            currentEvent = event(
                title: "Product Acquired",
                body: "You acquired \(tile.title) for ₱\(offer.cost.formatted()). Rival engineers now pay usage revenue when they land here.",
                cash: -offer.cost,
                reputation: 1
            )

        case .scale:
            guard owners[tile.id] == players[currentPlayerIndex].id,
                  players[currentPlayerIndex].cash >= offer.cost,
                  scaleLevels[tile.id, default: 0] < 4 else {
                currentEvent = event(title: "Scaling Blocked", body: "The product cannot be scaled right now.")
                dealOffer = nil
                finishTurn()
                return
            }
            players[currentPlayerIndex].cash -= offer.cost
            scaleLevels[tile.id, default: 0] += 1
            players[currentPlayerIndex].reputation += 1
            let newLevel = scaleLevels[tile.id, default: 0]
            currentEvent = event(
                title: newLevel == 4 ? "Unicorn Scale" : "Production Scaled",
                body: "\(tile.title) reached scale level \(newLevel). Its usage revenue is now ₱\(revenue(for: tile).formatted()).",
                cash: -offer.cost,
                reputation: 1
            )
        }

        dealOffer = nil
        finishTurn()
    }

    func declineDeal() {
        guard let offer = dealOffer,
              let tile = board.first(where: { $0.id == offer.tileID }) else {
            dealOffer = nil
            return
        }

        currentEvent = event(
            title: offer.kind == .acquire ? "Acquisition Passed" : "Scaling Deferred",
            body: offer.kind == .acquire
                ? "You keep your cash and leave \(tile.title) available to another engineer."
                : "You postpone scaling \(tile.title) until a later lap."
        )
        dealOffer = nil
        finishTurn()
    }

    func restart() {
        let fresh = GameState.demo()
        players = fresh.players
        currentPlayerIndex = 0
        era = .hiringBoom
        lastRoll = 0
        turn = 1
        currentEvent = nil
        dealOffer = nil
        owners = [:]
        scaleLevels = [:]
        gameOverMessage = nil
    }

    private func resolveLanding(on tile: BoardTile) {
        if tile.isOwnable {
            resolveProject(tile)
            return
        }

        switch tile.kind {
        case .launch:
            players[currentPlayerIndex].cash += 10_000
            currentEvent = event(title: "Sprint Launch", body: "You ship a clean release and earn a ₱10,000 launch bonus.", cash: 10_000)

        case .career:
            let raise = Int(Double(8_000) * era.salaryMultiplier)
            players[currentPlayerIndex].salary += raise
            players[currentPlayerIndex].cash += 12_000
            players[currentPlayerIndex].skill += 1
            currentEvent = event(
                title: "Career Review",
                body: "Strong delivery increases your salary by ₱\(raise.formatted()) and pays a ₱12,000 bonus.",
                cash: 12_000,
                reputation: 1
            )

        case .incident:
            triggerRandomIncident()

        case .market:
            let change = Int.random(in: -18...25)
            applyEquity(percent: change)
            currentEvent = event(
                title: change >= 0 ? "Tech Rally" : "Valuation Reset",
                body: "Your market investments move \(change >= 0 ? "+" : "")\(change)% with the software sector.",
                equityPercent: change
            )

        case .skill:
            let cost = min(6_000, players[currentPlayerIndex].cash)
            players[currentPlayerIndex].cash -= cost
            players[currentPlayerIndex].skill += 2
            currentEvent = event(title: "Deep Work Lab", body: "A focused learning sprint improves your technical leverage.", cash: -cost)

        case .wellbeing:
            players[currentPlayerIndex].wellbeing = min(100, players[currentPlayerIndex].wellbeing + 14)
            currentEvent = event(title: "Offline Weekend", body: "No tickets, no deploys, no pager. Wellbeing recovers.", wellbeing: 14)

        case .openSource:
            players[currentPlayerIndex].reputation += 4
            players[currentPlayerIndex].skill += 1
            players[currentPlayerIndex].recurringIncome += 1_000
            currentEvent = event(title: "Open Source Breakthrough", body: "Your library gains adoption, reputation, and sponsorship income.", reputation: 4)

        case .aiFrontier:
            let gain = era == .aiAcceleration ? 18_000 : 8_000
            players[currentPlayerIndex].cash += gain
            players[currentPlayerIndex].skill += 1
            players[currentPlayerIndex].reputation += 1
            currentEvent = event(title: "AI Leverage", body: "You automate a painful workflow and monetize the productivity gain.", cash: gain, reputation: 1)

        case .tax:
            let fee = max(8_000, min(35_000, netWorth(for: players[currentPlayerIndex]) / 12))
            chargeCurrentPlayer(amount: fee, recipientID: nil)
            currentEvent = event(title: "Cloud & Compliance Bill", body: "Infrastructure, licenses, tax, and compliance cost ₱\(fee.formatted()).", cash: -fee)

        case .project:
            break
        }

        finishTurn()
    }

    private func resolveProject(_ tile: BoardTile) {
        let playerID = players[currentPlayerIndex].id

        guard let ownerID = owners[tile.id] else {
            let projected = tile.baseRevenue
            if isHumanTurn {
                dealOffer = DealOffer(tileID: tile.id, kind: .acquire, cost: tile.purchasePrice, projectedRevenue: projected)
            } else if shouldAIAcquire(tile) {
                players[currentPlayerIndex].cash -= tile.purchasePrice
                owners[tile.id] = playerID
                players[currentPlayerIndex].reputation += 1
                currentEvent = event(title: "Rival Acquisition", body: "\(players[currentPlayerIndex].name) acquired \(tile.title).")
                finishTurn()
            } else {
                currentEvent = event(title: "Rival Passed", body: "\(players[currentPlayerIndex].name) leaves \(tile.title) unowned.")
                finishTurn()
            }
            return
        }

        if ownerID == playerID {
            if let district = tile.district,
               ownsDistrict(playerID: playerID, district: district),
               scaleLevels[tile.id, default: 0] < 4 {
                let nextLevel = scaleLevels[tile.id, default: 0] + 1
                let cost = scaleCost(for: tile, nextLevel: nextLevel)
                let projected = revenue(for: tile, levelOverride: nextLevel)

                if isHumanTurn {
                    dealOffer = DealOffer(tileID: tile.id, kind: .scale, cost: cost, projectedRevenue: projected)
                } else if players[currentPlayerIndex].cash > cost * 2 {
                    players[currentPlayerIndex].cash -= cost
                    scaleLevels[tile.id, default: 0] = nextLevel
                    currentEvent = event(title: "Rival Scaled", body: "\(players[currentPlayerIndex].name) scaled \(tile.title) to level \(nextLevel).")
                    finishTurn()
                } else {
                    currentEvent = event(title: "Owned Product", body: "\(tile.title) is already in \(players[currentPlayerIndex].name)'s portfolio.")
                    finishTurn()
                }
            } else {
                currentEvent = event(title: "Owned Product", body: "\(tile.title) is already yours. Complete its district to unlock scaling.")
                finishTurn()
            }
            return
        }

        let fee = revenue(for: tile)
        let owner = players.first(where: { $0.id == ownerID })?.name ?? "another engineer"
        chargeCurrentPlayer(amount: fee, recipientID: ownerID)
        currentEvent = event(
            title: "Usage Revenue Paid",
            body: "You landed on \(owner)'s \(tile.title) and paid ₱\(fee.formatted()) in platform and licensing revenue.",
            cash: -fee
        )
        finishTurn()
    }

    private func shouldAIAcquire(_ tile: BoardTile) -> Bool {
        let player = players[currentPlayerIndex]
        if let district = tile.district {
            let alreadyOwnsSibling = board.contains { candidate in
                candidate.district == district && owners[candidate.id] == player.id
            }
            if alreadyOwnsSibling && player.cash >= tile.purchasePrice { return true }
        }
        return player.cash >= max(tile.purchasePrice * 2, 100_000)
    }

    private func collectLaunchPayout() {
        let salary = players[currentPlayerIndex].salary
        let passive = players[currentPlayerIndex].recurringIncome
        let payout = salary + passive
        players[currentPlayerIndex].cash += payout
    }

    private func chargeCurrentPlayer(amount: Int, recipientID: UUID?) {
        guard amount > 0 else { return }
        var remaining = amount
        var paid = 0

        let cashPaid = min(players[currentPlayerIndex].cash, remaining)
        players[currentPlayerIndex].cash -= cashPaid
        remaining -= cashPaid
        paid += cashPaid

        if remaining > 0 {
            let equityPaid = min(players[currentPlayerIndex].equityValue, remaining)
            players[currentPlayerIndex].equityValue -= equityPaid
            remaining -= equityPaid
            paid += equityPaid
        }

        if remaining > 0 {
            let propertyPaid = min(players[currentPlayerIndex].propertyValue, remaining)
            players[currentPlayerIndex].propertyValue -= propertyPaid
            remaining -= propertyPaid
            paid += propertyPaid
        }

        if let recipientID,
           let recipientIndex = players.firstIndex(where: { $0.id == recipientID }) {
            players[recipientIndex].cash += paid
        }

        if remaining > 0 {
            declareBankruptcy(for: currentPlayerIndex, creditorID: recipientID)
        }
    }

    private func declareBankruptcy(for index: Int, creditorID: UUID?) {
        let debtorID = players[index].id
        players[index].bankrupt = true
        players[index].cash = 0
        players[index].equityValue = 0
        players[index].propertyValue = 0

        let debtorTiles = owners.filter { $0.value == debtorID }.map(\.key)
        for tileID in debtorTiles {
            if let creditorID {
                owners[tileID] = creditorID
            } else {
                owners.removeValue(forKey: tileID)
                scaleLevels.removeValue(forKey: tileID)
            }
        }
    }

    private func triggerRandomIncident() {
        let incidents = [
            IndustryEvent(id: UUID(), title: "Production Outage", body: "A cascading failure burns the weekend and triggers emergency cloud spend.", cashDelta: -12_000, reputationDelta: 1, wellbeingDelta: -9, equityPercentChange: -3),
            IndustryEvent(id: UUID(), title: "Viral Launch", body: "A side product reaches the front page and sponsorships explode.", cashDelta: 24_000, reputationDelta: 4, wellbeingDelta: -2, equityPercentChange: 5),
            IndustryEvent(id: UUID(), title: "Layoff Wave", body: "A sector-wide restructuring hits compensation and confidence.", cashDelta: -18_000, reputationDelta: 0, wellbeingDelta: -8, equityPercentChange: -10),
            IndustryEvent(id: UUID(), title: "Critical CVE", body: "A dependency vulnerability forces an emergency patch and audit.", cashDelta: -10_000, reputationDelta: 1, wellbeingDelta: -5, equityPercentChange: -5),
            IndustryEvent(id: UUID(), title: "Acquisition Offer", body: "One of your private bets exits at a premium.", cashDelta: 32_000, reputationDelta: 2, wellbeingDelta: 3, equityPercentChange: 18),
            IndustryEvent(id: UUID(), title: "Framework Migration", body: "The ecosystem shifts. Your rewrite is painful but raises your skill ceiling.", cashDelta: -6_000, reputationDelta: 2, wellbeingDelta: -3, equityPercentChange: 3),
            IndustryEvent(id: UUID(), title: "Remote Hiring Boom", body: "A global contract lands without a relocation.", cashDelta: 20_000, reputationDelta: 2, wellbeingDelta: 4, equityPercentChange: 4),
            IndustryEvent(id: UUID(), title: "Scope Creep", body: "The sprint triples in size. Nobody remembers approving it.", cashDelta: -5_000, reputationDelta: 0, wellbeingDelta: -7, equityPercentChange: 0),
            IndustryEvent(id: UUID(), title: "Bug Bounty Jackpot", body: "You responsibly disclose a serious flaw and receive a major bounty.", cashDelta: 28_000, reputationDelta: 4, wellbeingDelta: 1, equityPercentChange: 0),
            IndustryEvent(id: UUID(), title: "Pager Marathon", body: "You survive a brutal on-call week but must skip the next movement turn to recover.", cashDelta: 6_000, reputationDelta: 2, wellbeingDelta: -12, equityPercentChange: 0)
        ]

        let incident = incidents.randomElement()!
        if incident.cashDelta >= 0 {
            players[currentPlayerIndex].cash += incident.cashDelta
        } else {
            chargeCurrentPlayer(amount: -incident.cashDelta, recipientID: nil)
        }
        players[currentPlayerIndex].reputation = max(0, players[currentPlayerIndex].reputation + incident.reputationDelta)
        players[currentPlayerIndex].wellbeing = max(0, min(100, players[currentPlayerIndex].wellbeing + incident.wellbeingDelta))
        applyEquity(percent: incident.equityPercentChange)
        if incident.title == "Pager Marathon" {
            players[currentPlayerIndex].skippedTurns = 1
        }
        currentEvent = incident
    }

    private func applyEquity(percent: Int) {
        let value = players[currentPlayerIndex].equityValue
        players[currentPlayerIndex].equityValue = max(0, value + (value * percent / 100))
    }

    private func finishTurn() {
        evaluateGameOver()
        guard gameOverMessage == nil else { return }
        advanceTurn()
    }

    private func advanceTurn() {
        guard !players.isEmpty else { return }
        var next = currentPlayerIndex
        repeat {
            next = (next + 1) % players.count
            if next == 0 {
                turn += 1
                if turn % 5 == 0 {
                    era = IndustryEra.allCases.randomElement() ?? era
                }
            }
        } while players[next].bankrupt && next != currentPlayerIndex

        currentPlayerIndex = next
        evaluateGameOver()
    }

    private func evaluateGameOver() {
        let active = players.filter { !$0.bankrupt }
        if active.count == 1, players.count > 1, let winner = active.first {
            gameOverMessage = "\(winner.name) controls the software economy with a net worth of ₱\(netWorth(for: winner).formatted())."
            return
        }

        if turn > 40 {
            let ranked = active.sorted { legacyScore(for: $0) > legacyScore(for: $1) }
            if let winner = ranked.first {
                gameOverMessage = "40 rounds are complete. \(winner.name) wins with a Legacy Score of \(legacyScore(for: winner).formatted())."
            }
        }
    }

    private func event(
        title: String,
        body: String,
        cash: Int = 0,
        reputation: Int = 0,
        wellbeing: Int = 0,
        equityPercent: Int = 0
    ) -> IndustryEvent {
        IndustryEvent(
            id: UUID(),
            title: title,
            body: body,
            cashDelta: cash,
            reputationDelta: reputation,
            wellbeingDelta: wellbeing,
            equityPercentChange: equityPercent
        )
    }

    static func demo() -> GameState {
        let tiles: [BoardTile] = [
            .init(id: 0, title: "Sprint Zero", kind: .launch, subtitle: "Collect salary and recurring income when you pass"),
            .init(id: 1, title: "React Studio", kind: .project, subtitle: "Component platform", district: .frontend, purchasePrice: 50_000, baseRevenue: 6_000),
            .init(id: 2, title: "Pull Request", kind: .incident, subtitle: "Review roulette"),
            .init(id: 3, title: "TypeScript Toolkit", kind: .project, subtitle: "Typed web infrastructure", district: .frontend, purchasePrice: 60_000, baseRevenue: 7_000),
            .init(id: 4, title: "Career Review", kind: .career, subtitle: "Negotiate scope and compensation"),
            .init(id: 5, title: "API Forge", kind: .project, subtitle: "Managed backend APIs", district: .backend, purchasePrice: 70_000, baseRevenue: 8_000),
            .init(id: 6, title: "Open Source Commons", kind: .openSource, subtitle: "Reputation compounds publicly"),
            .init(id: 7, title: "QueueWorks", kind: .project, subtitle: "Events and job processing", district: .backend, purchasePrice: 80_000, baseRevenue: 9_000),
            .init(id: 8, title: "Deep Work Lab", kind: .skill, subtitle: "Skill points beat hype"),
            .init(id: 9, title: "SwiftShip", kind: .project, subtitle: "Native iOS delivery stack", district: .mobile, purchasePrice: 90_000, baseRevenue: 10_000),
            .init(id: 10, title: "Store Policy Shock", kind: .incident, subtitle: "A platform rule changes overnight"),
            .init(id: 11, title: "KotlinCraft", kind: .project, subtitle: "Android product engine", district: .mobile, purchasePrice: 100_000, baseRevenue: 11_000),
            .init(id: 12, title: "Market Exchange", kind: .market, subtitle: "Software valuations reprice"),
            .init(id: 13, title: "VectorBase", kind: .project, subtitle: "Search and embeddings", district: .dataAI, purchasePrice: 110_000, baseRevenue: 12_000),
            .init(id: 14, title: "AI Frontier", kind: .aiFrontier, subtitle: "Turn automation into leverage"),
            .init(id: 15, title: "ModelWorks", kind: .project, subtitle: "Inference and model services", district: .dataAI, purchasePrice: 120_000, baseRevenue: 13_000),
            .init(id: 16, title: "Cloud Bill", kind: .tax, subtitle: "Infrastructure always sends an invoice"),
            .init(id: 17, title: "Container Cloud", kind: .project, subtitle: "Managed compute platform", district: .cloud, purchasePrice: 130_000, baseRevenue: 14_000),
            .init(id: 18, title: "Production Outage", kind: .incident, subtitle: "The pager chooses violence"),
            .init(id: 19, title: "Serverless Grid", kind: .project, subtitle: "Elastic application runtime", district: .cloud, purchasePrice: 140_000, baseRevenue: 15_000),
            .init(id: 20, title: "Offline Weekend", kind: .wellbeing, subtitle: "Recover before burnout"),
            .init(id: 21, title: "DevKit Pro", kind: .project, subtitle: "Developer productivity suite", district: .devTools, purchasePrice: 150_000, baseRevenue: 16_000),
            .init(id: 22, title: "Dependency Crisis", kind: .incident, subtitle: "One package breaks everything"),
            .init(id: 23, title: "CI Foundry", kind: .project, subtitle: "Build and release automation", district: .devTools, purchasePrice: 160_000, baseRevenue: 17_000),
            .init(id: 24, title: "Staff Review", kind: .career, subtitle: "Influence without leaving the craft"),
            .init(id: 25, title: "SaaS Launchpad", kind: .project, subtitle: "Recurring revenue machine", district: .creator, purchasePrice: 170_000, baseRevenue: 18_000),
            .init(id: 26, title: "Viral Growth", kind: .incident, subtitle: "Traffic can be a blessing or a bill"),
            .init(id: 27, title: "Subscriptly", kind: .project, subtitle: "Subscription billing platform", district: .creator, purchasePrice: 180_000, baseRevenue: 19_000),
            .init(id: 28, title: "Security Audit", kind: .tax, subtitle: "Compliance becomes real at scale"),
            .init(id: 29, title: "ZeroTrust Labs", kind: .project, subtitle: "Identity and access platform", district: .security, purchasePrice: 190_000, baseRevenue: 20_000),
            .init(id: 30, title: "Bug Bounty", kind: .openSource, subtitle: "Trust is an asset"),
            .init(id: 31, title: "CipherStack", kind: .project, subtitle: "Application security stack", district: .security, purchasePrice: 200_000, baseRevenue: 22_000)
        ]

        let names = ["You", "Mika", "Andre", "Lia"]
        let players = names.map { name in
            Player(
                id: UUID(),
                name: name,
                cash: 220_000,
                salary: 45_000,
                reputation: 5,
                wellbeing: 82,
                skill: 3,
                position: 0,
                recurringIncome: 0,
                equityValue: 35_000,
                propertyValue: 25_000
            )
        }
        return GameState(players: players, board: tiles)
    }
}
