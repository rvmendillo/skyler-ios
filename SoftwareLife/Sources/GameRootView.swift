import SwiftUI
import Foundation

struct GameRootView: View {
    @EnvironmentObject private var game: GameState
    @State private var showPortfolio = false
    @State private var showRules = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.055, blue: 0.075), Color(red: 0.055, green: 0.12, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                playerStrip
                BoardView()
                    .environmentObject(game)
                    .aspectRatio(1, contentMode: .fit)
                playerHUD
                controls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .preferredColorScheme(.dark)
        .alert(item: $game.currentEvent) { event in
            Alert(
                title: Text(event.title),
                message: Text(event.body),
                dismissButton: .default(Text("Continue"))
            )
        }
        .sheet(item: $game.dealOffer) { offer in
            DealSheet(offer: offer)
                .environmentObject(game)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPortfolio) {
            PortfolioSheet()
                .environmentObject(game)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showRules) {
            RulesSheet()
                .presentationDetents([.medium, .large])
        }
        .overlay {
            if let message = game.gameOverMessage {
                GameOverOverlay(message: message) {
                    game.restart()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("CODE CAPITAL")
                    .font(.caption.bold())
                    .tracking(2)
                Text("Software economy board game")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(game.era.rawValue)
                    .font(.caption.bold())
                Text("Round \(game.turn) / 40")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("Portfolio", systemImage: "briefcase") { showPortfolio = true }
                Button("How to Play", systemImage: "questionmark.circle") { showRules = true }
                Divider()
                Button("Restart Game", systemImage: "arrow.counterclockwise", role: .destructive) { game.restart() }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var playerStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(playerColor(index))
                            .frame(width: 6, height: 6)
                        Text(player.name)
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                    }
                    Text(player.bankrupt ? "OUT" : "₱\(compact(game.netWorth(for: player)))")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(player.bankrupt ? .red : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    index == game.currentPlayerIndex ? playerColor(index).opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(index == game.currentPlayerIndex ? playerColor(index) : .white.opacity(0.07), lineWidth: 1)
                }
            }
        }
    }

    private var playerHUD: some View {
        let player = game.currentPlayer
        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.name == "You" ? "YOUR TURN" : "RIVAL TURN")
                        .font(.caption2.bold())
                        .foregroundStyle(playerColor(game.currentPlayerIndex))
                    Text(player.name)
                        .font(.headline.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Net worth")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("₱\(game.netWorth(for: player).formatted())")
                        .font(.subheadline.bold().monospacedDigit())
                }
            }

            HStack(spacing: 6) {
                Metric(label: "Cash", value: "₱\(compact(player.cash))", icon: "banknote")
                Metric(label: "Salary", value: "₱\(compact(player.salary))", icon: "laptopcomputer")
                Metric(label: "Projects", value: "\(game.ownedProjects(for: player.id).count)", icon: "shippingbox")
                Metric(label: "Skill", value: "\(player.skill)", icon: "terminal")
                Metric(label: "Rep", value: "\(player.reputation)", icon: "star")
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                showPortfolio = true
            } label: {
                Image(systemName: "briefcase.fill")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)

            Button {
                game.rollAndAdvance()
            } label: {
                Label(game.isHumanTurn ? "Roll & Move" : "Run \(game.currentPlayer.name)", systemImage: "dice.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(playerColor(game.currentPlayerIndex))
            .disabled(game.dealOffer != nil || game.gameOverMessage != nil)
        }
    }
}

