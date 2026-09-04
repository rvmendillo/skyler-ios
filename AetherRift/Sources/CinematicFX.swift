import SpriteKit
import SwiftUI
import UIKit

// Original icy-fantasy art direction. This intentionally avoids reproducing any
// copyrighted film/game character, costume, map, or asset.
enum CinematicFX {
    private static let friendlyNames: [String: HeroClass] = [
        "Bastion": .tank, "Kael": .fighter, "Nyx": .assassin,
        "Lyra": .mage, "Orion": .marksman, "Mira": .support
    ]

    private static let enemyNames: [String: HeroClass] = [
        "Grom": .tank, "Raze": .fighter, "Vex": .assassin,
        "Sable": .mage, "Kestrel": .marksman, "Eira": .support
    ]

    static func install(in scene: GameScene, selectedHero: HeroClass) {
        guard let camera = scene.camera else { return }

        if camera.childNode(withName: "cinematic-screen-fx") == nil {
            camera.addChild(makeScreenFX(size: scene.size))
        }

        guard let world = scene.children.first(where: { $0 !== camera }) else { return }
        if world.childNode(withName: "cinematic-world-fx") == nil {
            world.addChild(makeWorldFX())
        }

        decorateCharacters(in: world)
        attachPetIfNeeded(to: world, heroClass: selectedHero)
    }

    private static func makeScreenFX(size: CGSize) -> SKNode {
        let root = SKNode()
        root.name = "cinematic-screen-fx"
        root.zPosition = 82

        let halfW = max(size.width / 2, 466)
        let halfH = max(size.height / 2, 215)

        let auroraTexture = gradientTexture(
            size: CGSize(width: halfW * 2.3, height: 130),
            stops: [
                (UIColor.systemTeal.withAlphaComponent(0.00), 0.00),
                (UIColor.systemTeal.withAlphaComponent(0.16), 0.28),
                (UIColor.systemIndigo.withAlphaComponent(0.12), 0.62),
                (UIColor.clear, 1.00)
            ],
            vertical: false
        )
        let aurora = SKSpriteNode(texture: auroraTexture)
        aurora.position = CGPoint(x: 0, y: halfH - 58)
        aurora.zPosition = 1
        aurora.blendMode = .add
        aurora.alpha = 0.72
        aurora.run(.repeatForever(.sequence([
            .moveBy(x: 35, y: 3, duration: 4.5),
            .moveBy(x: -70, y: -6, duration: 9.0),
            .moveBy(x: 35, y: 3, duration: 4.5)
        ])))
        root.addChild(aurora)

        let fogTexture = radialFogTexture(size: CGSize(width: 460, height: 190))
        for index in 0..<3 {
            let fog = SKSpriteNode(texture: fogTexture)
            fog.alpha = 0.13 + CGFloat(index) * 0.025
            fog.position = CGPoint(
                x: -halfW + CGFloat(index) * halfW * 0.82,
                y: -halfH + 60 + CGFloat(index % 2) * 30
            )
            fog.zPosition = 2
            fog.blendMode = .alpha
            fog.setScale(1.15 + CGFloat(index) * 0.18)
            fog.run(.repeatForever(.sequence([
                .moveBy(x: 140, y: 12, duration: 10 + Double(index) * 2),
                .moveBy(x: -140, y: -12, duration: 10 + Double(index) * 2)
            ])))
            root.addChild(fog)
        }

        let vignette = SKSpriteNode(texture: vignetteTexture(size: CGSize(width: halfW * 2.05, height: halfH * 2.05)))
        vignette.position = .zero
        vignette.zPosition = 8
        vignette.alpha = 0.32
        root.addChild(vignette)

        let snow = SKEmitterNode()
        snow.particleTexture = particleTexture()
        snow.particleBirthRate = 32
        snow.particleLifetime = 6.4
        snow.particleLifetimeRange = 2.2
        snow.particlePosition = CGPoint(x: 0, y: halfH + 36)
        snow.particlePositionRange = CGVector(dx: halfW * 2.15, dy: 20)
        snow.emissionAngle = -.pi / 2
        snow.emissionAngleRange = 0.24
        snow.particleSpeed = 58
        snow.particleSpeedRange = 34
        snow.xAcceleration = -7
        snow.yAcceleration = -8
        snow.particleAlpha = 0.72
        snow.particleAlphaRange = 0.24
        snow.particleAlphaSpeed = -0.045
        snow.particleScale = 0.13
        snow.particleScaleRange = 0.11
        snow.particleRotationRange = .pi
        snow.particleRotationSpeed = 0.7
        snow.particleColor = .white
        snow.zPosition = 6
        root.addChild(snow)

        return root
    }

