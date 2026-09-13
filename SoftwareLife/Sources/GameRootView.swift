import SwiftUI

struct GameRootView: View {
    @EnvironmentObject private var game: GameState
    @State private var showPortfolio = false
    @State private var showRules = false

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height * 1.12

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.05, blue: 0.07),
                        Color(red: 0.04, green: 0.11, blue: 0.13),
                        Color(red: 0.02, green: 0.06, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if landscape {
                    HStack(spacing: 12) {
                        VStack(spacing: 8) {
                            topBar
                            BoardArena()
                                .environmentObject(game)
                            actionBar
                        }

                        PlayerRail(vertical: true)
                            .environmentObject(game)
                            .frame(width: min(225, proxy.size.width * 0.27))
                    }
                    .padding(10)
                } else {
                    VStack(spacing: 8) {
                        topBar
                        PlayerRail(vertical: false)
                            .environmentObject(game)
                        BoardArena()
                            .environmentObject(game)
                        actionBar
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
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
        .overlay(alignment: .bottom) {
            if let event = game.currentEvent {
                EventToast(event: event) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        game.currentEvent = nil
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 86)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(20)
            }
        }
        .overlay {
            if let message = game.gameOverMessage {
                GameOverOverlay(message: message) {
                    game.restart()
                }
                .zIndex(30)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.9), .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text("CODE CAPITAL")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(1.4)
                Text("Own the software economy")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(game.era.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                Text("ROUND \(game.turn) / 40")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button("Portfolio", systemImage: "briefcase.fill") { showPortfolio = true }
                Button("How to Play", systemImage: "questionmark.circle.fill") { showRules = true }
                Divider()
                Button("Restart Game", systemImage: "arrow.counterclockwise", role: .destructive) {
                    game.restart()
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                showPortfolio = true
            } label: {
                Image(systemName: "briefcase.fill")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)

            Button {
                game.rollAndAdvance()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "dice.fill")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(game.isHumanTurn ? "ROLL & DEPLOY" : "RUN \(game.currentPlayer.name.uppercased())")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                        if game.lastRoll > 0 {
                            Text("Previous roll: \(game.lastRoll)")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .opacity(0.8)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 43)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(playerColor(game.currentPlayerIndex))
            .disabled(game.dealOffer != nil || game.gameOverMessage != nil)

            Button {
                showRules = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct PlayerRail: View {
    @EnvironmentObject private var game: GameState
    let vertical: Bool

    var body: some View {
        Group {
            if vertical {
                VStack(spacing: 8) {
                    ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                        PlayerCard(player: player, index: index, compact: false)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                        PlayerCard(player: player, index: index, compact: true)
                    }
                }
            }
        }
    }
}

private struct PlayerCard: View {
    @EnvironmentObject private var game: GameState
    let player: Player
    let index: Int
    let compact: Bool

    var body: some View {
        let current = index == game.currentPlayerIndex

        VStack(alignment: .leading, spacing: compact ? 2 : 7) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(playerColor(index).gradient)
                    Image(systemName: index == 0 ? "person.fill" : "cpu.fill")
                        .font(.system(size: compact ? 7 : 10, weight: .black))
                        .foregroundStyle(.white)
                }
                .frame(width: compact ? 18 : 28, height: compact ? 18 : 28)

                VStack(alignment: .leading, spacing: 0) {
                    Text(player.name)
                        .font(.system(size: compact ? 9 : 13, weight: .black, design: .rounded))
                        .lineLimit(1)
                    if !compact {
                        Text(current ? "ACTIVE PLAYER" : (player.bankrupt ? "BANKRUPT" : "ENGINEER"))
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundStyle(player.bankrupt ? .red : .secondary)
                    }
                }

                Spacer(minLength: 2)

                if current {
                    Image(systemName: "play.fill")
                        .font(.system(size: compact ? 7 : 9))
                        .foregroundStyle(playerColor(index))
                }
            }

            Text(player.bankrupt ? "OUT" : "₱\(compactMoney(game.netWorth(for: player)))")
                .font(.system(size: compact ? 8 : 16, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(player.bankrupt ? .red : .primary)

            if !compact {
                HStack(spacing: 8) {
                    MiniStat(icon: "banknote.fill", value: compactMoney(player.cash))
                    MiniStat(icon: "shippingbox.fill", value: "\(game.ownedProjects(for: player.id).count)")
                    MiniStat(icon: "terminal.fill", value: "\(player.skill)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 6 : 10)
        .background(
            current ? playerColor(index).opacity(0.16) : Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: compact ? 11 : 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 11 : 15)
                .stroke(current ? playerColor(index).opacity(0.9) : .white.opacity(0.08), lineWidth: current ? 1.5 : 1)
        }
        .shadow(color: current ? playerColor(index).opacity(0.18) : .clear, radius: 10)
    }
}

private struct MiniStat: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct BoardArena: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.black.opacity(0.42))
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.65), radius: 22, y: 14)

                BoardView()
                    .environmentObject(game)
                    .frame(width: side * 0.97, height: side * 0.97)
                    .rotation3DEffect(.degrees(4.5), axis: (x: 1, y: 0, z: 0), perspective: 0.12)

                if game.lastRoll > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            DiceBadge(value: game.lastRoll)
                                .padding(side * 0.055)
                        }
                    }
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct BoardView: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / 9

            ZStack {
                RoundedRectangle(cornerRadius: 21)
                    .fill(Color(red: 0.68, green: 0.82, blue: 0.72))

                RoundedRectangle(cornerRadius: 21)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)

                centerCity(cell: cell)

                ForEach(Array(game.board.enumerated()), id: \.element.id) { index, tile in
                    let grid = boardCoordinate(index)
                    TileView(tile: tile, isCurrent: game.currentPlayer.position == index)
                        .environmentObject(game)
                        .frame(width: cell * 0.98, height: cell * 0.98)
                        .position(
                            x: (CGFloat(grid.col) + 0.5) * cell,
                            y: (CGFloat(grid.row) + 0.5) * cell
                        )
                }

                ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                    if !player.bankrupt {
                        let grid = boardCoordinate(player.position)
                        PawnView(name: player.name, index: index)
                            .frame(width: cell * 0.32, height: cell * 0.32)
                            .position(
                                x: (CGFloat(grid.col) + 0.30 + CGFloat(index % 2) * 0.32) * cell,
                                y: (CGFloat(grid.row) + 0.30 + CGFloat(index / 2) * 0.32) * cell
                            )
                            .animation(.spring(response: 0.42, dampingFraction: 0.76), value: player.position)
                            .zIndex(10)
                    }
                }
            }
        }
    }

    private func centerCity(cell: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.16, blue: 0.18),
                            Color(red: 0.05, green: 0.10, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: cell * 6.55, height: cell * 6.55)

            Path { path in
                path.move(to: CGPoint(x: cell * 0.65, y: cell * 3.25))
                path.addLine(to: CGPoint(x: cell * 5.9, y: cell * 3.25))
                path.move(to: CGPoint(x: cell * 3.28, y: cell * 0.65))
                path.addLine(to: CGPoint(x: cell * 3.28, y: cell * 5.9))
            }
            .stroke(.white.opacity(0.13), style: StrokeStyle(lineWidth: cell * 0.20, dash: [cell * 0.18, cell * 0.16]))
            .frame(width: cell * 6.55, height: cell * 6.55)

            VStack(spacing: cell * 0.20) {
                HStack(spacing: cell * 0.18) {
                    CityBuilding(width: cell * 0.58, height: cell * 1.20, color: .blue)
                    CityBuilding(width: cell * 0.66, height: cell * 1.75, color: .purple)
                    CityBuilding(width: cell * 0.54, height: cell * 0.95, color: .cyan)
                    CityBuilding(width: cell * 0.72, height: cell * 1.52, color: .orange)
                    CityBuilding(width: cell * 0.58, height: cell * 1.08, color: .pink)
                }
                .frame(height: cell * 1.9, alignment: .bottom)

                VStack(spacing: 2) {
                    Text("CODE")
                        .font(.system(size: cell * 0.40, weight: .black, design: .rounded))
                    Text("CAPITAL")
                        .font(.system(size: cell * 0.55, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                    Text("BUILD • OWN • SCALE")
                        .font(.system(size: cell * 0.15, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))
                }

                VStack(spacing: 2) {
                    Text(game.currentTile.title)
                        .font(.system(size: cell * 0.22, weight: .black, design: .rounded))
                        .lineLimit(1)
                    Text(currentTileStatus)
                        .font(.system(size: cell * 0.145, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, cell * 0.42)
                }
            }
        }
        .frame(width: cell * 6.55, height: cell * 6.55)
    }

    private var currentTileStatus: String {
        let tile = game.currentTile
        if tile.isOwnable {
            if let owner = game.ownerName(for: tile.id) {
                return "\(owner) • ₱\(game.revenue(for: tile).formatted()) usage • scale \(game.scaleLevel(for: tile.id))/4"
            }
            return "Available • acquire for ₱\(tile.purchasePrice.formatted())"
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

private struct CityBuilding: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.95), color.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width, height: height)
                .shadow(color: color.opacity(0.30), radius: 7, y: 4)

            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(.white.opacity(0.28))
                        .frame(width: width * 0.45, height: 2)
                }
            }
            .padding(5)
        }
    }
}

