import SwiftUI
import RealityKit
import UIKit

struct GameRoot3DView: View {
    @EnvironmentObject private var game: GameState
    @State private var yaw: Float = -0.08
    @State private var tilt: Float = -0.52
    @State private var showPortfolio = false
    @State private var showRules = false

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height * 1.12

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.015, green: 0.025, blue: 0.035),
                        Color(red: 0.025, green: 0.075, blue: 0.085),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                CodeCapitalTabletop3D(yaw: yaw, tilt: tilt)
                    .environmentObject(game)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                yaw = max(-0.55, min(0.55, -0.08 + Float(value.translation.width / 520)))
                                tilt = max(-0.82, min(-0.22, -0.52 + Float(value.translation.height / 700)))
                            }
                    )

                LinearGradient(
                    colors: [Color.black.opacity(0.58), .clear, Color.black.opacity(0.48)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 10) {
                    topBar
                    playerRail(vertical: landscape)
                    Spacer(minLength: 0)
                    bottomDock
                }
                .padding(.horizontal, landscape ? 16 : 10)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .overlay(alignment: .center) {
                if let offer = game.dealOffer {
                    CC3DDealCard(offer: offer)
                        .environmentObject(game)
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                        .zIndex(30)
                }
            }
            .overlay(alignment: .bottom) {
                if let event = game.currentEvent, game.dealOffer == nil {
                    CC3DEventCard(event: event) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            game.currentEvent = nil
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 88)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(25)
                }
            }
            .overlay {
                if let message = game.gameOverMessage {
                    CC3DGameOver(message: message) { game.restart() }
                        .zIndex(40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPortfolio) {
            CC3DPortfolioView()
                .environmentObject(game)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showRules) {
            CC3DRulesView()
                .presentationDetents([.medium, .large])
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.headline.black())
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text("CODE CAPITAL")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(1.3)
                Text("3D SOFTWARE EMPIRE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.cyan.opacity(0.85))
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(game.era.rawValue.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                Text("ROUND \(game.turn) / 40")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button("Portfolio", systemImage: "briefcase.fill") { showPortfolio = true }
                Button("How to Play", systemImage: "questionmark.circle.fill") { showRules = true }
                Button("Reset Camera", systemImage: "view.3d") {
                    withAnimation(.spring) {
                        yaw = -0.08
                        tilt = -0.52
                    }
                }
                Divider()
                Button("Restart", systemImage: "arrow.counterclockwise", role: .destructive) { game.restart() }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.10), lineWidth: 1) }
    }

    @ViewBuilder
    private func playerRail(vertical: Bool) -> some View {
        if vertical {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                        CC3DPlayerCard(player: player, index: index, compact: false)
                            .environmentObject(game)
                    }
                }
                .frame(width: 185)
            }
        } else {
            HStack(spacing: 5) {
                ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                    CC3DPlayerCard(player: player, index: index, compact: true)
                        .environmentObject(game)
                }
            }
        }
    }

    private var bottomDock: some View {
        HStack(spacing: 8) {
            Button { showPortfolio = true } label: {
                Image(systemName: "briefcase.fill")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)

            Button {
                game.rollAndAdvance()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "dice.fill")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(game.isHumanTurn ? "ROLL & MOVE" : "\(game.currentPlayer.name.uppercased()) IS PLAYING")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                        Text(game.lastRoll > 0 ? "Last roll \(game.lastRoll)" : "Drag the board to change the view")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .opacity(0.78)
                    }
                    Spacer()
                    Image(systemName: game.isHumanTurn ? "chevron.right.circle.fill" : "hourglass.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(ccPlayerColor(game.currentPlayerIndex))
            .disabled(!game.isHumanTurn || game.dealOffer != nil || game.gameOverMessage != nil)

            Button { showRules = true } label: {
                Image(systemName: "questionmark.circle.fill")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct CodeCapitalTabletop3D: View {
    @EnvironmentObject private var game: GameState
    let yaw: Float
    let tilt: Float

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "cc-tabletop-root"
            root.scale = SIMD3<Float>(repeating: 0.82)
            root.orientation = boardOrientation

            buildBoard(into: root)
            buildCenterCity(into: root)
            buildTiles(into: root)
            buildPawns(into: root)
            buildDice(into: root)
            buildDecor(into: root)

            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "cc-tabletop-root" }) else { return }
            root.orientation = boardOrientation

            for (index, player) in game.players.enumerated() {
                guard let pawn = root.findEntity(named: "cc-pawn-\(player.id.uuidString)") else { continue }
                let base = CC3DGeometry.position(for: player.position)
                var target = pawn.transform
                target.translation = base + pawnOffset(index)
                pawn.move(to: target, relativeTo: root, duration: 0.48, timingFunction: .easeInOut)
                pawn.isEnabled = !player.bankrupt
            }

            for tile in game.board where tile.isOwnable {
                if let flag = root.findEntity(named: "cc-owner-\(tile.id)") as? ModelEntity {
                    if let ownerID = game.owners[tile.id],
                       let ownerIndex = game.players.firstIndex(where: { $0.id == ownerID }) {
                        flag.isEnabled = true
                        flag.model?.materials = [SimpleMaterial(color: ccUIColor(ownerIndex), roughness: 0.38, isMetallic: false)]
                    } else {
                        flag.isEnabled = false
                    }
                }

                let level = game.scaleLevel(for: tile.id)
                for scaleIndex in 1...4 {
                    root.findEntity(named: "cc-scale-\(tile.id)-\(scaleIndex)")?.isEnabled = scaleIndex <= level
                }
            }

            if let die = root.findEntity(named: "cc-die") {
                die.isEnabled = game.lastRoll > 0
                var transform = die.transform
                let spin = Float(game.lastRoll) * 0.42
                transform.rotation = simd_quatf(angle: spin, axis: normalize(SIMD3<Float>(1, 0.7, 0.35)))
                die.move(to: transform, relativeTo: root, duration: 0.32, timingFunction: .easeInOut)
            }

            for pip in 1...6 {
                root.findEntity(named: "cc-pip-\(pip)")?.isEnabled = pip <= max(0, game.lastRoll)
            }
        }
        .allowsHitTesting(false)
    }

    private var boardOrientation: simd_quatf {
        simd_quatf(angle: tilt, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    private func buildBoard(into root: Entity) {
        let table = ModelEntity(
            mesh: .generateBox(size: [10.1, 0.26, 10.1]),
            materials: [SimpleMaterial(color: UIColor(red: 0.055, green: 0.035, blue: 0.025, alpha: 1), roughness: 0.82, isMetallic: false)]
        )
        table.position.y = -0.34
        root.addChild(table)

        let boardBase = ModelEntity(
            mesh: .generateBox(size: [8.95, 0.24, 8.95]),
            materials: [SimpleMaterial(color: UIColor(red: 0.095, green: 0.24, blue: 0.20, alpha: 1), roughness: 0.72, isMetallic: false)]
        )
        boardBase.position.y = -0.13
        root.addChild(boardBase)

        let boardTop = ModelEntity(
            mesh: .generateBox(size: [8.60, 0.07, 8.60]),
            materials: [SimpleMaterial(color: UIColor(red: 0.61, green: 0.76, blue: 0.63, alpha: 1), roughness: 0.9, isMetallic: false)]
        )
        boardTop.position.y = 0.02
        root.addChild(boardTop)

        let frameMaterial = SimpleMaterial(color: UIColor(red: 0.12, green: 0.09, blue: 0.07, alpha: 1), roughness: 0.58, isMetallic: false)
        let frame: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0, 0.02, -4.48], [9.20, 0.30, 0.22]),
            ([0, 0.02, 4.48], [9.20, 0.30, 0.22]),
            ([-4.48, 0.02, 0], [0.22, 0.30, 9.20]),
            ([4.48, 0.02, 0], [0.22, 0.30, 9.20])
        ]
        for item in frame {
            let entity = ModelEntity(mesh: .generateBox(size: item.1), materials: [frameMaterial])
            entity.position = item.0
            root.addChild(entity)
        }
    }

    private func buildTiles(into root: Entity) {
        for (index, tile) in game.board.enumerated() {
            let tileRoot = Entity()
            tileRoot.name = "cc-tile-\(tile.id)"
            tileRoot.position = CC3DGeometry.position(for: index)
            if CC3DGeometry.isVertical(index) {
                tileRoot.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
            }

            let slab = ModelEntity(
                mesh: .generateBox(size: [0.90, 0.15, 0.70]),
                materials: [SimpleMaterial(color: tileSurfaceColor(tile), roughness: 0.72, isMetallic: false)]
            )
            slab.position.y = 0.13
            tileRoot.addChild(slab)

            let band = ModelEntity(
                mesh: .generateBox(size: [0.90, 0.075, 0.16]),
                materials: [SimpleMaterial(color: ccTileUIColor(tile), roughness: 0.44, isMetallic: false)]
            )
            band.position = [0, 0.245, -0.26]
            tileRoot.addChild(band)

            if tile.isOwnable {
                let owner = ModelEntity(
                    mesh: .generateBox(size: [0.20, 0.20, 0.20]),
                    materials: [SimpleMaterial(color: .white, roughness: 0.4, isMetallic: false)]
                )
                owner.name = "cc-owner-\(tile.id)"
                owner.position = [0.31, 0.34, -0.22]
                owner.isEnabled = false
                tileRoot.addChild(owner)

                for level in 1...4 {
                    let height = Float(0.16 + Double(level) * 0.045)
                    let upgrade = ModelEntity(
                        mesh: .generateBox(size: [0.11, height, 0.11]),
                        materials: [SimpleMaterial(color: ccTileUIColor(tile), roughness: 0.50, isMetallic: false)]
                    )
                    upgrade.name = "cc-scale-\(tile.id)-\(level)"
                    upgrade.position = [Float(level - 2) * 0.12, 0.28 + height / 2, 0.17]
                    upgrade.isEnabled = false
                    tileRoot.addChild(upgrade)
                }
            } else {
                let marker = ModelEntity(
                    mesh: markerMesh(for: tile.kind),
                    materials: [SimpleMaterial(color: ccTileUIColor(tile), roughness: 0.45, isMetallic: tile.kind == .market)]
                )
                marker.position = [0, 0.34, 0.05]
                tileRoot.addChild(marker)
            }

            root.addChild(tileRoot)
        }
    }

    private func buildCenterCity(into root: Entity) {
        let plaza = ModelEntity(
            mesh: .generateBox(size: [5.55, 0.10, 5.55]),
            materials: [SimpleMaterial(color: UIColor(red: 0.035, green: 0.085, blue: 0.095, alpha: 1), roughness: 0.72, isMetallic: false)]
        )
        plaza.position.y = 0.11
        root.addChild(plaza)

        let roadMaterial = SimpleMaterial(color: UIColor(white: 0.16, alpha: 1), roughness: 0.9, isMetallic: false)
        let roadX = ModelEntity(mesh: .generateBox(size: [5.15, 0.035, 0.62]), materials: [roadMaterial])
        roadX.position.y = 0.18
        root.addChild(roadX)
        let roadZ = ModelEntity(mesh: .generateBox(size: [0.62, 0.035, 5.15]), materials: [roadMaterial])
        roadZ.position.y = 0.18
        root.addChild(roadZ)

        let buildings: [(Float, Float, Float, UIColor)] = [
            (-1.75, -1.65, 1.28, .systemBlue), (-0.95, -1.65, 0.82, .systemTeal),
            (1.05, -1.60, 1.58, .systemPurple), (1.85, -1.55, 1.02, .systemOrange),
            (-1.75, 1.55, 0.95, .systemPink), (-0.95, 1.55, 1.48, .systemIndigo),
            (1.05, 1.55, 0.78, .systemGreen), (1.85, 1.55, 1.32, .systemCyan),
            (-1.85, 0.55, 0.62, .systemMint), (1.85, 0.55, 0.72, .systemRed)
        ]
        for (x, z, h, color) in buildings {
            addBuilding(to: root, x: x, z: z, height: h, color: color)
        }

        let tower = ModelEntity(
            mesh: .generateBox(size: [0.86, 1.86, 0.86]),
            materials: [SimpleMaterial(color: UIColor.systemCyan, roughness: 0.32, isMetallic: true)]
        )
        tower.position = [0.90, 1.12, 0.60]
        root.addChild(tower)

        let crown = ModelEntity(
            mesh: .generateBox(size: [1.0, 0.12, 1.0]),
            materials: [SimpleMaterial(color: UIColor.white.withAlphaComponent(0.88), roughness: 0.25, isMetallic: true)]
        )
        crown.position = [0.90, 2.10, 0.60]
        root.addChild(crown)
    }

    private func buildPawns(into root: Entity) {
        for (index, player) in game.players.enumerated() {
            let pawn = makePawn(index: index)
            pawn.name = "cc-pawn-\(player.id.uuidString)"
            pawn.position = CC3DGeometry.position(for: player.position) + pawnOffset(index)
            root.addChild(pawn)
        }
    }

    private func makePawn(index: Int) -> Entity {
        let root = Entity()
        let color = ccUIColor(index)

        let base = ModelEntity(
            mesh: .generateCylinder(height: 0.12, radius: 0.18),
            materials: [SimpleMaterial(color: color, roughness: 0.32, isMetallic: true)]
        )
        base.position.y = 0.06
        root.addChild(base)

        let body = ModelEntity(
            mesh: .generateCylinder(height: 0.32, radius: 0.095),
            materials: [SimpleMaterial(color: color, roughness: 0.48, isMetallic: false)]
        )
        body.position.y = 0.28
        root.addChild(body)

        let head = ModelEntity(
            mesh: .generateSphere(radius: 0.115),
            materials: [SimpleMaterial(color: UIColor(red: 0.96, green: 0.77, blue: 0.60, alpha: 1), roughness: 0.72, isMetallic: false)]
        )
        head.position.y = 0.55
        root.addChild(head)

        return root
    }

    private func buildDice(into root: Entity) {
        let die = ModelEntity(
            mesh: .generateBox(size: 0.62, cornerRadius: 0.11),
            materials: [SimpleMaterial(color: .white, roughness: 0.28, isMetallic: false)]
        )
        die.name = "cc-die"
        die.position = [0, 0.67, -0.28]
        die.isEnabled = game.lastRoll > 0

        let pipPositions: [SIMD3<Float>] = [
            [0, 0.325, 0], [-0.17, 0.325, -0.17], [0.17, 0.325, 0.17],
            [-0.17, 0.325, 0.17], [0.17, 0.325, -0.17], [0, 0.325, -0.19]
        ]
        for index in 0..<6 {
            let pip = ModelEntity(
                mesh: .generateSphere(radius: 0.043),
                materials: [SimpleMaterial(color: .black, roughness: 0.45, isMetallic: false)]
            )
            pip.name = "cc-pip-\(index + 1)"
            pip.position = pipPositions[index]
            pip.isEnabled = (index + 1) <= game.lastRoll
            die.addChild(pip)
        }
        root.addChild(die)
    }

    private func buildDecor(into root: Entity) {
        let postMaterial = SimpleMaterial(color: UIColor(red: 0.12, green: 0.45, blue: 0.28, alpha: 1), roughness: 0.72, isMetallic: false)
        for x in stride(from: -2.7 as Float, through: 2.7, by: 0.9) {
            for z in [-2.72 as Float, 2.72 as Float] {
                let tree = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [postMaterial])
                tree.position = [x, 0.36, z]
                root.addChild(tree)
            }
        }
    }

    private func addBuilding(to root: Entity, x: Float, z: Float, height: Float, color: UIColor) {
        let building = ModelEntity(
            mesh: .generateBox(size: [0.55, height, 0.55]),
            materials: [SimpleMaterial(color: color, roughness: 0.48, isMetallic: false)]
        )
        building.position = [x, 0.20 + height / 2, z]
        root.addChild(building)

        let roof = ModelEntity(
            mesh: .generateBox(size: [0.62, 0.08, 0.62]),
            materials: [SimpleMaterial(color: UIColor.white.withAlphaComponent(0.82), roughness: 0.35, isMetallic: true)]
        )
        roof.position = [x, 0.24 + height, z]
        root.addChild(roof)
    }

    private func pawnOffset(_ index: Int) -> SIMD3<Float> {
        let offsets: [SIMD3<Float>] = [
            [-0.20, 0.33, -0.15], [0.20, 0.33, -0.15],
            [-0.20, 0.33, 0.17], [0.20, 0.33, 0.17]
        ]
        return offsets[index % offsets.count]
    }

    private func markerMesh(for kind: TileKind) -> MeshResource {
        switch kind {
        case .launch: return .generateCone(height: 0.27, radius: 0.12)
        case .career: return .generateBox(size: [0.24, 0.20, 0.16])
        case .incident: return .generateCone(height: 0.25, radius: 0.14)
        case .market: return .generateSphere(radius: 0.13)
        case .skill: return .generateBox(size: [0.19, 0.24, 0.19])
        case .wellbeing: return .generateSphere(radius: 0.13)
        case .openSource: return .generateCylinder(height: 0.22, radius: 0.12)
        case .aiFrontier: return .generateSphere(radius: 0.15)
        case .tax: return .generateBox(size: [0.25, 0.18, 0.18])
        case .project: return .generateBox(size: [0.18, 0.18, 0.18])
        }
    }

    private func tileSurfaceColor(_ tile: BoardTile) -> UIColor {
        tile.isOwnable ? UIColor(red: 0.91, green: 0.94, blue: 0.88, alpha: 1) : UIColor(red: 0.78, green: 0.84, blue: 0.76, alpha: 1)
    }
}