    private static func makeWorldFX() -> SKNode {
        let root = SKNode()
        root.name = "cinematic-world-fx"
        root.zPosition = -17

        let frostPatches: [CGPoint] = [
            CGPoint(x: 520, y: 760), CGPoint(x: 720, y: 1180), CGPoint(x: 980, y: 520),
            CGPoint(x: 1120, y: 1320), CGPoint(x: 1360, y: 540), CGPoint(x: 1640, y: 1280),
            CGPoint(x: 1900, y: 520), CGPoint(x: 2070, y: 1280), CGPoint(x: 2350, y: 760),
            CGPoint(x: 2460, y: 1100)
        ]
        for (index, point) in frostPatches.enumerated() {
            let patch = SKShapeNode(ellipseOf: CGSize(width: 190 + CGFloat(index % 3) * 28, height: 88 + CGFloat(index % 2) * 18))
            patch.position = point
            patch.fillColor = SKColor(red: 0.58, green: 0.84, blue: 0.92, alpha: 0.11)
            patch.strokeColor = SKColor(red: 0.76, green: 0.94, blue: 1.0, alpha: 0.18)
            patch.lineWidth = 2
            patch.zPosition = 0
            root.addChild(patch)
        }

        let crystalPoints: [CGPoint] = [
            CGPoint(x: 620, y: 560), CGPoint(x: 830, y: 1250), CGPoint(x: 1030, y: 750),
            CGPoint(x: 1220, y: 1090), CGPoint(x: 1390, y: 480), CGPoint(x: 1620, y: 1325),
            CGPoint(x: 1800, y: 700), CGPoint(x: 2020, y: 1180), CGPoint(x: 2210, y: 520),
            CGPoint(x: 2390, y: 1270)
        ]
        for (index, point) in crystalPoints.enumerated() {
            root.addChild(crystalCluster(at: point, scale: 0.82 + CGFloat(index % 3) * 0.12))
        }

        return root
    }

    private static func decorateCharacters(in world: SKNode) {
        for node in world.children where node.zPosition >= 14 {
            guard node.childNode(withName: "cinematic-character-detail") == nil else { continue }
            guard let label = node.children.compactMap({ $0 as? SKLabelNode }).first(where: { child in
                guard let text = child.text else { return false }
                return friendlyNames[text] != nil || enemyNames[text] != nil
            }), let name = label.text else { continue }

            let heroClass = friendlyNames[name] ?? enemyNames[name] ?? .fighter
            let enemy = enemyNames[name] != nil
            node.addChild(characterDetail(heroClass: heroClass, enemy: enemy))
        }
    }