private struct BoardView: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / 9

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.075, green: 0.16, blue: 0.16))
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 10)

                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.15), lineWidth: 2)
                    .padding(2)

                centerPanel(cell: cell)

                ForEach(Array(game.board.enumerated()), id: \.element.id) { index, tile in
                    let grid = boardCoordinate(index)
                    TileView(tile: tile, isCurrent: game.currentPlayer.position == index)
                        .environmentObject(game)
                        .frame(width: cell * 0.94, height: cell * 0.94)
                        .position(x: (CGFloat(grid.col) + 0.5) * cell, y: (CGFloat(grid.row) + 0.5) * cell)
                }

                ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                    if !player.bankrupt {
                        let grid = boardCoordinate(player.position)
                        PawnView(name: player.name, index: index)
                            .frame(width: cell * 0.34, height: cell * 0.34)
                            .position(
                                x: (CGFloat(grid.col) + 0.34 + CGFloat(index % 2) * 0.30) * cell,
                                y: (CGFloat(grid.row) + 0.35 + CGFloat(index / 2) * 0.30) * cell
                            )
                            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: player.position)
                    }
                }
            }
            .frame(width: side, height: side)
            .rotation3DEffect(.degrees(3.5), axis: (x: 1, y: 0, z: 0), perspective: 0.15)
        }
    }

    @ViewBuilder
    private func centerPanel(cell: CGFloat) -> some View {
        VStack(spacing: 5) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: cell * 0.55, weight: .black))
                .foregroundStyle(.cyan)
            Text("CODE CAPITAL")
                .font(.system(size: cell * 0.34, weight: .black, design: .rounded))
                .tracking(1.2)
            Text("BUILD • OWN • SCALE")
                .font(.system(size: cell * 0.18, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: cell * 0.16) {
                skylineBlock(height: cell * 0.55, color: .blue)
                skylineBlock(height: cell * 0.90, color: .purple)
                skylineBlock(height: cell * 0.68, color: .teal)
                skylineBlock(height: cell * 1.10, color: .orange)
                skylineBlock(height: cell * 0.76, color: .pink)
            }
            .frame(height: cell * 1.2, alignment: .bottom)
            Text(game.currentTile.title)
                .font(.system(size: cell * 0.23, weight: .bold))
                .lineLimit(1)
            Text(currentTileStatus)
                .font(.system(size: cell * 0.16, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, cell * 0.45)
        }
        .frame(width: cell * 6.5, height: cell * 6.5)
        .background(
            RadialGradient(colors: [.white.opacity(0.08), .clear], center: .center, startRadius: 0, endRadius: cell * 3.5)
        )
    }

    private func skylineBlock(height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.gradient)
            .frame(width: 16, height: height)
            .shadow(color: color.opacity(0.35), radius: 5)
    }

    private var currentTileStatus: String {
        let tile = game.currentTile
        if tile.isOwnable {
            if let owner = game.ownerName(for: tile.id) {
                return "\(owner) • ₱\(game.revenue(for: tile).formatted()) usage revenue • scale \(game.scaleLevel(for: tile.id))/4"
            }
            return "Unowned • ₱\(tile.purchasePrice.formatted()) to acquire"
        }
        return tile.subtitle
    }

    private func boardCoordinate(_ index: Int) -> (row: Int, col: Int) {
        switch index {
        case 0...8:
            return (8, index)
        case 9...16:
            return (16 - index, 8)
        case 17...24:
            return (0, 24 - index)
        default:
            return (index - 24, 0)
        }
    }
}

private struct TileView: View {
    @EnvironmentObject private var game: GameState
    let tile: BoardTile
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tileColor(tile))
                .frame(height: 5)

            Image(systemName: icon(for: tile.kind))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tileColor(tile))

            Text(shortTitle)
                .font(.system(size: 6.8, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.55)

            if tile.isOwnable {
                Text("₱\(compact(tile.purchasePrice))")
                    .font(.system(size: 5.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let ownerID = game.owners[tile.id],
               let ownerIndex = game.players.firstIndex(where: { $0.id == ownerID }) {
                Capsule()
                    .fill(playerColor(ownerIndex))
                    .frame(width: 16, height: 3)
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.42))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isCurrent ? .white : .white.opacity(0.08), lineWidth: isCurrent ? 1.5 : 0.7)
        }
        .scaleEffect(isCurrent ? 1.06 : 1)
        .shadow(color: isCurrent ? tileColor(tile).opacity(0.55) : .clear, radius: 6)
        .zIndex(isCurrent ? 3 : 1)
    }

    private var shortTitle: String {
        let words = tile.title.split(separator: " ")
        if words.count <= 2 { return tile.title }
        return words.prefix(2).joined(separator: " ")
    }
}

private struct PawnView: View {
    let name: String
    let index: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(playerColor(index).gradient)
                .shadow(color: .black.opacity(0.55), radius: 2, y: 2)
            Image(systemName: index == 0 ? "person.fill" : "cpu.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(name)
    }
}

private struct Metric: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.bold().monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 7.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DealSheet: View {
    @EnvironmentObject private var game: GameState
    let offer: DealOffer

    private var tile: BoardTile? {
        game.board.first(where: { $0.id == offer.tileID })
    }