private struct TileView: View {
    @EnvironmentObject private var game: GameState
    let tile: BoardTile
    let isCurrent: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 1) {
                Rectangle()
                    .fill(tileColor(tile))
                    .frame(height: 7)

                Image(systemName: icon(for: tile.kind))
                    .font(.system(size: 8.5, weight: .black))
                    .foregroundStyle(tileColor(tile))

                Text(shortTitle)
                    .font(.system(size: 6.6, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.05, green: 0.10, blue: 0.10))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)

                if tile.isOwnable {
                    Text("₱\(compactMoney(tile.purchasePrice))")
                        .font(.system(size: 5.7, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.55))
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.93, green: 0.96, blue: 0.90))
            )

            if let ownerID = game.owners[tile.id],
               let ownerIndex = game.players.firstIndex(where: { $0.id == ownerID }) {
                OwnerFlag(color: playerColor(ownerIndex))
                    .offset(x: 2, y: 1)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isCurrent ? .white : Color.black.opacity(0.18), lineWidth: isCurrent ? 2 : 0.8)
        }
        .scaleEffect(isCurrent ? 1.07 : 1)
        .shadow(color: isCurrent ? tileColor(tile).opacity(0.75) : .black.opacity(0.08), radius: isCurrent ? 7 : 1)
        .zIndex(isCurrent ? 5 : 1)
    }

    private var shortTitle: String {
        let words = tile.title.split(separator: " ")
        if words.count <= 2 { return tile.title }
        return words.prefix(2).joined(separator: " ")
    }
}