private enum CC3DGeometry {
    static func position(for index: Int) -> SIMD3<Float> {
        let step: Float = 0.90
        let low: Float = -3.60
        let high: Float = 3.60

        switch index {
        case 0...8:
            return [low + Float(index) * step, 0.10, high]
        case 9...16:
            return [high, 0.10, high - Float(index - 8) * step]
        case 17...24:
            return [high - Float(index - 16) * step, 0.10, low]
        default:
            return [low, 0.10, low + Float(index - 24) * step]
        }
    }

    static func isVertical(_ index: Int) -> Bool {
        (9...16).contains(index) || (25...31).contains(index)
    }
}

private struct CC3DPlayerCard: View {
    @EnvironmentObject private var game: GameState
    let player: Player
    let index: Int
    let compact: Bool

    var body: some View {
        let active = index == game.currentPlayerIndex
        VStack(alignment: .leading, spacing: compact ? 2 : 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(ccPlayerColor(index).gradient)
                    .frame(width: compact ? 9 : 16, height: compact ? 9 : 16)
                Text(player.name)
                    .font(.system(size: compact ? 8 : 11, weight: .black, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 1)
                if active { Image(systemName: "play.fill").font(.system(size: 7)).foregroundStyle(ccPlayerColor(index)) }
            }
            Text(player.bankrupt ? "OUT" : "₱\(ccMoney(game.netWorth(for: player)))")
                .font(.system(size: compact ? 8 : 13, weight: .black, design: .rounded))
                .foregroundStyle(player.bankrupt ? .red : .white)
            if !compact {
                Text("Cash ₱\(ccMoney(player.cash))  •  \(game.ownedProjects(for: player.id).count) projects")
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 5 : 8)
        .background(active ? ccPlayerColor(index).opacity(0.20) : Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(active ? ccPlayerColor(index) : .white.opacity(0.10), lineWidth: active ? 1.4 : 0.7) }
    }
}

private struct CC3DDealCard: View {
    @EnvironmentObject private var game: GameState
    let offer: DealOffer