    private static func attachPetIfNeeded(to world: SKNode, heroClass: HeroClass) {
        guard let player = world.children.first(where: { $0.zPosition >= 17.5 && $0.zPosition <= 18.5 }) else { return }
        guard player.childNode(withName: "cinematic-pet") == nil else { return }

        let pet = petNode(for: heroClass)
        pet.name = "cinematic-pet"
        pet.position = CGPoint(x: -46, y: -24)
        pet.zPosition = 25
        pet.setScale(0.82)
        pet.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 4, duration: 0.72),
            .moveBy(x: 0, y: -4, duration: 0.72)
        ])))
        player.addChild(pet)
    }

    private static func characterDetail(heroClass: HeroClass, enemy: Bool) -> SKNode {
        let root = SKNode()
        root.name = "cinematic-character-detail"
        root.zPosition = 8

        let tint = color(for: heroClass)

        let aura = SKShapeNode(ellipseOf: CGSize(width: 72, height: 28))
        aura.position = CGPoint(x: 0, y: -24)
        aura.fillColor = tint.withAlphaComponent(enemy ? 0.09 : 0.15)
        aura.strokeColor = tint.withAlphaComponent(enemy ? 0.35 : 0.62)
        aura.lineWidth = 2
        aura.glowWidth = enemy ? 2 : 5
        aura.zPosition = -2
        root.addChild(aura)

        let backCape = SKShapeNode(path: capePath())
        backCape.position = CGPoint(x: 0, y: -2)
        backCape.fillColor = tint.withAlphaComponent(0.54)
        backCape.strokeColor = SKColor.white.withAlphaComponent(0.18)
        backCape.lineWidth = 1
        backCape.zPosition = -1
        root.addChild(backCape)

        for x in [-17.0, 17.0] {
            let shoulder = SKShapeNode(ellipseOf: CGSize(width: 19, height: 12))
            shoulder.position = CGPoint(x: x, y: 12)
            shoulder.fillColor = tint.withAlphaComponent(0.92)
            shoulder.strokeColor = .white.withAlphaComponent(0.75)
            shoulder.lineWidth = 1.4
            root.addChild(shoulder)
        }

        let chestGem = SKShapeNode(path: diamondPath(width: 11, height: 15))
        chestGem.position = CGPoint(x: 0, y: 7)
        chestGem.fillColor = .white.withAlphaComponent(0.88)
        chestGem.strokeColor = tint
        chestGem.lineWidth = 1
        chestGem.glowWidth = 4
        root.addChild(chestGem)

        let hair = SKShapeNode(path: hairPath(for: heroClass))
        hair.position = CGPoint(x: 0, y: 29)
        hair.fillColor = hairColor(for: heroClass, enemy: enemy)
        hair.strokeColor = .white.withAlphaComponent(0.12)
        hair.lineWidth = 1
        root.addChild(hair)

        let weapon = weaponNode(for: heroClass, color: tint)
        weapon.position = CGPoint(x: heroClass == .tank ? 24 : 25, y: 5)
        weapon.zRotation = heroClass == .marksman ? -0.12 : -0.34
        root.addChild(weapon)

        let sparkle = SKEmitterNode()
        sparkle.particleTexture = particleTexture()
        sparkle.particleBirthRate = enemy ? 1.2 : 2.8
        sparkle.particleLifetime = 0.8
        sparkle.particlePositionRange = CGVector(dx: 44, dy: 58)
        sparkle.particleSpeed = 11
        sparkle.emissionAngleRange = .pi * 2
        sparkle.particleScale = 0.055
        sparkle.particleScaleRange = 0.025
        sparkle.particleAlpha = 0.64
        sparkle.particleAlphaSpeed = -0.7
        sparkle.particleColor = tint
        sparkle.zPosition = 9
        root.addChild(sparkle)

        return root
    }

    private static func petNode(for heroClass: HeroClass) -> SKNode {
        let root = SKNode()
        let tint = color(for: heroClass)

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 34, height: 11))
        shadow.position = CGPoint(x: 0, y: -13)
        shadow.fillColor = .black.withAlphaComponent(0.28)
        shadow.strokeColor = .clear
        root.addChild(shadow)

        let tail = SKShapeNode(path: tailPath())
        tail.position = CGPoint(x: -14, y: 0)
        tail.fillColor = tint.withAlphaComponent(0.86)
        tail.strokeColor = .white.withAlphaComponent(0.45)
        tail.lineWidth = 1
        tail.zPosition = -1
        tail.run(.repeatForever(.sequence([
            .rotate(toAngle: -0.22, duration: 0.35, shortestUnitArc: true),
            .rotate(toAngle: 0.24, duration: 0.35, shortestUnitArc: true)
        ])))
        root.addChild(tail)

        let body = SKShapeNode(ellipseOf: CGSize(width: 32, height: 25))
        body.fillColor = tint.withAlphaComponent(0.90)
        body.strokeColor = .white.withAlphaComponent(0.75)
        body.lineWidth = 1.5
        root.addChild(body)

        let head = SKShapeNode(circleOfRadius: 12)
        head.position = CGPoint(x: 12, y: 10)
        head.fillColor = SKColor(red: 0.90, green: 0.96, blue: 1.0, alpha: 1)
        head.strokeColor = tint
        head.lineWidth = 1.5
        root.addChild(head)

        let earLeft = SKShapeNode(path: earPath())
        earLeft.position = CGPoint(x: 7, y: 20)
        earLeft.fillColor = tint
        earLeft.strokeColor = .white.withAlphaComponent(0.5)
        earLeft.lineWidth = 1
        root.addChild(earLeft)

        let earRight = SKShapeNode(path: earPath())
        earRight.xScale = -1
        earRight.position = CGPoint(x: 17, y: 20)
        earRight.fillColor = tint
        earRight.strokeColor = .white.withAlphaComponent(0.5)
        earRight.lineWidth = 1
        root.addChild(earRight)

        for x in [9.0, 16.0] {
            let eye = SKShapeNode(circleOfRadius: 2.2)
            eye.position = CGPoint(x: x, y: 12)
            eye.fillColor = SKColor(red: 0.08, green: 0.12, blue: 0.20, alpha: 1)
            eye.strokeColor = .clear
            root.addChild(eye)
        }

        let gem = SKShapeNode(path: diamondPath(width: 7, height: 9))
        gem.position = CGPoint(x: 0, y: 2)
        gem.fillColor = .white
        gem.strokeColor = tint
        gem.lineWidth = 1
        gem.glowWidth = 3
        root.addChild(gem)

        return root
    }

    private static func weaponNode(for heroClass: HeroClass, color: SKColor) -> SKNode {
        let node = SKNode()
        switch heroClass {
        case .tank:
            let shield = SKShapeNode(path: shieldPath())
            shield.fillColor = color.withAlphaComponent(0.90)
            shield.strokeColor = .white
            shield.lineWidth = 2
            node.addChild(shield)
        case .fighter:
            let blade = SKShapeNode(path: bladePath(length: 46, width: 8))
            blade.fillColor = .white.withAlphaComponent(0.92)
            blade.strokeColor = color
            blade.lineWidth = 2
            blade.glowWidth = 3
            node.addChild(blade)
        case .assassin:
            for offset in [-5.0, 5.0] {
                let blade = SKShapeNode(path: bladePath(length: 34, width: 5))
                blade.position = CGPoint(x: offset, y: 0)
                blade.fillColor = color
                blade.strokeColor = .white
                blade.lineWidth = 1
                blade.glowWidth = 2
                node.addChild(blade)
            }
        case .mage, .support:
            let staff = SKShapeNode(rectOf: CGSize(width: 5, height: 44), cornerRadius: 2)
            staff.position = CGPoint(x: 0, y: -2)
            staff.fillColor = SKColor(red: 0.45, green: 0.32, blue: 0.22, alpha: 1)
            staff.strokeColor = .white.withAlphaComponent(0.4)
            node.addChild(staff)
            let orb = SKShapeNode(circleOfRadius: heroClass == .mage ? 8 : 7)
            orb.position = CGPoint(x: 0, y: 23)
            orb.fillColor = color
            orb.strokeColor = .white
            orb.glowWidth = 6
            node.addChild(orb)
        case .marksman:
            let bow = SKShapeNode(path: bowPath())
            bow.strokeColor = color
            bow.lineWidth = 4
            bow.glowWidth = 2
            bow.fillColor = .clear
            node.addChild(bow)
        }
        return node
    }

    private static func crystalCluster(at position: CGPoint, scale: CGFloat) -> SKNode {
        let root = SKNode()
        root.position = position
        root.setScale(scale)
        for index in 0..<4 {
            let crystal = SKShapeNode(path: crystalPath(height: 34 + CGFloat(index) * 8, width: 13 + CGFloat(index % 2) * 4))
            crystal.position = CGPoint(x: CGFloat(index - 2) * 10, y: CGFloat(index % 2) * 3)
            crystal.zRotation = CGFloat(index - 1) * 0.09
            crystal.fillColor = SKColor(red: 0.55, green: 0.88, blue: 1.0, alpha: 0.26)
            crystal.strokeColor = SKColor(red: 0.78, green: 0.96, blue: 1.0, alpha: 0.64)
            crystal.lineWidth = 1.4
            crystal.glowWidth = 2
            root.addChild(crystal)
        }
        return root
    }

    static func color(for heroClass: HeroClass) -> SKColor {
        switch heroClass {
        case .tank: return SKColor(red: 0.28, green: 0.80, blue: 0.96, alpha: 1)
        case .fighter: return SKColor(red: 0.98, green: 0.55, blue: 0.28, alpha: 1)
        case .assassin: return SKColor(red: 0.64, green: 0.40, blue: 0.95, alpha: 1)
        case .mage: return SKColor(red: 0.40, green: 0.54, blue: 1.0, alpha: 1)
        case .marksman: return SKColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1)
        case .support: return SKColor(red: 0.30, green: 0.90, blue: 0.66, alpha: 1)
        }
    }

    static func swiftUIColor(for heroClass: HeroClass) -> Color {
        switch heroClass {
        case .tank: return Color(red: 0.28, green: 0.80, blue: 0.96)
        case .fighter: return Color(red: 0.98, green: 0.55, blue: 0.28)
        case .assassin: return Color(red: 0.64, green: 0.40, blue: 0.95)
        case .mage: return Color(red: 0.40, green: 0.54, blue: 1.0)
        case .marksman: return Color(red: 0.95, green: 0.80, blue: 0.30)
        case .support: return Color(red: 0.30, green: 0.90, blue: 0.66)
        }
    }

    private static func hairColor(for heroClass: HeroClass, enemy: Bool) -> SKColor {
        if enemy { return SKColor(red: 0.18, green: 0.10, blue: 0.16, alpha: 1) }
        switch heroClass {
        case .tank: return SKColor(red: 0.78, green: 0.91, blue: 0.98, alpha: 1)
        case .fighter: return SKColor(red: 0.31, green: 0.17, blue: 0.10, alpha: 1)
        case .assassin: return SKColor(red: 0.16, green: 0.10, blue: 0.25, alpha: 1)
        case .mage: return SKColor(red: 0.83, green: 0.88, blue: 1.0, alpha: 1)
        case .marksman: return SKColor(red: 0.43, green: 0.25, blue: 0.10, alpha: 1)
        case .support: return SKColor(red: 0.82, green: 0.95, blue: 0.92, alpha: 1)
        }
    }

    private static func particleTexture() -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18))
        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawRadialGradient(gradient, startCenter: CGPoint(x: 9, y: 9), startRadius: 0, endCenter: CGPoint(x: 9, y: 9), endRadius: 9, options: [])
        }
        return SKTexture(image: image)
    }

    private static func radialFogTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors = [UIColor.white.withAlphaComponent(0.42).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: max(size.width, size.height) / 2, options: [])
        }
        return SKTexture(image: image)
    }

    private static func vignetteTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.78).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.50, 1.0])!
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: min(size.width, size.height) * 0.35, endCenter: center, endRadius: max(size.width, size.height) * 0.62, options: [])
        }
        return SKTexture(image: image)
    }

    private static func gradientTexture(size: CGSize, stops: [(UIColor, CGFloat)], vertical: Bool) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let colors = stops.map { $0.0.cgColor } as CFArray
            let locations = stops.map { $0.1 }
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
            let start = vertical ? CGPoint(x: size.width / 2, y: 0) : CGPoint(x: 0, y: size.height / 2)
            let end = vertical ? CGPoint(x: size.width / 2, y: size.height) : CGPoint(x: size.width, y: size.height / 2)
            context.cgContext.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
        return SKTexture(image: image)
    }

    private static func diamondPath(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: height / 2))
        path.addLine(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -height / 2))
        path.addLine(to: CGPoint(x: -width / 2, y: 0))
        path.closeSubpath()
        return path
    }

    private static func capePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -20, y: 18))
        path.addCurve(to: CGPoint(x: -27, y: -30), control1: CGPoint(x: -28, y: 0), control2: CGPoint(x: -30, y: -20))
        path.addLine(to: CGPoint(x: 0, y: -22))
        path.addLine(to: CGPoint(x: 27, y: -30))
        path.addCurve(to: CGPoint(x: 20, y: 18), control1: CGPoint(x: 30, y: -20), control2: CGPoint(x: 28, y: 0))
        path.closeSubpath()
        return path
    }

    private static func hairPath(for heroClass: HeroClass) -> CGPath {
        let path = CGMutablePath()
        let spread: CGFloat = heroClass == .mage || heroClass == .support ? 21 : 17
        path.move(to: CGPoint(x: -spread, y: 3))
        path.addCurve(to: CGPoint(x: 0, y: 13), control1: CGPoint(x: -13, y: 15), control2: CGPoint(x: -5, y: 17))
        path.addCurve(to: CGPoint(x: spread, y: 3), control1: CGPoint(x: 6, y: 17), control2: CGPoint(x: 14, y: 14))
        path.addLine(to: CGPoint(x: 12, y: -8))
        path.addLine(to: CGPoint(x: 5, y: -2))
        path.addLine(to: CGPoint(x: 0, y: -10))
        path.addLine(to: CGPoint(x: -6, y: -2))
        path.addLine(to: CGPoint(x: -13, y: -8))
        path.closeSubpath()
        return path
    }

    private static func bladePath(length: CGFloat, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width / 2, y: -length / 2))
        path.addLine(to: CGPoint(x: width / 2, y: -length / 2))
        path.addLine(to: CGPoint(x: width / 3, y: length * 0.34))
        path.addLine(to: CGPoint(x: 0, y: length / 2))
        path.addLine(to: CGPoint(x: -width / 3, y: length * 0.34))
        path.closeSubpath()
        return path
    }

    private static func shieldPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -15, y: 18))
        path.addLine(to: CGPoint(x: 15, y: 18))
        path.addLine(to: CGPoint(x: 18, y: -2))
        path.addCurve(to: CGPoint(x: 0, y: -24), control1: CGPoint(x: 14, y: -14), control2: CGPoint(x: 8, y: -20))
        path.addCurve(to: CGPoint(x: -18, y: -2), control1: CGPoint(x: -8, y: -20), control2: CGPoint(x: -14, y: -14))
        path.closeSubpath()
        return path
    }

    private static func bowPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -24))
        path.addCurve(to: CGPoint(x: 0, y: 24), control1: CGPoint(x: 24, y: -12), control2: CGPoint(x: 24, y: 12))
        path.move(to: CGPoint(x: 0, y: -24))
        path.addLine(to: CGPoint(x: 0, y: 24))
        return path
    }

    private static func crystalPath(height: CGFloat, width: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: height / 2))
        path.addLine(to: CGPoint(x: width / 2, y: -height * 0.18))
        path.addLine(to: CGPoint(x: width * 0.28, y: -height / 2))
        path.addLine(to: CGPoint(x: -width * 0.32, y: -height / 2))
        path.addLine(to: CGPoint(x: -width / 2, y: -height * 0.16))
        path.closeSubpath()
        return path
    }

    private static func tailPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: -25, y: 11), control1: CGPoint(x: -8, y: -8), control2: CGPoint(x: -22, y: -3))
        path.addCurve(to: CGPoint(x: -10, y: 18), control1: CGPoint(x: -28, y: 20), control2: CGPoint(x: -20, y: 22))
        path.closeSubpath()
        return path
    }

    private static func earPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 2, y: 12))
        path.addLine(to: CGPoint(x: 8, y: 2))
        path.closeSubpath()
        return path
    }
}

