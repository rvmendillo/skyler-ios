import SwiftUI

struct WorldView: View {
    @EnvironmentObject var game: GameState
    @State private var player = CGPoint(x: 0.5, y: 0.62)

    private let monsters: [WorldMonster] = [
        WorldMonster(id: UUID(), creature: Creature(species: CreatureSpecies.catalog[0], level: 3), x: 0.20, y: 0.30),
        WorldMonster(id: UUID(), creature: Creature(species: CreatureSpecies.catalog[2], level: 4), x: 0.78, y: 0.28),
        WorldMonster(id: UUID(), creature: Creature(species: CreatureSpecies.catalog[3], level: 5), x: 0.25, y: 0.77),
        WorldMonster(id: UUID(), creature: Creature(species: CreatureSpecies.catalog[4], level: 6), x: 0.82, y: 0.72),
        WorldMonster(id: UUID(), creature: Creature(species: CreatureSpecies.catalog[5], level: 7), x: 0.62, y: 0.46)
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                worldBackground

                building(title: "Guild", icon: "shield.lefthalf.filled", tint: .indigo)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.14)
                building(title: "Rune Shop", icon: "bag.fill", tint: .orange)
                    .position(x: geo.size.width * 0.76, y: geo.size.height * 0.15)

                ForEach(monsters) { monster in
                    Button {
                        game.beginEncounter(monster.creature)
                    } label: {
                        VStack(spacing: 2) {
                            CreatureView(creature: monster.creature, size: 48)
                            Text("Lv.\(monster.creature.level)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: geo.size.width * monster.x, y: geo.size.height * monster.y)
                }

                PlayerAvatar()
                    .position(x: geo.size.width * player.x, y: geo.size.height * player.y)
                    .animation(.snappy(duration: 0.15), value: player)

                VStack {
                    HUD()
                    Spacer()
                    HStack(alignment: .bottom) {
                        joystick
                        Spacer()
                        actionButtons
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 84)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $game.encounter) { _ in
            BattleView()
                .environmentObject(game)
                .interactiveDismissDisabled()
        }
    }

    private var worldBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.11, green: 0.28, blue: 0.18), Color(red: 0.17, green: 0.38, blue: 0.22)], startPoint: .top, endPoint: .bottom)
            ForEach(0..<16, id: \.self) { i in
                Circle()
                    .fill(.green.opacity(0.20))
                    .frame(width: CGFloat(34 + (i % 4) * 8))
                    .offset(x: CGFloat((i * 83) % 340) - 170, y: CGFloat((i * 137) % 760) - 380)
            }
            RoundedRectangle(cornerRadius: 50)
                .fill(Color(red: 0.56, green: 0.48, blue: 0.32).opacity(0.55))
                .frame(width: 95, height: 860)
                .rotationEffect(.degrees(7))
        }
    }

    private func building(title: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(tint.gradient).frame(width: 104, height: 74)
                Image(systemName: icon).font(.title).foregroundStyle(.white)
            }
            Text(title).font(.caption.bold()).foregroundStyle(.white)
        }
    }

    private var joystick: some View {
        ZStack {
            Circle().fill(.black.opacity(0.35)).frame(width: 116, height: 116)
            VStack(spacing: 5) {
                Button { move(dx: 0, dy: -0.06) } label: { Image(systemName: "chevron.up") }
                HStack(spacing: 28) {
                    Button { move(dx: -0.06, dy: 0) } label: { Image(systemName: "chevron.left") }
                    Button { move(dx: 0.06, dy: 0) } label: { Image(systemName: "chevron.right") }
                }
                Button { move(dx: 0, dy: 0.06) } label: { Image(systemName: "chevron.down") }
            }
            .font(.title2.bold()).foregroundStyle(.white)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button { game.screen = .collection } label: {
                Image(systemName: "pawprint.fill").frame(width: 54, height: 54).background(.indigo.gradient, in: Circle())
            }
            Button { game.screen = .quests } label: {
                Image(systemName: "scroll.fill").frame(width: 54, height: 54).background(.orange.gradient, in: Circle())
            }
        }
        .font(.title3.bold()).foregroundStyle(.white)
    }

    private func move(dx: Double, dy: Double) {
        player.x = min(0.92, max(0.08, player.x + dx))
        player.y = min(0.88, max(0.18, player.y + dy))
        if let near = monsters.first(where: { hypot(player.x - $0.x, player.y - $0.y) < 0.10 }), Int.random(in: 0...2) == 0 {
            game.beginEncounter(near.creature)
        }
    }
}

struct PlayerAvatar: View {
    var body: some View {
        VStack(spacing: -3) {
            ZStack {
                Circle().fill(.pink.opacity(0.9)).frame(width: 34, height: 34)
                Image(systemName: "person.fill").foregroundStyle(.white)
            }
            Capsule().fill(.blue.gradient).frame(width: 36, height: 28)
        }
        .shadow(radius: 5)
    }
}

struct HUD: View {
    @EnvironmentObject var game: GameState
    var body: some View {
        HStack(spacing: 10) {
            CreatureView(creature: game.activeCreature, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Tamer Lv.\(game.playerLevel)").bold(); Spacer(); Label("\(game.coins)", systemImage: "circle.hexagongrid.fill") }
                ProgressView(value: Double(game.playerHP), total: 100).tint(.green)
                Text("HP \(game.playerHP)/100 • EXP \(game.exp)/\(game.playerLevel * 100)").font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.top, 52).padding(.horizontal, 12)
    }
}