    var tile: BoardTile? { game.board.first(where: { $0.id == offer.tileID }) }

    var body: some View {
        if let tile {
            VStack(spacing: 13) {
                Capsule().fill(.white.opacity(0.22)).frame(width: 42, height: 4)
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(ccTileColor(tile).opacity(0.18))
                    Image(systemName: offer.kind == .acquire ? "building.2.fill" : "arrow.up.right.circle.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(ccTileColor(tile))
                }
                .frame(width: 70, height: 70)

                VStack(spacing: 2) {
                    Text(offer.kind == .acquire ? "ACQUIRE \(tile.title.uppercased())?" : "SCALE \(tile.title.uppercased())?")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(tile.district?.rawValue ?? "Independent Product")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 7) {
                    metric("COST", "₱\(offer.cost.formatted())")
                    metric("REVENUE", "₱\(offer.projectedRevenue.formatted())")
                    metric("CASH", "₱\(game.currentPlayer.cash.formatted())")
                }

                HStack(spacing: 10) {
                    Button("PASS") { game.declineDeal() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button(offer.kind == .acquire ? "ACQUIRE" : "SCALE") { game.acceptDeal() }
                        .buttonStyle(.borderedProminent)
                        .tint(ccTileColor(tile))
                        .frame(maxWidth: .infinity)
                        .disabled(game.currentPlayer.cash < offer.cost)
                }
            }
            .padding(18)
            .frame(maxWidth: 390)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.14), lineWidth: 1) }
            .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
            .padding(20)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 7, weight: .black, design: .rounded)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .black, design: .rounded)).minimumScaleFactor(0.65).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CC3DEventCard: View {
    let event: IndustryEvent
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(.orange.opacity(0.20))
                Image(systemName: "bolt.fill").foregroundStyle(.orange)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.subheadline.bold())
                Text(event.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("OK", action: dismiss).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(11)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 17))
        .shadow(color: .black.opacity(0.42), radius: 14, y: 7)
    }
}