struct CinematicHeroPortrait: View {
    let hero: HeroClass

    private var accent: Color { CinematicFX.swiftUIColor(for: hero) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.07, blue: 0.13), accent.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: 112, height: 112)
                .blur(radius: 10)
                .offset(y: 4)

            VStack(spacing: 0) {
                ZStack {
                    Capsule()
                        .fill(accent.opacity(0.42))
                        .frame(width: 54, height: 72)
                        .offset(y: 25)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color(red: 0.78, green: 0.87, blue: 0.94)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 43, height: 43)
                        .overlay(Circle().stroke(accent.opacity(0.9), lineWidth: 2))
                        .offset(y: -7)

                    HeroHairShape(hero: hero)
                        .fill(heroHairColor)
                        .frame(width: 55, height: 39)
                        .offset(y: -23)

                    weaponSymbol
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.white, accent)
                        .shadow(color: accent.opacity(0.8), radius: 8)
                        .offset(x: 42, y: 25)

                    PetPortrait(hero: hero)
                        .frame(width: 38, height: 38)
                        .offset(x: -43, y: 43)
                }
                .frame(height: 118)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.5), accent.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var weaponSymbol: some View {
        switch hero {
        case .tank: Image(systemName: "shield.lefthalf.filled")
        case .fighter: Image(systemName: "bolt.fill")
        case .assassin: Image(systemName: "moon.stars.fill")
        case .mage: Image(systemName: "sparkles")
        case .marksman: Image(systemName: "scope")
        case .support: Image(systemName: "cross.case.fill")
        }
    }

    private var heroHairColor: Color {
        switch hero {
        case .tank: return Color(red: 0.80, green: 0.91, blue: 0.98)
        case .fighter: return Color(red: 0.28, green: 0.16, blue: 0.10)
        case .assassin: return Color(red: 0.16, green: 0.09, blue: 0.24)
        case .mage: return Color(red: 0.82, green: 0.88, blue: 1.0)
        case .marksman: return Color(red: 0.43, green: 0.26, blue: 0.11)
        case .support: return Color(red: 0.82, green: 0.95, blue: 0.91)
        }
    }
}