private struct OwnerFlag: View {
    let color: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(color)
                .frame(width: 18, height: 7)
            Path { path in
                path.move(to: CGPoint(x: 18, y: 0))
                path.addLine(to: CGPoint(x: 18, y: 14))
                path.addLine(to: CGPoint(x: 10, y: 7))
                path.closeSubpath()
            }
            .fill(color)
            .frame(width: 18, height: 14)
        }
        .frame(width: 18, height: 14)
    }
}

private struct PawnView: View {
    let name: String
    let index: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(playerColor(index).gradient)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.55), radius: 3, y: 2)

            Image(systemName: index == 0 ? "person.fill" : "cpu.fill")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(name)
    }
}

private struct DiceBadge: View {
    let value: Int

    var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .frame(width: 48, height: 48)
                .overlay {
                    Text("\(value)")
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 5)

            Text("ROLL")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

private struct EventToast: View {
    let event: IndustryEvent
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.20))
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.orange)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.bold())
                Text(event.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 4)

            Button("OK", action: dismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
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
            Capsule()
                .fill(.secondary.opacity(0.3))
                .frame(width: 38, height: 4)

            if let tile {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(tileColor(tile).opacity(0.18))
                    Image(systemName: offer.kind == .acquire ? "building.2.crop.circle.fill" : "arrow.up.right.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(tileColor(tile))
                }
                .frame(width: 82, height: 82)

                VStack(spacing: 3) {
                    Text(offer.kind == .acquire ? "Acquire \(tile.title)?" : "Scale \(tile.title)?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(tile.district?.rawValue ?? "Independent Product")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    DealMetric(title: "Cost", value: "₱\(offer.cost.formatted())")
                    DealMetric(title: "Revenue", value: "₱\(offer.projectedRevenue.formatted())")
                    DealMetric(title: "Cash", value: "₱\(game.currentPlayer.cash.formatted())")
                }

                HStack(spacing: 10) {
                    Button("PASS") {
                        game.declineDeal()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button(offer.kind == .acquire ? "ACQUIRE" : "SCALE") {
                        game.acceptDeal()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tileColor(tile))
                    .frame(maxWidth: .infinity)
                    .disabled(game.currentPlayer.cash < offer.cost)
                }
            }
        }
        .padding(20)
    }
}

