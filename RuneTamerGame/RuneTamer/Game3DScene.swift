import SwiftUI
import SceneKit
import UIKit

struct RuneWorld3DView: UIViewRepresentable {
    @ObservedObject var controller: RuneWorld3DController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = controller.scene
        view.delegate = controller
        view.pointOfView = controller.camera
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = UIColor(red: 0.45, green: 0.72, blue: 0.88, alpha: 1)

        let pan = UIPanGestureRecognizer(target: controller, action: #selector(RuneWorld3DController.handleCameraPan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: controller, action: #selector(RuneWorld3DController.handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene !== controller.scene { uiView.scene = controller.scene }
        if uiView.pointOfView !== controller.camera { uiView.pointOfView = controller.camera }
    }
}

final class RuneWorld3DController: NSObject, ObservableObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let player = SCNNode()
    let camera = SCNNode()

    @Published var locationName = "Aetherwild · Runehaven Meadow"

    private let cameraYawNode = SCNNode()
    private let cameraPitchNode = SCNNode()
    private var moveInput = SIMD2<Float>(repeating: 0)
    private var cameraYaw: Float = 0
    private var cameraPitch: Float = -0.24
    private var cameraDistance: Float = 7.2
    private var lastUpdate: TimeInterval = 0
    private var speedMultiplier: Float = 1
    private var isJumping = false
    private var monsterNodes: [(node: SCNNode, creature: Creature)] = []
    private weak var game: GameState?

    override init() {
        super.init()
        configureScene()
    }

    func connect(game: GameState) {
        self.game = game
    }

    func setMove(strafe: Float, forward: Float) {
        moveInput = SIMD2<Float>(strafe, forward)
    }

    func stopMoving() {
        moveInput = .zero
    }

    func dash() {
        speedMultiplier = 2.0
        let oldScale = player.scale
        player.scale = SCNVector3(oldScale.x * 0.95, oldScale.y * 1.05, oldScale.z * 0.95)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            guard let self else { return }
            self.speedMultiplier = 1
            self.player.scale = SCNVector3(1, 1, 1)
        }
    }

    func jump() {
        guard !isJumping else { return }
        isJumping = true
        let up = SCNAction.moveBy(x: 0, y: 1.35, z: 0, duration: 0.28)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -1.35, z: 0, duration: 0.34)
        down.timingMode = .easeIn
        player.runAction(.sequence([up, down])) { [weak self] in
            self?.isJumping = false
        }
    }

    func primaryAction() {
        animateAttack()
        guard let game else { return }
        guard let target = nearestCreature(maxDistance: 4.1) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            game.beginEncounter(target)
        }
    }

    @objc func handleCameraPan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
        cameraYaw -= Float(delta.x) * 0.006
        cameraPitch -= Float(delta.y) * 0.004
        cameraPitch = min(0.12, max(-0.72, cameraPitch))
        cameraYawNode.eulerAngles.y = cameraYaw
        cameraPitchNode.eulerAngles.x = cameraPitch
    }

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        cameraDistance /= Float(gesture.scale)
        cameraDistance = min(10.5, max(4.4, cameraDistance))
        camera.position.z = cameraDistance
        gesture.scale = 1
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard lastUpdate > 0 else {
            lastUpdate = time
            return
        }

        let dt = Float(min(1.0 / 20.0, time - lastUpdate))
        lastUpdate = time

        let magnitude = simd_length(moveInput)
        if magnitude > 0.04 {
            let input = magnitude > 1 ? simd_normalize(moveInput) : moveInput
            let forward = SIMD3<Float>(-sin(cameraYaw), 0, -cos(cameraYaw))
            let right = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
            var direction = right * input.x + forward * input.y
            if simd_length(direction) > 0.001 {
                direction = simd_normalize(direction)
                let speed: Float = 5.3 * speedMultiplier
                player.simdPosition += direction * speed * dt
                player.simdPosition.x = min(53, max(-53, player.simdPosition.x))
                player.simdPosition.z = min(53, max(-53, player.simdPosition.z))

                let targetYaw = atan2(direction.x, direction.z) + .pi
                player.eulerAngles.y = lerpAngle(player.eulerAngles.y, targetYaw, factor: min(1, dt * 10))
            }
        }

        let target = SCNVector3(player.position.x, player.position.y + 1.3, player.position.z)
        cameraYawNode.position.x += (target.x - cameraYawNode.position.x) * min(1, dt * 8)
        cameraYawNode.position.y += (target.y - cameraYawNode.position.y) * min(1, dt * 8)
        cameraYawNode.position.z += (target.z - cameraYawNode.position.z) * min(1, dt * 8)
    }

    private func configureScene() {
        scene.background.contents = UIColor(red: 0.43, green: 0.72, blue: 0.90, alpha: 1)
        scene.fogColor = UIColor(red: 0.70, green: 0.84, blue: 0.90, alpha: 1)
        scene.fogStartDistance = 52
        scene.fogEndDistance = 95

        addLighting()
        addTerrain()
        addTown()
        addPlayer()
        addWildCreatures()
        addCamera()
    }

    private func addLighting() {
        let sun = SCNNode()
        let light = SCNLight()
        light.type = .directional
        light.intensity = 1250
        light.temperature = 5600
        light.castsShadow = true
        light.shadowRadius = 5
        light.shadowSampleCount = 8
        sun.light = light
        sun.eulerAngles = SCNVector3(-0.95, -0.65, 0)
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 430
        ambientLight.color = UIColor(red: 0.58, green: 0.68, blue: 0.86, alpha: 1)
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)
    }

    private func addTerrain() {
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial = material(UIColor(red: 0.18, green: 0.46, blue: 0.24, alpha: 1), roughness: 0.95)
        let ground = SCNNode(geometry: floor)
        ground.position.y = 0
        scene.rootNode.addChildNode(ground)

        for i in 0..<18 {
            let hill = SCNSphere(radius: CGFloat(5 + (i % 4) * 2))
            hill.segmentCount = 24
            hill.firstMaterial = material(
                UIColor(red: 0.14 + CGFloat(i % 3) * 0.015, green: 0.38, blue: 0.19, alpha: 1),
                roughness: 1
            )
            let node = SCNNode(geometry: hill)
            let angle = Float(i) / 18 * .pi * 2
            let radius: Float = 43 + Float((i * 7) % 13)
            node.position = SCNVector3(cos(angle) * radius, -4.8, sin(angle) * radius)
            node.scale.y = 0.65
            scene.rootNode.addChildNode(node)
        }

        let river = SCNPlane(width: 10, height: 105)
        river.firstMaterial = material(UIColor(red: 0.10, green: 0.58, blue: 0.72, alpha: 0.82), roughness: 0.18)
        river.firstMaterial?.isDoubleSided = true
        let riverNode = SCNNode(geometry: river)
        riverNode.eulerAngles.x = -.pi / 2
        riverNode.eulerAngles.z = 0.09
        riverNode.position = SCNVector3(-27, 0.025, -3)
        scene.rootNode.addChildNode(riverNode)

        for i in 0..<34 {
            let x = Float((i * 17) % 101) - 50
            let z = Float((i * 29) % 103) - 51
            if abs(x + 27) > 8 { addTree(at: SCNVector3(x, 0, z), scale: 0.75 + Float(i % 4) * 0.12) }
        }

        for i in 0..<26 {
            let rock = SCNSphere(radius: CGFloat(0.35 + Double(i % 3) * 0.12))
            rock.segmentCount = 8
            rock.firstMaterial = material(UIColor(red: 0.36, green: 0.39, blue: 0.38, alpha: 1), roughness: 1)
            let node = SCNNode(geometry: rock)
            node.position = SCNVector3(Float((i * 31) % 97) - 48, 0.25, Float((i * 43) % 91) - 45)
            node.scale = SCNVector3(1.2, 0.65, 0.9)
            scene.rootNode.addChildNode(node)
        }
    }

    private func addTree(at position: SCNVector3, scale: Float) {
        let root = SCNNode()
        root.position = position
        root.scale = SCNVector3(scale, scale, scale)

        let trunk = SCNCylinder(radius: 0.22, height: 2.4)
        trunk.firstMaterial = material(UIColor(red: 0.28, green: 0.16, blue: 0.09, alpha: 1), roughness: 1)
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position.y = 1.2
        root.addChildNode(trunkNode)

        let crown = SCNCone(topRadius: 0.25, bottomRadius: 1.35, height: 3.0)
        crown.radialSegmentCount = 10
        crown.firstMaterial = material(UIColor(red: 0.12, green: 0.42, blue: 0.20, alpha: 1), roughness: 0.95)
        let crownNode = SCNNode(geometry: crown)
        crownNode.position.y = 3.0
        root.addChildNode(crownNode)

        scene.rootNode.addChildNode(root)
    }

    private func addTown() {
        addBuilding(at: SCNVector3(8, 0, -11), width: 6.5, depth: 5, height: 3.6, wall: UIColor(red: 0.73, green: 0.62, blue: 0.43, alpha: 1), roof: UIColor(red: 0.30, green: 0.22, blue: 0.38, alpha: 1))
        addBuilding(at: SCNVector3(15, 0, -5), width: 5.2, depth: 4.2, height: 3.0, wall: UIColor(red: 0.70, green: 0.52, blue: 0.35, alpha: 1), roof: UIColor(red: 0.18, green: 0.32, blue: 0.42, alpha: 1))
        addBuilding(at: SCNVector3(10, 0, 4), width: 7.0, depth: 4.6, height: 3.3, wall: UIColor(red: 0.77, green: 0.68, blue: 0.49, alpha: 1), roof: UIColor(red: 0.35, green: 0.18, blue: 0.25, alpha: 1))

        let shrineBase = SCNCylinder(radius: 2.0, height: 0.35)
        shrineBase.firstMaterial = material(UIColor(red: 0.48, green: 0.51, blue: 0.54, alpha: 1), roughness: 0.72)
        let baseNode = SCNNode(geometry: shrineBase)
        baseNode.position = SCNVector3(1, 0.18, -7)
        scene.rootNode.addChildNode(baseNode)

        let crystal = SCNOctahedron(radius: 0.9)
        crystal.firstMaterial = material(UIColor(red: 0.20, green: 0.90, blue: 0.96, alpha: 0.78), roughness: 0.12, metalness: 0.1)
        let crystalNode = SCNNode(geometry: crystal)
        crystalNode.position = SCNVector3(1, 1.65, -7)
        crystalNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 5)))
        scene.rootNode.addChildNode(crystalNode)

        let arch = SCNTorus(ringRadius: 2.1, pipeRadius: 0.18)
        arch.firstMaterial = material(UIColor(red: 0.33, green: 0.26, blue: 0.49, alpha: 1), roughness: 0.45, metalness: 0.25)
        let archNode = SCNNode(geometry: arch)
        archNode.position = SCNVector3(1, 2.1, -7)
        scene.rootNode.addChildNode(archNode)
    }

    private func addBuilding(at position: SCNVector3, width: CGFloat, depth: CGFloat, height: CGFloat, wall: UIColor, roof: UIColor) {
        let root = SCNNode()
        root.position = position

        let body = SCNBox(width: width, height: height, length: depth, chamferRadius: 0.22)
        body.firstMaterial = material(wall, roughness: 0.92)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position.y = Float(height / 2)
        root.addChildNode(bodyNode)

        let roofGeo = SCNPyramid(width: width + 1.0, height: 2.0, length: depth + 1.0)
        roofGeo.firstMaterial = material(roof, roughness: 0.82)
        let roofNode = SCNNode(geometry: roofGeo)
        roofNode.position.y = Float(height + 1.0)
        root.addChildNode(roofNode)

        let door = SCNBox(width: 1.0, height: 1.8, length: 0.1, chamferRadius: 0.08)
        door.firstMaterial = material(UIColor(red: 0.20, green: 0.12, blue: 0.08, alpha: 1), roughness: 1)
        let doorNode = SCNNode(geometry: door)
        doorNode.position = SCNVector3(0, 0.9, Float(depth / 2 + 0.06))
        root.addChildNode(doorNode)

        scene.rootNode.addChildNode(root)
    }

    private func addPlayer() {
        player.name = "Aether Tamer"
        player.position = SCNVector3(0, 0, 5)

        let hips = SCNCapsule(capRadius: 0.35, height: 1.35)
        hips.firstMaterial = material(UIColor(red: 0.13, green: 0.28, blue: 0.52, alpha: 1), roughness: 0.55)
        let body = SCNNode(geometry: hips)
        body.position.y = 1.18
        player.addChildNode(body)

        let chest = SCNCapsule(capRadius: 0.42, height: 1.25)
        chest.firstMaterial = material(UIColor(red: 0.12, green: 0.55, blue: 0.62, alpha: 1), roughness: 0.45)
        let chestNode = SCNNode(geometry: chest)
        chestNode.position.y = 2.05
        player.addChildNode(chestNode)

        let head = SCNSphere(radius: 0.42)
        head.segmentCount = 24
        head.firstMaterial = material(UIColor(red: 0.92, green: 0.71, blue: 0.57, alpha: 1), roughness: 0.72)
        let headNode = SCNNode(geometry: head)
        headNode.position.y = 2.95
        player.addChildNode(headNode)

        let hair = SCNSphere(radius: 0.44)
        hair.segmentCount = 18
        hair.firstMaterial = material(UIColor(red: 0.10, green: 0.08, blue: 0.15, alpha: 1), roughness: 0.9)
        let hairNode = SCNNode(geometry: hair)
        hairNode.scale = SCNVector3(1, 0.62, 1)
        hairNode.position = SCNVector3(0, 3.16, -0.02)
        player.addChildNode(hairNode)

        let scarf = SCNTorus(ringRadius: 0.45, pipeRadius: 0.09)
        scarf.firstMaterial = material(UIColor(red: 0.50, green: 0.30, blue: 0.92, alpha: 1), roughness: 0.45)
        let scarfNode = SCNNode(geometry: scarf)
        scarfNode.position.y = 2.55
        scarfNode.eulerAngles.x = .pi / 2
        player.addChildNode(scarfNode)

        let sword = SCNBox(width: 0.10, height: 1.55, length: 0.14, chamferRadius: 0.04)
        sword.firstMaterial = material(UIColor(red: 0.72, green: 0.91, blue: 0.96, alpha: 1), roughness: 0.14, metalness: 0.75)
        let swordNode = SCNNode(geometry: sword)
        swordNode.name = "sword"
        swordNode.position = SCNVector3(0.62, 1.55, 0.18)
        swordNode.eulerAngles.z = -0.42
        player.addChildNode(swordNode)

        let aura = SCNTorus(ringRadius: 0.75, pipeRadius: 0.025)
        aura.firstMaterial = material(UIColor(red: 0.25, green: 0.94, blue: 1.0, alpha: 0.65), roughness: 0.15)
        let auraNode = SCNNode(geometry: aura)
        auraNode.position.y = 0.05
        auraNode.eulerAngles.x = .pi / 2
        auraNode.runAction(.repeatForever(.sequence([
            .fadeOpacity(to: 0.25, duration: 1.0),
            .fadeOpacity(to: 0.9, duration: 1.0)
        ])))
        player.addChildNode(auraNode)

        scene.rootNode.addChildNode(player)
    }

    private func addWildCreatures() {
        let placements: [(Int, Float, Float, Int)] = [
            (0, -7, -14, 4),
            (2, 23, 12, 6),
            (3, -15, 18, 5),
            (4, 29, -18, 8),
            (5, 7, 27, 7),
            (1, -9, 32, 5),
            (0, 35, 28, 9)
        ]

        for (index, x, z, level) in placements {
            let creature = Creature(species: CreatureSpecies.catalog[index], level: level)
            let node = makeCreatureNode(creature, variant: index)
            node.position = SCNVector3(x, 0.65, z)
            node.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.14, z: 0, duration: 0.8),
                .moveBy(x: 0, y: -0.14, z: 0, duration: 0.8)
            ])))
            scene.rootNode.addChildNode(node)
            monsterNodes.append((node, creature))
        }
    }

    private func makeCreatureNode(_ creature: Creature, variant: Int) -> SCNNode {
        let root = SCNNode()
        root.name = creature.species.name

        let baseColor = uiColor(for: creature.species.element)
        let bodyGeo = SCNSphere(radius: 0.75)
        bodyGeo.segmentCount = 20
        bodyGeo.firstMaterial = material(baseColor, roughness: 0.52)
        let body = SCNNode(geometry: bodyGeo)
        body.scale = SCNVector3(1.0, 0.82, 1.12)
        body.position.y = 0.75
        root.addChildNode(body)

        let headGeo = SCNSphere(radius: 0.52)
        headGeo.segmentCount = 20
        headGeo.firstMaterial = material(baseColor.withAlphaComponent(0.96), roughness: 0.48)
        let head = SCNNode(geometry: headGeo)
        head.position = SCNVector3(0, 1.5, -0.36)
        root.addChildNode(head)

        for side: Float in [-1, 1] {
            let eye = SCNSphere(radius: 0.085)
            eye.firstMaterial = material(.white, roughness: 0.3)
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(side * 0.18, 1.58, -0.82)
            root.addChildNode(eyeNode)

            let pupil = SCNSphere(radius: 0.045)
            pupil.firstMaterial = material(UIColor(red: 0.05, green: 0.08, blue: 0.12, alpha: 1), roughness: 0.2)
            let pupilNode = SCNNode(geometry: pupil)
            pupilNode.position = SCNVector3(side * 0.18, 1.58, -0.90)
            root.addChildNode(pupilNode)
        }

        if variant % 2 == 0 {
            for side: Float in [-1, 1] {
                let horn = SCNCone(topRadius: 0, bottomRadius: 0.15, height: 0.65)
                horn.radialSegmentCount = 8
                horn.firstMaterial = material(baseColor.adjustedBrightness(0.68), roughness: 0.7)
                let hornNode = SCNNode(geometry: horn)
                hornNode.position = SCNVector3(side * 0.28, 2.0, -0.25)
                hornNode.eulerAngles.z = side * 0.22
                root.addChildNode(hornNode)
            }
        } else {
            for side: Float in [-1, 1] {
                let ear = SCNPyramid(width: 0.42, height: 0.72, length: 0.26)
                ear.firstMaterial = material(baseColor.adjustedBrightness(0.80), roughness: 0.8)
                let earNode = SCNNode(geometry: ear)
                earNode.position = SCNVector3(side * 0.38, 1.98, -0.28)
                root.addChildNode(earNode)
            }
        }

        let ring = SCNTorus(ringRadius: 0.82, pipeRadius: 0.035)
        ring.firstMaterial = material(baseColor.adjustedBrightness(1.25), roughness: 0.15, metalness: 0.1)
        let ringNode = SCNNode(geometry: ring)
        ringNode.position.y = 0.18
        ringNode.eulerAngles.x = .pi / 2
        ringNode.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: .pi * 2, duration: 4.8)))
        root.addChildNode(ringNode)

        let labelGeo = SCNText(string: "\(creature.species.name)  Lv.\(creature.level)", extrusionDepth: 0.01)
        labelGeo.font = UIFont.systemFont(ofSize: 0.22, weight: .bold)
        labelGeo.flatness = 0.2
        labelGeo.firstMaterial = material(.white, roughness: 0.5)
        let label = SCNNode(geometry: labelGeo)
        let bounds = label.boundingBox
        label.pivot = SCNMatrix4MakeTranslation((bounds.max.x - bounds.min.x) / 2, 0, 0)
        label.position = SCNVector3(0, 2.5, 0)
        label.constraints = [SCNBillboardConstraint()]
        root.addChildNode(label)

        return root
    }

    private func addCamera() {
        let cameraComponent = SCNCamera()
        cameraComponent.fieldOfView = 64
        cameraComponent.zNear = 0.05
        cameraComponent.zFar = 180
        cameraComponent.wantsHDR = true
        camera.camera = cameraComponent
        camera.position = SCNVector3(0, 0.8, cameraDistance)

        cameraPitchNode.addChildNode(camera)
        cameraPitchNode.eulerAngles.x = cameraPitch
        cameraYawNode.addChildNode(cameraPitchNode)
        cameraYawNode.position = SCNVector3(player.position.x, player.position.y + 1.3, player.position.z)
        scene.rootNode.addChildNode(cameraYawNode)
    }

    private func animateAttack() {
        guard let sword = player.childNode(withName: "sword", recursively: true) else { return }
        sword.removeAllActions()
        let original = sword.eulerAngles.z
        let swingOut = SCNAction.rotateTo(x: 0.35, y: 0, z: 1.15, duration: 0.11, usesShortestUnitArc: true)
        swingOut.timingMode = .easeOut
        let recover = SCNAction.rotateTo(x: 0, y: 0, z: CGFloat(original), duration: 0.20, usesShortestUnitArc: true)
        recover.timingMode = .easeInEaseOut
        sword.runAction(.sequence([swingOut, recover]))
    }

    private func nearestCreature(maxDistance: Float) -> Creature? {
        var best: (Creature, Float)?
        let p = player.simdPosition
        for pair in monsterNodes {
            let m = pair.node.simdPosition
            let distance = simd_distance(SIMD2<Float>(p.x, p.z), SIMD2<Float>(m.x, m.z))
            if distance <= maxDistance, best == nil || distance < best!.1 {
                best = (pair.creature, distance)
            }
        }
        return best?.0
    }

    private func material(_ color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        m.lightingModel = .physicallyBased
        return m
    }

    private func uiColor(for element: CreatureSpecies.Element) -> UIColor {
        switch element {
        case .ember: return UIColor(red: 0.93, green: 0.34, blue: 0.16, alpha: 1)
        case .tide: return UIColor(red: 0.14, green: 0.68, blue: 0.91, alpha: 1)
        case .grove: return UIColor(red: 0.26, green: 0.70, blue: 0.30, alpha: 1)
        case .storm: return UIColor(red: 0.96, green: 0.78, blue: 0.17, alpha: 1)
        case .stone: return UIColor(red: 0.54, green: 0.42, blue: 0.32, alpha: 1)
        case .spirit: return UIColor(red: 0.58, green: 0.35, blue: 0.92, alpha: 1)
        }
    }

    private func lerpAngle(_ from: Float, _ to: Float, factor: Float) -> Float {
        var delta = fmodf(to - from + .pi, .pi * 2) - .pi
        if delta < -.pi { delta += .pi * 2 }
        return from + delta * factor
    }
}

private extension UIColor {
    func adjustedBrightness(_ factor: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: min(1, brightness * factor), alpha: alpha)
    }
}