    var body: some View {
        VStack(spacing: 16) {
            if let tile {
                Image(systemName: offer.kind == .acquire ? "shippingbox.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(tileColor(tile))

                VStack(spacing: 4) {
                    Text(offer.kind == .acquire ? "Acquire \(tile.title)?" : "Scale \(tile.title)?")
                        .font(.title2.bold())
                    Text(tile.district?.rawValue ?? "Independent Product")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    DealMetric(title: "Cost", value: "₱\(offer.cost.formatted())")
                    DealMetric(title: "Revenue", value: "₱\(offer.projectedRevenue.formatted())")
                    DealMetric(title: "Cash after", value: "₱\(max(0, game.currentPlayer.cash - offer.cost).formatted())")
                }

                Text(offer.kind == .acquire
                     ? "Own both products in the same district to double district revenue and unlock product scaling."
                     : "Scaling increases usage revenue. Level 4 is the unicorn tier.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button("Pass") { game.declineDeal() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button(offer.kind == .acquire ? "Acquire" : "Scale") { game.acceptDeal() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(game.currentPlayer.cash < offer.cost)
                }
            }
        }
        .padding(24)
    }
}

private struct DealMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold().monospacedDigit()).minimumScaleFactor(0.65).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct PortfolioSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                    Section {
                        let projects = game.ownedProjects(for: player.id)
                        if projects.isEmpty {
                            Text(player.bankrupt ? "Bankrupt" : "No products yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(projects) { tile in
                                HStack {
                                    Circle().fill(playerColor(index)).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tile.title).font(.subheadline.bold())
                                        Text("\(tile.district?.rawValue ?? "Independent") • scale \(game.scaleLevel(for: tile.id))/4")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("₱\(game.revenue(for: tile).formatted())")
                                        .font(.caption.bold().monospacedDigit())
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(player.name)
                            Spacer()
                            Text("₱\(game.netWorth(for: player).formatted())")
                        }
                    }
                }
            }
            .navigationTitle("Product Portfolios")
        }
    }
}

private struct RulesSheet: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Rule(title: "1. Move through the software economy", text: "Roll a die and travel around 32 software-industry spaces. Passing Sprint Zero pays your salary plus recurring income.")
                    Rule(title: "2. Acquire products", text: "Unowned product spaces can be acquired. Rivals landing on them pay usage and licensing revenue to the owner.")
                    Rule(title: "3. Complete a tech district", text: "Own both products in a district to create a stack monopoly. District revenue doubles and scaling becomes available.")
                    Rule(title: "4. Scale to unicorn tier", text: "Each product has four scale levels. Higher levels dramatically increase landing revenue but consume cash.")
                    Rule(title: "5. Survive engineering reality", text: "Outages, layoffs, CVEs, framework migrations, market repricing, cloud bills, burnout, and AI shifts reshape the game.")
                    Rule(title: "6. Win", text: "Bankrupt the other engineers, or lead the Legacy Score after 40 rounds. Legacy rewards net worth, skill, reputation, wellbeing, and recurring income.")
                }
                .padding()
            }
            .navigationTitle("How to Play")
        }
    }

    private struct Rule: View {
        let title: String
        let text: String

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct GameOverOverlay: View {
    let message: String
    let restart: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.76).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                Text("Game Complete")
                    .font(.largeTitle.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("New Game", action: restart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(26)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(24)
        }
    }
}

private func playerColor(_ index: Int) -> Color {
    switch index % 4 {
    case 0: return .cyan
    case 1: return .orange
    case 2: return .purple
    default: return .green
    }
}

private func tileColor(_ tile: BoardTile) -> Color {
    if let district = tile.district {
        switch district {
        case .frontend: return .blue
        case .backend: return .teal
        case .mobile: return .indigo
        case .dataAI: return .purple
        case .cloud: return .cyan
        case .devTools: return .orange
        case .creator: return .pink
        case .security: return .red
        }
    }

    switch tile.kind {
    case .launch: return .green
    case .project: return .blue
    case .career: return .mint
    case .incident: return .red
    case .market: return .yellow
    case .skill: return .indigo
    case .wellbeing: return .green
    case .openSource: return .gray
    case .aiFrontier: return .purple
    case .tax: return .orange
    }
}

private func icon(for kind: TileKind) -> String {
    switch kind {
    case .launch: return "flag.checkered"
    case .project: return "shippingbox.fill"
    case .career: return "person.crop.rectangle.stack"
    case .incident: return "exclamationmark.triangle.fill"
    case .market: return "chart.line.uptrend.xyaxis"
    case .skill: return "terminal.fill"
    case .wellbeing: return "leaf.fill"
    case .openSource: return "chevron.left.forwardslash.chevron.right"
    case .aiFrontier: return "sparkles"
    case .tax: return "creditcard.fill"
    }
}

private func compact(_ value: Int) -> String {
    if abs(value) >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if abs(value) >= 1_000 { return String(format: "%.0fK", Double(value) / 1_000) }
    return "\(value)"
}
