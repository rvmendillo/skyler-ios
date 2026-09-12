import SwiftUI
import RealityKit

struct GameRootView: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        ZStack(alignment: .top) {
            Board3DView()
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.34), .clear, Color.black.opacity(0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SOFTWARE LIFE")
                            .font(.caption.bold())
                            .tracking(2)
                        Text("\(game.era.rawValue)  •  Turn \(game.turn)")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(game.board[game.currentPlayer.position].title)
                            .font(.caption.bold())
                        if game.lastRoll > 0 {
                            Label("Last roll \(game.lastRoll)", systemImage: "dice.fill")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(.ultraThinMaterial.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))

                Spacer()

                PlayerHUD(player: game.currentPlayer)

                Button {
                    game.rollAndAdvance()
                } label: {
                    Label("Roll & Move", systemImage: "dice")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(player.name)
                    .font(.headline.bold())
                Spacer()
                Text("Legacy \(player.legacyScore.formatted())")
                    .font(.caption.bold())
            }

            HStack(spacing: 14) {
                Stat(label: "Cash", value: "₱\(player.cash.formatted())")
                Stat(label: "Worth", value: "₱\(player.netWorth.formatted())")
                Stat(label: "Health", value: "\(player.wellbeing)")
                Stat(label: "Skill", value: "\(player.skill)")
                Stat(label: "Rep", value: "\(player.reputation)")
            }
        }
        .padding(14)
        .background(.regularMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 20))
    }

    private struct Stat: View {
        let label: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

            addTabletop(to: root)
            addTrack(to: root)
            addScenery(to: root)
            addMarketDial(to: root)
            addStartAndFinish(to: root)

            for (index, tile) in game.board.enumerated() {
                let position = BoardGeometry.position(for: index)
                let tileEntity = makeTile(tile: tile, index: index)
                tileEntity.position = position + SIMD3<Float>(0, 0.13, 0)
                root.addChild(tileEntity)
            }

            for (index, player) in game.players.enumerated() {
                let pawn = HumanPawn.make(index: index)
                pawn.name = "player-\(player.id.uuidString)"
                let base = BoardGeometry.position(for: player.position)
                pawn.position = base + pawnOffset(index: index)
                root.addChild(pawn)
            }

            // A tilted tabletop perspective keeps the whole journey visible on iPhone.
            root.orientation = simd_quatf(angle: -.pi / 9, axis: [1, 0, 0])
            root.scale = SIMD3<Float>(repeating: 0.94)
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "SoftwareLifeBoard" }) else { return }

            for (index, player) in game.players.enumerated() {
                guard let pawn = root.findEntity(named: "player-\(player.id.uuidString)") else { continue }
                let target = BoardGeometry.position(for: player.position) + pawnOffset(index: index)
                var transform = pawn.transform
                transform.translation = target
                pawn.move(to: transform, relativeTo: root, duration: 0.55, timingFunction: .easeInOut)
            }
        }
    }

    private func addTabletop(to root: Entity) {
        let boardBase = ModelEntity(
            mesh: .generateBox(size: [8.9, 0.16, 8.9]),
            materials: [SimpleMaterial(color: UIColor(red: 0.16, green: 0.34, blue: 0.22, alpha: 1), roughness: 0.95, isMetallic: false)]
        )
        boardBase.position.y = -0.14
        root.addChild(boardBase)

        let innerBoard = ModelEntity(
            mesh: .generateBox(size: [8.55, 0.05, 8.55]),
            materials: [SimpleMaterial(color: UIColor(red: 0.36, green: 0.57, blue: 0.34, alpha: 1), roughness: 0.9, isMetallic: false)]
        )
        innerBoard.position.y = -0.03
        root.addChild(innerBoard)

        // Raised frame gives it the silhouette of a physical board game.
        let frameMaterial = SimpleMaterial(color: UIColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1), roughness: 0.75, isMetallic: false)
        let top = ModelEntity(mesh: .generateBox(size: [9.15, 0.24, 0.18]), materials: [frameMaterial])
        top.position = [0, -0.02, -4.52]
        root.addChild(top)
        let bottom = ModelEntity(mesh: .generateBox(size: [9.15, 0.24, 0.18]), materials: [frameMaterial])
        bottom.position = [0, -0.02, 4.52]
        root.addChild(bottom)
        let left = ModelEntity(mesh: .generateBox(size: [0.18, 0.24, 9.15]), materials: [frameMaterial])
        left.position = [-4.52, -0.02, 0]
        root.addChild(left)
        let right = ModelEntity(mesh: .generateBox(size: [0.18, 0.24, 9.15]), materials: [frameMaterial])
        right.position = [4.52, -0.02, 0]
        root.addChild(right)
    }

    private func addTrack(to root: Entity) {
        let roadMaterial = SimpleMaterial(color: UIColor(white: 0.91, alpha: 1), roughness: 0.9, isMetallic: false)
        guard game.board.count > 1 else { return }

        for index in 0..<(game.board.count - 1) {
            let a = BoardGeometry.position(for: index)
            let b = BoardGeometry.position(for: index + 1)
            let dx = b.x - a.x
            let dz = b.z - a.z
            let length = sqrt(dx * dx + dz * dz)
            let connector = ModelEntity(mesh: .generateBox(size: [length, 0.05, 0.40]), materials: [roadMaterial])
            connector.position = [(a.x + b.x) / 2, 0.035, (a.z + b.z) / 2]
            connector.orientation = simd_quatf(angle: -atan2(dz, dx), axis: [0, 1, 0])
            root.addChild(connector)
        }
    }

    private func makeTile(tile: BoardTile, index: Int) -> Entity {
        let root = Entity()
        root.name = "tile-\(tile.id)"

        let block = ModelEntity(
            mesh: .generateBox(size: [1.03, 0.18, 0.74]),
            materials: [SimpleMaterial(color: tileColor(tile.kind), roughness: 0.55, isMetallic: false)]
        )
        root.addChild(block)

        let inset = ModelEntity(
            mesh: .generateBox(size: [0.82, 0.025, 0.53]),
            materials: [SimpleMaterial(color: UIColor.white.withAlphaComponent(0.22), roughness: 0.7, isMetallic: false)]
        )
        inset.position.y = 0.105
        root.addChild(inset)

        let marker: ModelEntity
        switch tile.kind {
        case .career, .property, .sideProject:
            marker = ModelEntity(mesh: .generateBox(size: [0.16, 0.13, 0.16]), materials: [SimpleMaterial(color: .white, roughness: 0.6, isMetallic: false)])
        case .startup, .market, .event:
            marker = ModelEntity(mesh: .generateSphere(radius: 0.09), materials: [SimpleMaterial(color: .white, roughness: 0.5, isMetallic: false)])
        case .skill, .openSource, .aiFrontier, .wellbeing:
            marker = ModelEntity(mesh: .generateBox(size: [0.11, 0.17, 0.11]), materials: [SimpleMaterial(color: .white, roughness: 0.55, isMetallic: false)])
        }
        marker.position = [0, 0.20, 0]
        root.addChild(marker)

        if index == 0 || index == game.board.count - 1 {
            let beacon = ModelEntity(mesh: .generateSphere(radius: 0.10), materials: [SimpleMaterial(color: .white, roughness: 0.3, isMetallic: true)])
            beacon.position = [0, 0.38, 0]
            root.addChild(beacon)
        }

        return root
    }

    private func addScenery(to root: Entity) {
        addBuilding(to: root, position: [-3.82, 0, 2.35], height: 0.70, color: .systemIndigo)
        addBuilding(to: root, position: [3.78, 0, 2.45], height: 1.05, color: .systemBlue)
        addBuilding(to: root, position: [3.82, 0, -2.35], height: 0.82, color: .systemOrange)
        addBuilding(to: root, position: [-3.80, 0, -2.30], height: 0.92, color: .systemPurple)
        addBuilding(to: root, position: [2.55, 0, 0.80], height: 0.65, color: .systemTeal)
        addBuilding(to: root, position: [-2.55, 0, -0.80], height: 0.72, color: .systemPink)

        addTree(to: root, position: [-3.75, 0, 0.78])
        addTree(to: root, position: [-3.35, 0, 0.72])
        addTree(to: root, position: [3.70, 0, -0.78])
        addTree(to: root, position: [3.30, 0, -0.72])
        addTree(to: root, position: [1.80, 0, 0.78])
        addTree(to: root, position: [-1.80, 0, -0.78])
    }

    private func addBuilding(to root: Entity, position: SIMD3<Float>, height: Float, color: UIColor) {
        let building = Entity()
        let body = ModelEntity(
            mesh: .generateBox(size: [0.46, height, 0.46]),
            materials: [SimpleMaterial(color: color, roughness: 0.55, isMetallic: false)]
        )
        body.position.y = height / 2
        building.addChild(body)

        let roof = ModelEntity(
            mesh: .generateBox(size: [0.54, 0.07, 0.54]),
            materials: [SimpleMaterial(color: UIColor.white.withAlphaComponent(0.85), roughness: 0.5, isMetallic: false)]
        )
        roof.position.y = height + 0.035
        building.addChild(roof)

        building.position = position
        root.addChild(building)
    }

    private func addTree(to root: Entity, position: SIMD3<Float>) {
        let tree = Entity()
        let trunk = ModelEntity(
            mesh: .generateBox(size: [0.09, 0.28, 0.09]),
            materials: [SimpleMaterial(color: .brown, roughness: 0.95, isMetallic: false)]
        )
        trunk.position.y = 0.14
        tree.addChild(trunk)

        let crown = ModelEntity(
            mesh: .generateSphere(radius: 0.18),
            materials: [SimpleMaterial(color: UIColor(red: 0.12, green: 0.48, blue: 0.20, alpha: 1), roughness: 0.9, isMetallic: false)]
        )
        crown.position.y = 0.39
        tree.addChild(crown)
        tree.position = position
        root.addChild(tree)
    }

    private func addMarketDial(to root: Entity) {
        let dialRoot = Entity()
        dialRoot.position = [0, 0, 0.80]

        let base = ModelEntity(
            mesh: .generateCylinder(height: 0.10, radius: 0.48),
            materials: [SimpleMaterial(color: UIColor(red: 0.15, green: 0.18, blue: 0.24, alpha: 1), roughness: 0.55, isMetallic: true)]
        )
        base.position.y = 0.06
        dialRoot.addChild(base)

        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple, .systemRed, .systemTeal, .systemPink, .systemYellow]
        for i in 0..<8 {
            let angle = Float(i) / 8 * Float.pi * 2
            let peg = ModelEntity(
                mesh: .generateSphere(radius: 0.07),
                materials: [SimpleMaterial(color: colors[i], roughness: 0.45, isMetallic: false)]
            )
            peg.position = [cos(angle) * 0.34, 0.15, sin(angle) * 0.34]
            dialRoot.addChild(peg)
        }

        let pointer = ModelEntity(
            mesh: .generateBox(size: [0.38, 0.045, 0.06]),
            materials: [SimpleMaterial(color: .white, roughness: 0.3, isMetallic: true)]
        )
        pointer.position = [0.15, 0.18, 0]
        pointer.orientation = simd_quatf(angle: .pi / 5, axis: [0, 1, 0])
        dialRoot.addChild(pointer)
        root.addChild(dialRoot)
    }

    private func addStartAndFinish(to root: Entity) {
        addGate(to: root, at: BoardGeometry.position(for: 0), color: .systemGreen)
        addGate(to: root, at: BoardGeometry.position(for: game.board.count - 1), color: .systemYellow)
    }

    private func addGate(to root: Entity, at position: SIMD3<Float>, color: UIColor) {
        let gate = Entity()
        let material = SimpleMaterial(color: color, roughness: 0.55, isMetallic: false)
        let left = ModelEntity(mesh: .generateBox(size: [0.08, 0.60, 0.08]), materials: [material])
        left.position = [-0.46, 0.30, 0]
        gate.addChild(left)
        let right = ModelEntity(mesh: .generateBox(size: [0.08, 0.60, 0.08]), materials: [material])
        right.position = [0.46, 0.30, 0]
        gate.addChild(right)
        let bar = ModelEntity(mesh: .generateBox(size: [1.00, 0.09, 0.09]), materials: [material])
        bar.position = [0, 0.59, 0]
        gate.addChild(bar)
        gate.position = position
        root.addChild(gate)
    }

    private func pawnOffset(index: Int) -> SIMD3<Float> {
        let offsets: [SIMD3<Float>] = [
            [-0.25, 0.35, -0.13],
            [0.25, 0.35, -0.13],
            [-0.25, 0.35, 0.14],
            [0.25, 0.35, 0.14]
        ]
        return offsets[index % offsets.count]
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

private enum BoardGeometry {
    static let positions: [SIMD3<Float>] = {
        let xs: [Float] = [-3.25, -1.95, -0.65, 0.65, 1.95, 3.25]
        let zs: [Float] = [3.20, 1.60, 0.00, -1.60, -3.20]
        var result: [SIMD3<Float>] = []

        for (row, z) in zs.enumerated() {
            let rowXs = row.isMultiple(of: 2) ? xs : Array(xs.reversed())
            for x in rowXs {
                result.append([x, 0, z])
            }
        }
        return result
    }()

    static func position(for index: Int) -> SIMD3<Float> {
        positions[index % positions.count]
    }
}

private enum HumanPawn {
    static func make(index: Int) -> Entity {
        let root = Entity()
        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple]
        let color = colors[index % colors.count]
        let skin = SimpleMaterial(color: UIColor(red: 0.82, green: 0.64, blue: 0.50, alpha: 1), roughness: 0.8, isMetallic: false)
        let clothing = SimpleMaterial(color: color, roughness: 0.7, isMetallic: false)
        let dark = SimpleMaterial(color: UIColor(white: 0.12, alpha: 1), roughness: 0.85, isMetallic: false)

        let torso = ModelEntity(mesh: .generateBox(size: [0.22, 0.32, 0.14]), materials: [clothing])
        torso.position.y = 0.31
        root.addChild(torso)

        let head = ModelEntity(mesh: .generateSphere(radius: 0.11), materials: [skin])
        head.position.y = 0.56
        root.addChild(head)

        let hair = ModelEntity(mesh: .generateSphere(radius: 0.115), materials: [dark])
        hair.scale = [1, 0.42, 1]
        hair.position.y = 0.615
        root.addChild(hair)

        let legLeft = ModelEntity(mesh: .generateBox(size: [0.075, 0.25, 0.085]), materials: [clothing])
        legLeft.position = [-0.06, 0.08, 0]
        root.addChild(legLeft)

        let legRight = ModelEntity(mesh: .generateBox(size: [0.075, 0.25, 0.085]), materials: [clothing])
        legRight.position = [0.06, 0.08, 0]
        root.addChild(legRight)

        let armLeft = ModelEntity(mesh: .generateBox(size: [0.055, 0.25, 0.065]), materials: [skin])
        armLeft.position = [-0.15, 0.31, 0]
        armLeft.orientation = simd_quatf(angle: 0.13, axis: [0, 0, 1])
        root.addChild(armLeft)

        let armRight = ModelEntity(mesh: .generateBox(size: [0.055, 0.25, 0.065]), materials: [skin])
        armRight.position = [0.15, 0.31, 0]
        armRight.orientation = simd_quatf(angle: -0.13, axis: [0, 0, 1])
        root.addChild(armRight)

        return root
    }
}