private struct DealMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PortfolioSheet: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        NavigationStack {
            List {
                Section("Players") {
                    ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                        HStack {
                            Circle()
                                .fill(playerColor(index))
                                .frame(width: 10, height: 10)
                            Text(player.name)
                                .font(.headline)
                            Spacer()
                            Text(player.bankrupt ? "BANKRUPT" : "₱\(game.netWorth(for: player).formatted())")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(player.bankrupt ? .red : .primary)
                        }
                    }
                }

                Section("Your Products") {
                    let products = game.ownedProjects(for: game.players[0].id)
                    if products.isEmpty {
                        Text("No acquisitions yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(products) { tile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(tile.title)
                                        .font(.headline)
                                    Text(tile.district?.rawValue ?? "Product")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("₱\(game.revenue(for: tile).formatted())")
                                        .font(.subheadline.bold())
                                    Text("Scale \(game.scaleLevel(for: tile.id))/4")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("District Control") {
                    ForEach(TechDistrict.allCases) { district in
                        HStack {
                            Text(district.rawValue)
                            Spacer()
                            if game.ownsDistrict(playerID: game.players[0].id, district: district) {
                                Label("CONTROLLED", systemImage: "crown.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.yellow)
                            } else {
                                Text("Incomplete")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Portfolio")
        }
    }
}

private struct RulesSheet: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Objective") {
                    Text("Acquire software products, complete technology districts, scale your strongest products, collect usage revenue from rivals, and finish with the highest legacy score—or be the last engineer solvent.")
                }
                Section("Turn") {
                    Text("Roll and move. Unowned products may be acquired. Landing on a rival product pays usage revenue. Owning every product in a district unlocks scaling up to level 4.")
                }
                Section("Software-Economy Twist") {
                    Text("Salary, skill, reputation, wellbeing, market investments, outages, layoffs, AI shifts, and changing industry eras alter the strategy throughout the match.")
                }
                Section("Reference Philosophy") {
                    Text("The presentation uses the clarity and pacing of premium digital tabletop games while keeping Code Capital's board, economy, names, art, and software-industry systems original.")
                }
            }
            .navigationTitle("How to Play")
        }
    }
}

private struct GameOverOverlay: View {
    let message: String
    let restart: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(.yellow)

                Text("MATCH COMPLETE")
                    .font(.caption.bold())
                    .tracking(2)

                Text(message)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Button("PLAY AGAIN", action: restart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

private func icon(for kind: TileKind) -> String {
    switch kind {
    case .launch: return "paperplane.fill"
    case .project: return "shippingbox.fill"
    case .career: return "laptopcomputer"
    case .incident: return "exclamationmark.triangle.fill"
    case .market: return "chart.line.uptrend.xyaxis"
    case .skill: return "terminal.fill"
    case .wellbeing: return "heart.fill"
    case .openSource: return "network"
    case .aiFrontier: return "brain.head.profile"
    case .tax: return "creditcard.fill"
    }
}

private func tileColor(_ tile: BoardTile) -> Color {
    if let district = tile.district {
        switch district {
        case .frontend: return .brown
        case .backend: return .cyan
        case .mobile: return .pink
        case .dataAI: return .orange
        case .cloud: return .red
        case .devTools: return .yellow
        case .creator: return .green
        case .security: return .blue
        }
    }

    switch tile.kind {
    case .launch: return .green
    case .career: return .indigo
    case .incident: return .orange
    case .market: return .mint
    case .skill: return .purple
    case .wellbeing: return .pink
    case .openSource: return .teal
    case .aiFrontier: return .cyan
    case .tax: return .red
    case .project: return .gray
    }
}

private func playerColor(_ index: Int) -> Color {
    let colors: [Color] = [.cyan, .orange, .pink, .green]
    return colors[index % colors.count]
}

private func compactMoney(_ value: Int) -> String {
    let absValue = abs(value)
    let sign = value < 0 ? "-" : ""

    if absValue >= 1_000_000 {
        let number = Double(absValue) / 1_000_000.0
        return "\(sign)\(number.formatted(.number.precision(.fractionLength(1))))M"
    }
    if absValue >= 1_000 {
        let number = Double(absValue) / 1_000.0
        return "\(sign)\(number.formatted(.number.precision(.fractionLength(0...1))))K"
    }
    return "\(value)"
}