private struct CC3DPortfolioView: View {
    @EnvironmentObject private var game: GameState
    var body: some View {
        NavigationStack {
            List {
                Section("Players") {
                    ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                        HStack {
                            Circle().fill(ccPlayerColor(index)).frame(width: 10, height: 10)
                            Text(player.name)
                            Spacer()
                            Text(player.bankrupt ? "OUT" : "₱\(game.netWorth(for: player).formatted())").fontWeight(.bold)
                        }
                    }
                }
                Section("Your Products") {
                    let products = game.ownedProjects(for: game.players[0].id)
                    if products.isEmpty { Text("No acquisitions yet.").foregroundStyle(.secondary) }
                    ForEach(products) { tile in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tile.title).font(.headline)
                                Text(tile.district?.rawValue ?? "Product").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Scale \(game.scaleLevel(for: tile.id))/4").font(.caption.bold())
                        }
                    }
                }
            }
            .navigationTitle("Portfolio")
        }
    }
}

private struct CC3DRulesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Objective") { Text("Build the strongest software empire by acquiring products, completing technology districts, scaling them, and collecting usage revenue from rival engineers.") }
                Section("3D Tabletop") { Text("Drag on the board to change the viewing angle. The raised tiles, center city, player pieces, ownership markers, scale towers, and die are rendered as real RealityKit geometry.") }
                Section("Original Theme") { Text("The presentation follows premium digital tabletop conventions while Code Capital keeps its own software-economy board, names, rules, artwork, and assets.") }
            }
            .navigationTitle("How to Play")
        }
    }
}

