import SwiftUI
import RealityKit

struct GameRootView: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        ZStack(alignment: .top) {
            Board3DView()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SOFTWARE LIFE")
                            .font(.caption.bold())
                            .tracking(2)
                        Text("Era: \(game.era.rawValue) • Turn \(game.turn)")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    if game.lastRoll > 0 {
                        Label("\(game.lastRoll)", systemImage: "dice.fill")
                            .font(.title3.bold())
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))

                Spacer()

                PlayerHUD(player: game.currentPlayer)

                Button {
                    game.rollAndAdvance()
                } label: {
                    Label("Roll & Live", systemImage: "dice")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .alert(item: $game.currentEvent) { event in
            Alert(
                title: Text(event.title),
                message: Text(event.body),
                dismissButton: .default(Text("Continue"))
            )
        }
    }
}

private struct PlayerHUD: View {
    let player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(player.name)
                    .font(.title3.bold())
                Spacer()
                Text("Legacy \(player.legacyScore.formatted())")
                    .font(.caption.bold())
            }

            HStack(spacing: 18) {
                Stat(label: "Cash", value: "₱\(player.cash.formatted())")
                Stat(label: "Net worth", value: "₱\(player.netWorth.formatted())")
                Stat(label: "Wellbeing", value: "\(player.wellbeing)")
                Stat(label: "Rep", value: "\(player.reputation)")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private struct Stat: View {
        let label: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.bold()).lineLimit(1)
            }
        }
    }
}

private struct Board3DView: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "SoftwareLifeBoard"

            let floor = ModelEntity(
                mesh: .generateBox(size: [9.5, 0.12, 9.5]),
                materials: [SimpleMaterial(color: .darkGray, roughness: 0.9, isMetallic: false)]
            )
            floor.position.y = -0.12
            root.addChild(floor)

            for (index, tile) in game.board.enumerated() {
                let position = tilePosition(index: index, count: game.board.count)
                let block = ModelEntity(
                    mesh: .generateBox(size: [1.6, 0.18, 1.6]),
                    materials: [SimpleMaterial(color: tileColor(tile.kind), roughness: 0.65, isMetallic: false)]
                )
                block.position = position
                block.name = "tile-\(tile.id)"
                root.addChild(block)
            }

            for (index, player) in game.players.enumerated() {
                let pawn = HumanPawn.make(index: index)
                pawn.name = "player-\(player.id.uuidString)"
                let base = tilePosition(index: player.position, count: game.board.count)
                pawn.position = base + SIMD3<Float>(Float(index) * 0.18 - 0.25, 0.20, 0)
                root.addChild(pawn)
            }

            root.orientation = simd_quatf(angle: -.pi / 10, axis: [1, 0, 0])
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "SoftwareLifeBoard" }) else { return }
            for (index, player) in game.players.enumerated() {
                guard let pawn = root.findEntity(named: "player-\(player.id.uuidString)") else { continue }
                let base = tilePosition(index: player.position, count: game.board.count)
                pawn.position = base + SIMD3<Float>(Float(index) * 0.18 - 0.25, 0.20, 0)
            }
        }
    }

    private func tilePosition(index: Int, count: Int) -> SIMD3<Float> {
        let perimeter = max(count, 4)
        let angle = Float(index) / Float(perimeter) * Float.pi * 2
        return SIMD3<Float>(cos(angle) * 3.5, 0, sin(angle) * 3.5)
    }

    private func tileColor(_ kind: TileKind) -> UIColor {
        switch kind {
        case .career: .systemBlue
        case .startup: .systemOrange
        case .market: .systemGreen
        case .property: .systemBrown
        case .skill: .systemIndigo
        case .sideProject: .systemPurple
        case .event: .systemRed
        case .wellbeing: .systemMint
        case .openSource: .systemTeal
        case .aiFrontier: .systemPink
        }
    }
}

private enum HumanPawn {
    static func make(index: Int) -> Entity {
        let root = Entity()
        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple]
        let color = colors[index % colors.count]
        let skin = SimpleMaterial(color: UIColor(red: 0.82, green: 0.64, blue: 0.50, alpha: 1), roughness: 0.8, isMetallic: false)
        let clothing = SimpleMaterial(color: color, roughness: 0.7, isMetallic: false)

        let torso = ModelEntity(mesh: .generateBox(size: [0.24, 0.36, 0.14]), materials: [clothing])
        torso.position.y = 0.28
        root.addChild(torso)

        let head = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [skin])
        head.position.y = 0.57
        root.addChild(head)

        let legLeft = ModelEntity(mesh: .generateBox(size: [0.08, 0.28, 0.09]), materials: [clothing])
        legLeft.position = [-0.07, 0.04, 0]
        root.addChild(legLeft)

        let legRight = ModelEntity(mesh: .generateBox(size: [0.08, 0.28, 0.09]), materials: [clothing])
        legRight.position = [0.07, 0.04, 0]
        root.addChild(legRight)

        return root
    }
}