private struct HeroHairShape: Shape {
    let hero: HeroClass

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY * 0.62))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.width * 0.16, y: rect.height * 0.15),
            control2: CGPoint(x: rect.width * 0.38, y: rect.height * 0.02)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY * 0.62),
            control1: CGPoint(x: rect.width * 0.62, y: rect.height * 0.02),
            control2: CGPoint(x: rect.width * 0.84, y: rect.height * 0.15)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.92))
        path.addLine(to: CGPoint(x: rect.width * 0.36, y: rect.height * 0.65))
        path.addLine(to: CGPoint(x: rect.width * 0.20, y: rect.height * 0.82))
        path.closeSubpath()
        return path
    }
}

private struct PetPortrait: View {
    let hero: HeroClass

    var body: some View {
        let accent = CinematicFX.swiftUIColor(for: hero)
        ZStack {
            Circle().fill(.black.opacity(0.24)).offset(y: 12).scaleEffect(x: 1.15, y: 0.36)
            Capsule().fill(accent.opacity(0.92)).frame(width: 29, height: 22).offset(x: -2, y: 4)
            Circle().fill(Color(red: 0.91, green: 0.96, blue: 1.0)).frame(width: 21, height: 21).offset(x: 8, y: -5)
            Circle().fill(.black).frame(width: 3.5, height: 3.5).offset(x: 4, y: -6)
            Circle().fill(.black).frame(width: 3.5, height: 3.5).offset(x: 11, y: -6)
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .shadow(color: accent, radius: 4)
                .offset(x: -3, y: 4)
        }
    }
}