private struct CC3DGameOver: View {
    let message: String
    let restart: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "trophy.fill").font(.system(size: 54)).foregroundStyle(.yellow)
                Text("MATCH COMPLETE").font(.caption.black()).tracking(2)
                Text(message).font(.title3.bold()).multilineTextAlignment(.center)
                Button("PLAY AGAIN", action: restart).buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(26)
            .frame(maxWidth: 360)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

private func ccPlayerColor(_ index: Int) -> Color {
    [.cyan, .orange, .pink, .green][index % 4]
}

private func ccUIColor(_ index: Int) -> UIColor {
    [.systemCyan, .systemOrange, .systemPink, .systemGreen][index % 4]
}

private func ccTileColor(_ tile: BoardTile) -> Color {
    Color(uiColor: ccTileUIColor(tile))
}

private func ccTileUIColor(_ tile: BoardTile) -> UIColor {
    if let district = tile.district {
        switch district {
        case .frontend: return .systemBrown
        case .backend: return .systemCyan
        case .mobile: return .systemPink
        case .dataAI: return .systemOrange
        case .cloud: return .systemRed
        case .devTools: return .systemYellow
        case .creator: return .systemGreen
        case .security: return .systemBlue
        }
    }
    switch tile.kind {
    case .launch: return .systemGreen
    case .project: return .systemGray
    case .career: return .systemIndigo
    case .incident: return .systemOrange
    case .market: return .systemMint
    case .skill: return .systemPurple
    case .wellbeing: return .systemPink
    case .openSource: return .systemTeal
    case .aiFrontier: return .systemCyan
    case .tax: return .systemRed
    }
}

private func ccMoney(_ value: Int) -> String {
    let amount = abs(value)
    let sign = value < 0 ? "-" : ""
    if amount >= 1_000_000 { return "\(sign)\(String(format: "%.1fM", Double(amount) / 1_000_000))" }
    if amount >= 1_000 { return "\(sign)\(String(format: "%.0fK", Double(amount) / 1_000))" }
    return "\(value)"
}
