import SwiftUI
import SceneKit
import UIKit

struct GameRootSceneKitView: View {
    @EnvironmentObject private var game: GameState

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height * 1.1

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.01, green: 0.02, blue: 0.025), Color(red: 0.025, green: 0.07, blue: 0.075), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                CodeCapitalSceneKitBoard(game: game, landscape: landscape)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.42), .clear, .black.opacity(0.48)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 8) {
                    header
                    if landscape {
                        HStack {
                            Spacer()
                            playerRail
                                .frame(width: 176)
                        }
                    } else {
                        playerStrip
                    }
                    Spacer()
                    actionBar
                }
                .padding(.horizontal, landscape ? 14 : 9)
                .padding(.vertical, 8)
            }
            .overlay {
                if let offer = game.dealOffer {
                    SceneKitDealCard(offer: offer)
                        .environmentObject(game)
                        .zIndex(20)
                }
            }
            .overlay(alignment: .bottom) {
                if let event = game.currentEvent, game.dealOffer == nil {
                    SceneKitEventCard(event: event) {
                        game.currentEvent = nil
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 84)
                    .zIndex(15)
                }
            }
            .overlay {
                if let message = game.gameOverMessage {
                    ZStack {
                        Color.black.opacity(0.7).ignoresSafeArea()
                        VStack(spacing: 14) {
                            Image(systemName: "trophy.fill").font(.system(size: 48)).foregroundStyle(.yellow)
                            Text("MATCH COMPLETE").font(.caption.weight(.black)).tracking(2)
                            Text(message).font(.headline).multilineTextAlignment(.center)
                            Button("PLAY AGAIN") { game.restart() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                        .padding(24)
                        .frame(maxWidth: 340)
                        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 22))
                    }
                    .zIndex(30)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 0) {
                Text("CODE CAPITAL")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(1.2)
                Text("3D SOFTWARE EMPIRE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(game.era.rawValue.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.cyan)
                Text("ROUND \(game.turn) / 40")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
    }

    private var playerStrip: some View {
        HStack(spacing: 5) {
            ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                playerCard(player, index: index, compact: true)
            }
        }
    }

    private var playerRail: some View {
        VStack(spacing: 6) {
            ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                playerCard(player, index: index, compact: false)
            }
        }
    }

    private func playerCard(_ player: Player, index: Int, compact: Bool) -> some View {
        let active = index == game.currentPlayerIndex
        return VStack(alignment: .leading, spacing: compact ? 2 : 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(scenePlayerColor(index))
                    .frame(width: compact ? 13 : 20, height: compact ? 13 : 20)
                Text(player.name)
                    .font(.system(size: compact ? 8 : 11, weight: .black, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 1)
                if active { Image(systemName: "play.fill").font(.system(size: 7)).foregroundStyle(scenePlayerColor(index)) }
            }
            Text(player.bankrupt ? "OUT" : "₱\(sceneCompactMoney(game.netWorth(for: player)))")
                .font(.system(size: compact ? 8 : 13, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 5 : 8)
        .background(active ? scenePlayerColor(index).opacity(0.20) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(active ? scenePlayerColor(index) : .white.opacity(0.12), lineWidth: active ? 1.5 : 1) }
    }

    private var actionBar: some View {
        Button {
            game.rollAndAdvance()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "dice.fill").font(.title3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.isHumanTurn ? "ROLL & MOVE" : "\(game.currentPlayer.name.uppercased()) IS PLAYING")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                    Text(game.lastRoll > 0 ? "Last roll \(game.lastRoll)" : "Tabletop camera locked to board")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .opacity(0.78)
                }
                Spacer()
                Image(systemName: game.isHumanTurn ? "chevron.right.circle.fill" : "hourglass.circle.fill")
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(scenePlayerColor(game.currentPlayerIndex))
        .disabled(!game.isHumanTurn || game.dealOffer != nil || game.gameOverMessage != nil)
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct CodeCapitalSceneKitBoard: UIViewRepresentable {
    @ObservedObject var game: GameState
    let landscape: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.scene = makeScene()
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: true)
        context.coordinator.scene = view.scene
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }
        updateCamera(in: scene)

        for (index, player) in game.players.enumerated() {
            guard let pawn = scene.rootNode.childNode(withName: "pawn-\(index)", recursively: true) else { continue }
            let p = Board3DPosition.position(for: player.position)
            let offsets: [(Float, Float)] = [(-0.20, -0.16), (0.20, -0.16), (-0.20, 0.16), (0.20, 0.16)]
            let o = offsets[index % offsets.count]
            let move = SCNAction.move(to: SCNVector3(p.x + o.0, 0.64, p.z + o.1), duration: 0.42)
            move.timingMode = .easeInEaseOut
            pawn.runAction(move)
            pawn.isHidden = player.bankrupt
        }

        for tile in game.board where tile.isOwnable {
            let ownerNode = scene.rootNode.childNode(withName: "owner-\(tile.id)", recursively: true)
            if let ownerID = game.owners[tile.id], let ownerIndex = game.players.firstIndex(where: { $0.id == ownerID }) {
                ownerNode?.isHidden = false
                ownerNode?.geometry?.firstMaterial?.diffuse.contents = sceneUIColor(ownerIndex)
            } else {
                ownerNode?.isHidden = true
            }

            let level = game.scaleLevel(for: tile.id)
            for i in 1...4 {
                scene.rootNode.childNode(withName: "scale-\(tile.id)-\(i)", recursively: true)?.isHidden = i > level
            }
        }

        if let die = scene.rootNode.childNode(withName: "die", recursively: true) {
            die.isHidden = game.lastRoll == 0
            if game.lastRoll > 0 {
                die.removeAllActions()
                let angle = CGFloat(Double(game.lastRoll) * 0.75)
                die.runAction(.rotateBy(x: angle, y: angle * 0.8, z: angle * 0.4, duration: 0.34))
            }
        }
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let focus = SCNNode()
        focus.name = "focus"
        focus.position = SCNVector3(0, 0.4, 0)
        scene.rootNode.addChildNode(focus)

        let camera = SCNNode()
        camera.name = "camera"
        let cameraObject = SCNCamera()
        cameraObject.fieldOfView = 41
        cameraObject.zNear = 0.1
        cameraObject.zFar = 100
        camera.camera = cameraObject
        camera.position = SCNVector3(0, 11.0, 12.8)
        let constraint = SCNLookAtConstraint(target: focus)
        constraint.isGimbalLockEnabled = true
        camera.constraints = [constraint]
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(white: 0.68, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1500
        key.light?.castsShadow = true
        key.eulerAngles = SCNVector3(-0.95, 0.65, 0)
        key.position = SCNVector3(-4, 10, 8)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 900
        fill.light?.color = UIColor.systemCyan
        fill.position = SCNVector3(0, 7, -3)
        scene.rootNode.addChildNode(fill)

        addBoard(to: scene.rootNode)
        addTiles(to: scene.rootNode)
        addCity(to: scene.rootNode)
        addPawns(to: scene.rootNode)
        addDie(to: scene.rootNode)
        return scene
    }

    private func updateCamera(in scene: SCNScene) {
        guard let camera = scene.rootNode.childNode(withName: "camera", recursively: false) else { return }
        camera.position = landscape ? SCNVector3(-0.4, 10.0, 12.0) : SCNVector3(0, 13.5, 15.6)
        camera.camera?.fieldOfView = landscape ? 42 : 39
    }

    private func addBoard(to root: SCNNode) {
        root.addChildNode(box(name: "table", width: 10.4, height: 0.32, length: 10.4, color: UIColor(red: 0.045, green: 0.026, blue: 0.018, alpha: 1), y: -0.35))
        root.addChildNode(box(name: "board-base", width: 9.15, height: 0.26, length: 9.15, color: UIColor(red: 0.08, green: 0.22, blue: 0.18, alpha: 1), y: -0.10))
        root.addChildNode(box(name: "board-top", width: 8.78, height: 0.08, length: 8.78, color: UIColor(red: 0.62, green: 0.76, blue: 0.64, alpha: 1), y: 0.07))

        let frameColor = UIColor(red: 0.13, green: 0.09, blue: 0.06, alpha: 1)
        let edges: [(Float, Float, Float, Float, Float)] = [
            (0, -4.55, 9.3, 0.28, 0.24), (0, 4.55, 9.3, 0.28, 0.24),
            (-4.55, 0, 0.24, 0.28, 9.3), (4.55, 0, 0.24, 0.28, 9.3)
        ]
        for (x, z, w, h, l) in edges {
            let n = box(name: nil, width: w, height: h, length: l, color: frameColor, y: 0.08)
            n.position.x = x
            n.position.z = z
            root.addChildNode(n)
        }
    }

    private func addTiles(to root: SCNNode) {
        for (index, tile) in game.board.enumerated() {
            let p = Board3DPosition.position(for: index)
            let tileRoot = SCNNode()
            tileRoot.name = "tile-\(tile.id)"
            tileRoot.position = SCNVector3(p.x, 0.18, p.z)
            if Board3DPosition.isVertical(index) { tileRoot.eulerAngles.y = .pi / 2 }

            tileRoot.addChildNode(box(name: nil, width: 0.90, height: 0.16, length: 0.70, color: tile.isOwnable ? UIColor(red: 0.91, green: 0.94, blue: 0.88, alpha: 1) : UIColor(red: 0.80, green: 0.85, blue: 0.78, alpha: 1), y: 0))
            let band = box(name: nil, width: 0.90, height: 0.09, length: 0.17, color: tileUIColor(tile), y: 0.12)
            band.position.z = -0.25
            tileRoot.addChildNode(band)

            let label = SCNNode(geometry: textGeometry(shortTitle(tile.title), color: .black))
            label.scale = SCNVector3(0.055, 0.055, 0.055)
            label.position = SCNVector3(-0.34, 0.105, 0.11)
            label.eulerAngles.x = -.pi / 2
            tileRoot.addChildNode(label)

            if tile.isOwnable {
                let owner = box(name: "owner-\(tile.id)", width: 0.17, height: 0.22, length: 0.17, color: .white, y: 0.24)
                owner.position.x = 0.30
                owner.position.z = -0.21
                owner.isHidden = true
                tileRoot.addChildNode(owner)
                for i in 1...4 {
                    let n = box(name: "scale-\(tile.id)-\(i)", width: 0.11, height: 0.16 + Float(i) * 0.04, length: 0.11, color: tileUIColor(tile), y: 0.24)
                    n.position.x = Float(i - 2) * 0.12
                    n.position.z = 0.19
                    n.isHidden = true
                    tileRoot.addChildNode(n)
                }
            }
            root.addChildNode(tileRoot)
        }
    }

    private func addCity(to root: SCNNode) {
        let plaza = box(name: "plaza", width: 5.55, height: 0.12, length: 5.55, color: UIColor(red: 0.035, green: 0.085, blue: 0.095, alpha: 1), y: 0.16)
        root.addChildNode(plaza)
        root.addChildNode(box(name: nil, width: 5.1, height: 0.04, length: 0.58, color: UIColor(white: 0.13, alpha: 1), y: 0.24))
        root.addChildNode(box(name: nil, width: 0.58, height: 0.04, length: 5.1, color: UIColor(white: 0.13, alpha: 1), y: 0.24))

        let buildings: [(Float, Float, Float, UIColor)] = [
            (-1.75,-1.65,1.15,.systemBlue),(-0.95,-1.65,0.78,.systemTeal),(1.05,-1.60,1.52,.systemPurple),(1.85,-1.55,0.98,.systemOrange),
            (-1.75,1.55,0.92,.systemPink),(-0.95,1.55,1.40,.systemIndigo),(1.05,1.55,0.74,.systemGreen),(1.85,1.55,1.24,.systemCyan),
            (-1.85,0.55,0.60,.systemMint),(1.85,0.55,0.68,.systemRed)
        ]
        for (x,z,h,c) in buildings {
            let b = box(name: nil, width: 0.56, height: h, length: 0.56, color: c, y: 0.28 + h/2)
            b.position.x = x; b.position.z = z
            root.addChildNode(b)
            let roof = box(name: nil, width: 0.64, height: 0.08, length: 0.64, color: UIColor.white.withAlphaComponent(0.85), y: 0.33 + h)
            roof.position.x = x; roof.position.z = z
            root.addChildNode(roof)
        }

        let tower = box(name: "tower", width: 0.86, height: 1.95, length: 0.86, color: .systemCyan, y: 1.27)
        tower.position.x = 0.88; tower.position.z = 0.58
        root.addChildNode(tower)

        let title = SCNNode(geometry: textGeometry("CODE\nCAPITAL", color: .white))
        title.scale = SCNVector3(0.12, 0.12, 0.12)
        title.position = SCNVector3(-0.72, 0.28, 0.05)
        title.eulerAngles.x = -.pi / 2
        root.addChildNode(title)
    }

    private func addPawns(to root: SCNNode) {
        for index in game.players.indices {
            let pawn = SCNNode()
            pawn.name = "pawn-\(index)"
            let p = Board3DPosition.position(for: 0)
            pawn.position = SCNVector3(p.x, 0.64, p.z)

            let base = SCNNode(geometry: SCNCylinder(radius: 0.16, height: 0.10))
            base.geometry?.firstMaterial = material(sceneUIColor(index), metalness: 0.75)
            base.position.y = 0.05
            pawn.addChildNode(base)

            let body = SCNNode(geometry: SCNCylinder(radius: 0.085, height: 0.28))
            body.geometry?.firstMaterial = material(sceneUIColor(index))
            body.position.y = 0.24
            pawn.addChildNode(body)

            let head = SCNNode(geometry: SCNSphere(radius: 0.105))
            head.geometry?.firstMaterial = material(UIColor(red: 0.96, green: 0.77, blue: 0.60, alpha: 1))
            head.position.y = 0.48
            pawn.addChildNode(head)
            root.addChildNode(pawn)
        }
    }

    private func addDie(to root: SCNNode) {
        let die = SCNNode(geometry: SCNBox(width: 0.62, height: 0.62, length: 0.62, chamferRadius: 0.10))
        die.name = "die"
        die.geometry?.firstMaterial = material(.white, metalness: 0.05)
        die.position = SCNVector3(0, 0.72, -0.35)
        die.isHidden = true
        root.addChildNode(die)
    }

    private func box(name: String?, width: Float, height: Float, length: Float, color: UIColor, y: Float) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.02)
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position.y = y
        return node
    }

    private func textGeometry(_ text: String, color: UIColor) -> SCNText {
        let g = SCNText(string: text, extrusionDepth: 0.2)
        g.font = UIFont.systemFont(ofSize: 4, weight: .black)
        g.flatness = 0.2
        g.firstMaterial = material(color)
        return g
    }

    private func material(_ color: UIColor, metalness: CGFloat = 0.0) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.roughness.contents = 0.58
        m.metalness.contents = metalness
        return m
    }

    private func shortTitle(_ title: String) -> String {
        let words = title.split(separator: " ")
        return words.count <= 2 ? title : words.prefix(2).joined(separator: " ")
    }

    final class Coordinator {
        var scene: SCNScene?
    }
}

private enum Board3DPosition {
    static func position(for index: Int) -> (x: Float, z: Float) {
        let step: Float = 0.90, low: Float = -3.60, high: Float = 3.60
        switch index {
        case 0...8: return (low + Float(index) * step, high)
        case 9...16: return (high, high - Float(index - 8) * step)
        case 17...24: return (high - Float(index - 16) * step, low)
        default: return (low, low + Float(index - 24) * step)
        }
    }
    static func isVertical(_ index: Int) -> Bool { (9...16).contains(index) || (25...31).contains(index) }
}

private struct SceneKitDealCard: View {
    @EnvironmentObject private var game: GameState
    let offer: DealOffer
    private var tile: BoardTile? { game.board.first(where: { $0.id == offer.tileID }) }

    var body: some View {
        VStack(spacing: 12) {
            if let tile {
                Image(systemName: offer.kind == .acquire ? "building.2.fill" : "arrow.up.right.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(sceneTileColor(tile))
                Text(offer.kind == .acquire ? "Acquire \(tile.title)?" : "Scale \(tile.title)?")
                    .font(.title3.weight(.black))
                    .multilineTextAlignment(.center)
                Text("₱\(offer.cost.formatted()) • Revenue ₱\(offer.projectedRevenue.formatted())")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                HStack {
                    Button("PASS") { game.declineDeal() }.buttonStyle(.bordered)
                    Button(offer.kind == .acquire ? "ACQUIRE" : "SCALE") { game.acceptDeal() }
                        .buttonStyle(.borderedProminent)
                        .disabled(game.currentPlayer.cash < offer.cost)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1) }
        .shadow(radius: 22)
    }
}

private struct SceneKitEventCard: View {
    let event: IndustryEvent
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline.bold())
                Text(event.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            Button("OK", action: dismiss).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(12)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 17))
    }
}

private func tileUIColor(_ tile: BoardTile) -> UIColor {
    guard let district = tile.district else {
        switch tile.kind {
        case .launch: return .systemGreen
        case .career: return .systemIndigo
        case .incident: return .systemOrange
        case .market: return .systemMint
        case .skill: return .systemPurple
        case .wellbeing: return .systemPink
        case .openSource: return .systemTeal
        case .aiFrontier: return .systemCyan
        case .tax: return .systemRed
        case .project: return .systemGray
        }
    }
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

private func sceneTileColor(_ tile: BoardTile) -> Color { Color(uiColor: tileUIColor(tile)) }
private func sceneUIColor(_ index: Int) -> UIColor { [.systemCyan, .systemOrange, .systemPink, .systemGreen][index % 4] }
private func scenePlayerColor(_ index: Int) -> Color { Color(uiColor: sceneUIColor(index)) }

private func sceneCompactMoney(_ value: Int) -> String {
    if abs(value) >= 1_000_000 { return "\(Double(value) / 1_000_000, specifier: "%.1f")M" }
    if abs(value) >= 1_000 { return "\(Double(value) / 1_000, specifier: "%.0f")K" }
    return "\(value)"
}
