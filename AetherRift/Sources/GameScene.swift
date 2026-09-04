import SpriteKit
import Foundation

private enum Lane: CaseIterable {
    case top, mid, bottom
}

private enum ObjectiveKind: String {
    case turtle = "TURTLE"
    case lord = "LORD"
}

private struct ItemSpec {
    let name: String
    let cost: Int
    let requiredLevel: Int
    let attack: CGFloat
    let hp: CGFloat
    let mana: CGFloat
    let moveSpeed: CGFloat
}

private final class MinionUnit {
    let node: SKShapeNode
    let team: Int
    let lane: Lane
    let maxHP: CGFloat
    var hp: CGFloat
    var nextAttack: TimeInterval = 0
    var waypointIndex = 0
    var rewarded = false

    init(team: Int, lane: Lane, position: CGPoint, siege: Bool) {
        self.team = team
        self.lane = lane
        maxHP = siege ? 430 : 250
        hp = maxHP
        node = SKShapeNode(rectOf: siege ? CGSize(width: 30, height: 24) : CGSize(width: 24, height: 24), cornerRadius: 7)
        node.position = position
        node.fillColor = team == 0 ? .systemTeal : .systemRed
        node.strokeColor = .white.withAlphaComponent(0.55)
        node.lineWidth = 1.5
        node.zPosition = 8

        let mark = SKShapeNode(circleOfRadius: siege ? 6 : 4)
        mark.fillColor = siege ? .systemYellow : .white
        mark.strokeColor = .clear
        node.addChild(mark)
    }
}

private final class TowerUnit {
    let node: SKShapeNode
    let team: Int
    let lane: Lane?
    let tier: Int
    let maxHP: CGFloat
    var hp: CGFloat
    var nextAttack: TimeInterval = 0

    init(team: Int, lane: Lane?, tier: Int, position: CGPoint) {
        self.team = team
        self.lane = lane
        self.tier = tier
        maxHP = tier == 0 ? 5200 : 2300 + CGFloat(3 - tier) * 260
        hp = maxHP
        node = SKShapeNode(rectOf: CGSize(width: tier == 0 ? 92 : 58, height: tier == 0 ? 92 : 94), cornerRadius: 14)
        node.position = position
        node.fillColor = team == 0 ? .systemCyan : .systemPink
        node.strokeColor = .white.withAlphaComponent(0.68)
        node.lineWidth = 2
        node.zPosition = 10

        let crown = SKShapeNode(circleOfRadius: tier == 0 ? 22 : 14)
        crown.position = CGPoint(x: 0, y: tier == 0 ? 0 : 34)
        crown.fillColor = team == 0 ? .systemBlue : .systemRed
        crown.strokeColor = .white.withAlphaComponent(0.6)
        crown.lineWidth = 1
        node.addChild(crown)
    }
}

private final class BotUnit {
    let node = SKNode()
    let team: Int
    let lane: Lane
    let heroClass: HeroClass
    let heroName: String
    let isJungler: Bool
    let baseMaxHP: CGFloat
    var hp: CGFloat
    var level = 1
    var gold = 300
    var nextAttack: TimeInterval = 0
    var nextSkill: TimeInterval = 0
    var respawnAt: TimeInterval?

    var maxHP: CGFloat { baseMaxHP + CGFloat(level - 1) * 62 }
    var attackDamage: CGFloat { heroClass.attackDamage * 0.88 + CGFloat(level - 1) * 4.2 }
    var attackRange: CGFloat { max(120, heroClass.attackRange) }
    var moveSpeed: CGFloat { heroClass.moveSpeed * 0.74 + 18 }

    init(team: Int, lane: Lane, heroClass: HeroClass, heroName: String, position: CGPoint, isJungler: Bool) {
        self.team = team
        self.lane = lane
        self.heroClass = heroClass
        self.heroName = heroName
        self.isJungler = isJungler
        baseMaxHP = heroClass.maxHP * 0.92
        hp = baseMaxHP
        node.position = position
        node.zPosition = 15

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 50, height: 18))
        shadow.position = CGPoint(x: 0, y: -23)
        shadow.fillColor = .black.withAlphaComponent(0.28)
        shadow.strokeColor = .clear
        node.addChild(shadow)

        let body = SKShapeNode(rectOf: CGSize(width: 38, height: 42), cornerRadius: 12)
        body.position = CGPoint(x: 0, y: 0)
        body.fillColor = BotUnit.color(for: heroClass, team: team)
        body.strokeColor = .white.withAlphaComponent(0.85)
        body.lineWidth = 2
        node.addChild(body)

        let head = SKShapeNode(circleOfRadius: 12)
        head.position = CGPoint(x: 0, y: 25)
        head.fillColor = team == 0 ? .white : SKColor(red: 1, green: 0.78, blue: 0.78, alpha: 1)
        head.strokeColor = .clear
        node.addChild(head)

        let role = SKLabelNode(fontNamed: "AvenirNext-Bold")
        role.text = String(heroClass.rawValue.prefix(1))
        role.fontSize = 11
        role.fontColor = .black
        role.verticalAlignmentMode = .center
        role.position = CGPoint(x: 0, y: 25)
        node.addChild(role)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = heroName
        label.fontSize = 10
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: 42)
        node.addChild(label)
    }

    private static func color(for heroClass: HeroClass, team: Int) -> SKColor {
        let base: SKColor
        switch heroClass {
        case .tank: base = .systemCyan
        case .fighter: base = .systemOrange
        case .assassin: base = .systemPurple
        case .mage: base = .systemIndigo
        case .marksman: base = .systemYellow
        case .support: base = .systemGreen
        }
        return team == 0 ? base : base.withAlphaComponent(0.78)
    }
}

private final class CampUnit {
    let node = SKNode()
    let maxHP: CGFloat
    let elite: Bool
    var hp: CGFloat
    var respawnAt: TimeInterval?

    init(position: CGPoint, elite: Bool) {
        self.elite = elite
        maxHP = elite ? 1450 : 900
        hp = maxHP
        node.position = position
        node.zPosition = 7

        let body = SKShapeNode(circleOfRadius: elite ? 34 : 28)
        body.fillColor = elite ? .systemPurple : SKColor(red: 0.20, green: 0.48, blue: 0.18, alpha: 1)
        body.strokeColor = .white.withAlphaComponent(0.55)
        body.lineWidth = 2
        node.addChild(body)

        let eye = SKShapeNode(circleOfRadius: 7)
        eye.fillColor = elite ? .systemYellow : .white
        eye.strokeColor = .clear
        node.addChild(eye)
    }
}

private final class ObjectiveUnit {
    let kind: ObjectiveKind
    let node = SKNode()
    let spawnAt: TimeInterval
    let respawnDelay: TimeInterval
    let maxHP: CGFloat
    var hp: CGFloat
    var respawnAt: TimeInterval?
    var nextAttack: TimeInterval = 0

    init(kind: ObjectiveKind, position: CGPoint, spawnAt: TimeInterval) {
        self.kind = kind
        self.spawnAt = spawnAt
        respawnDelay = kind == .turtle ? 75 : 130
        maxHP = kind == .turtle ? 4200 : 8600
        hp = maxHP
        node.position = position
        node.zPosition = 12
        node.isHidden = true

        let body = SKShapeNode(ellipseOf: kind == .turtle ? CGSize(width: 92, height: 70) : CGSize(width: 112, height: 98))
        body.fillColor = kind == .turtle ? SKColor(red: 0.18, green: 0.58, blue: 0.50, alpha: 1) : SKColor(red: 0.36, green: 0.20, blue: 0.58, alpha: 1)
        body.strokeColor = .white.withAlphaComponent(0.7)
        body.lineWidth = 3
        node.addChild(body)

        let shell = SKShapeNode(circleOfRadius: kind == .turtle ? 24 : 31)
        shell.fillColor = kind == .turtle ? SKColor(red: 0.10, green: 0.35, blue: 0.30, alpha: 1) : SKColor(red: 0.20, green: 0.10, blue: 0.34, alpha: 1)
        shell.strokeColor = .systemYellow.withAlphaComponent(0.7)
        shell.lineWidth = 2
        node.addChild(shell)

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = kind.rawValue
        label.fontSize = 12
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: kind == .turtle ? 48 : 60)
        node.addChild(label)
    }
}

private final class LordPushUnit {
    let node = SKNode()
    let team: Int
    let maxHP: CGFloat = 6500
    var hp: CGFloat = 6500
    var nextAttack: TimeInterval = 0

    init(team: Int, position: CGPoint) {
        self.team = team
        node.position = position
        node.zPosition = 13

        let body = SKShapeNode(rectOf: CGSize(width: 74, height: 86), cornerRadius: 20)
        body.fillColor = team == 0 ? .systemIndigo : .systemRed
        body.strokeColor = .systemYellow
        body.lineWidth = 3
        node.addChild(body)

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "LORD"
        label.fontSize = 12
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: 52)
        node.addChild(label)
    }
}

final class GameScene: SKScene {
    private let heroClass: HeroClass
    private let worldWidth: CGFloat = 3000
    private let worldHeight: CGFloat = 1800

    private var world = SKNode()
    private var gameCamera = SKCameraNode()
    private var player = SKNode()
    private var hpBack = SKSpriteNode(color: .black.withAlphaComponent(0.60), size: CGSize(width: 214, height: 15))
    private var hpBar = SKSpriteNode(color: .systemGreen, size: CGSize(width: 210, height: 11))
    private var manaBack = SKSpriteNode(color: .black.withAlphaComponent(0.60), size: CGSize(width: 214, height: 11))
    private var manaBar = SKSpriteNode(color: .systemBlue, size: CGSize(width: 210, height: 7))
    private var scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var statusLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var objectiveLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var messageLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var miniMap = SKShapeNode()
    private var miniMapDynamic = SKNode()

    private var minions: [MinionUnit] = []
    private var towers: [TowerUnit] = []
    private var bots: [BotUnit] = []
    private var camps: [CampUnit] = []
    private var objectives: [ObjectiveUnit] = []
    private var lordPushes: [LordPushUnit] = []
    private var grassCenters: [CGPoint] = []

    private var didBootstrap = false
    private var movement = CGVector.zero
    private var lastFrameTime: TimeInterval = 0
    private var sceneNow: TimeInterval = 0
    private var matchStartTime: TimeInterval = 0
    private var matchElapsed: TimeInterval = 0
    private var lastWaveTime: TimeInterval = -100
    private var lastMiniMapUpdate: TimeInterval = -100
    private var lastAttackTime: TimeInterval = -100
    private var skillLastUsed: [Int: TimeInterval] = [:]
    private var playerRespawnAt: TimeInterval?
    private var playerHP: CGFloat = 1
    private var playerMana: CGFloat = 1
    private var shieldHP: CGFloat = 0
    private var attackBuffUntil: TimeInterval = 0
    private var stealthUntil: TimeInterval = 0
    private var blueTeamBuffUntil: TimeInterval = 0
    private var redTeamBuffUntil: TimeInterval = 0
    private var blueKills = 0
    private var redKills = 0
    private var gameOver = false

    private var playerLevel = 1
    private var playerXP = 0
    private var playerGold = 300
    private var ownedItems: [ItemSpec] = []

    init(size: CGSize, heroClass: HeroClass) {
        self.heroClass = heroClass
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func didMove(to view: SKView) {
        guard !didBootstrap else { return }
        didBootstrap = true
        restartMatch()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateCameraPosition(immediate: true)
        layoutHUD()
    }

    func restartMatch() {
        removeAllActions()
        removeAllChildren()
        camera = nil

        world = SKNode()
        gameCamera = SKCameraNode()
        player = SKNode()
        hpBack = SKSpriteNode(color: .black.withAlphaComponent(0.60), size: CGSize(width: 214, height: 15))
        hpBar = SKSpriteNode(color: .systemGreen, size: CGSize(width: 210, height: 11))
        manaBack = SKSpriteNode(color: .black.withAlphaComponent(0.60), size: CGSize(width: 214, height: 11))
        manaBar = SKSpriteNode(color: .systemBlue, size: CGSize(width: 210, height: 7))
        scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        statusLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        objectiveLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        messageLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        miniMap = SKShapeNode(rectOf: CGSize(width: 184, height: 110), cornerRadius: 10)
        miniMapDynamic = SKNode()

        minions.removeAll()
        towers.removeAll()
        bots.removeAll()
        camps.removeAll()
        objectives.removeAll()
        lordPushes.removeAll()
        grassCenters.removeAll()
        movement = .zero
        lastFrameTime = 0
        sceneNow = 0
        matchStartTime = 0
        matchElapsed = 0
        lastWaveTime = -100
        lastMiniMapUpdate = -100
        lastAttackTime = -100
        skillLastUsed.removeAll()
        playerRespawnAt = nil
        playerLevel = 1
        playerXP = 0
        playerGold = 300
        ownedItems.removeAll()
        playerHP = playerMaxHP
        playerMana = playerMaxMana
        shieldHP = 0
        attackBuffUntil = 0
        stealthUntil = 0
        blueTeamBuffUntil = 0
        redTeamBuffUntil = 0
        blueKills = 0
        redKills = 0
        gameOver = false

        addChild(world)
        buildMap()
        buildStructures()
        buildPlayer()
        buildBots()
        buildCamps()
        buildObjectives()
        buildCameraAndHUD()
        spawnWave()
        updateHUD()
    }

    // MARK: - Map

    private func buildMap() {
        let ground = SKSpriteNode(
            color: SKColor(red: 0.035, green: 0.145, blue: 0.075, alpha: 1),
            size: CGSize(width: worldWidth, height: worldHeight)
        )
        ground.anchorPoint = .zero
        ground.position = .zero
        ground.zPosition = -40
        world.addChild(ground)

        // Grass texture patches.
        for x in stride(from: CGFloat(120), through: worldWidth - 120, by: 150) {
            for y in stride(from: CGFloat(120), through: worldHeight - 120, by: 150) {
                let blade = SKShapeNode(ellipseOf: CGSize(width: 72, height: 24))
                blade.position = CGPoint(x: x + CGFloat(Int(y) % 37), y: y + CGFloat(Int(x) % 29))
                blade.fillColor = SKColor(red: 0.05, green: 0.20 + CGFloat((Int(x + y) / 150) % 3) * 0.02, blue: 0.08, alpha: 0.5)
                blade.strokeColor = .clear
                blade.zPosition = -38
                world.addChild(blade)
            }
        }

        let river = SKShapeNode(rectOf: CGSize(width: 205, height: worldHeight + 100), cornerRadius: 56)
        river.position = CGPoint(x: worldWidth / 2, y: worldHeight / 2)
        river.fillColor = SKColor(red: 0.04, green: 0.30, blue: 0.43, alpha: 0.90)
        river.strokeColor = SKColor(red: 0.30, green: 0.72, blue: 0.78, alpha: 0.25)
        river.lineWidth = 8
        river.zPosition = -33
        world.addChild(river)

        for y in stride(from: CGFloat(100), through: worldHeight - 100, by: 180) {
            let waterLine = SKShapeNode(rectOf: CGSize(width: 130, height: 5), cornerRadius: 2)
            waterLine.position = CGPoint(x: worldWidth / 2 + (Int(y) % 2 == 0 ? 14 : -14), y: y)
            waterLine.fillColor = .white.withAlphaComponent(0.10)
            waterLine.strokeColor = .clear
            waterLine.zPosition = -32
            world.addChild(waterLine)
        }

        for lane in Lane.allCases {
            let points = lanePoints(lane)
            let path = CGMutablePath()
            if let first = points.first {
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }

            let border = SKShapeNode(path: path)
            border.strokeColor = SKColor(red: 0.45, green: 0.39, blue: 0.27, alpha: 0.32)
            border.lineWidth = 168
            border.lineCap = .round
            border.lineJoin = .round
            border.zPosition = -31
            world.addChild(border)

            let road = SKShapeNode(path: path)
            road.strokeColor = SKColor(red: 0.24, green: 0.24, blue: 0.18, alpha: 1)
            road.lineWidth = 148
            road.lineCap = .round
            road.lineJoin = .round
            road.zPosition = -30
            world.addChild(road)

            let center = SKShapeNode(path: path)
            center.strokeColor = .white.withAlphaComponent(0.035)
            center.lineWidth = 4
            center.zPosition = -29
            world.addChild(center)
        }

        let bushPositions: [CGPoint] = [
            CGPoint(x: 720, y: 650), CGPoint(x: 900, y: 1120), CGPoint(x: 1100, y: 590),
            CGPoint(x: 1260, y: 1210), CGPoint(x: 1380, y: 720), CGPoint(x: 1620, y: 1080),
            CGPoint(x: 1740, y: 610), CGPoint(x: 1940, y: 1190), CGPoint(x: 2120, y: 650),
            CGPoint(x: 2280, y: 1120), CGPoint(x: 820, y: 1000), CGPoint(x: 2180, y: 820)
        ]
        for position in bushPositions {
            grassCenters.append(position)
            addBush(at: position)
        }

        let rockPositions = [
            CGPoint(x: 1040, y: 760), CGPoint(x: 1170, y: 1040), CGPoint(x: 1830, y: 760),
            CGPoint(x: 1970, y: 1020), CGPoint(x: 640, y: 1080), CGPoint(x: 2350, y: 690)
        ]
        for p in rockPositions {
            let rock = SKShapeNode(ellipseOf: CGSize(width: 68, height: 48))
            rock.position = p
            rock.fillColor = SKColor(red: 0.26, green: 0.28, blue: 0.25, alpha: 1)
            rock.strokeColor = .white.withAlphaComponent(0.08)
            rock.lineWidth = 2
            rock.zPosition = -18
            world.addChild(rock)
        }

        addBase(team: 0, at: CGPoint(x: 180, y: 900))
        addBase(team: 1, at: CGPoint(x: worldWidth - 180, y: 900))
    }

    private func addBush(at point: CGPoint) {
        let bush = SKNode()
        bush.position = point
        bush.zPosition = -16
        for i in 0..<7 {
            let leaf = SKShapeNode(ellipseOf: CGSize(width: 48, height: 34))
            let angle = CGFloat(i) / 7 * .pi * 2
            leaf.position = CGPoint(x: cos(angle) * 35, y: sin(angle) * 21)
            leaf.fillColor = i.isMultiple(of: 2)
                ? SKColor(red: 0.04, green: 0.30, blue: 0.08, alpha: 0.98)
                : SKColor(red: 0.08, green: 0.38, blue: 0.10, alpha: 0.96)
            leaf.strokeColor = .clear
            bush.addChild(leaf)
        }
        world.addChild(bush)
    }

    private func addBase(team: Int, at position: CGPoint) {
        let base = SKShapeNode(circleOfRadius: 165)
        base.position = position
        base.fillColor = team == 0 ? .systemBlue.withAlphaComponent(0.18) : .systemRed.withAlphaComponent(0.18)
        base.strokeColor = team == 0 ? .systemCyan.withAlphaComponent(0.55) : .systemPink.withAlphaComponent(0.55)
        base.lineWidth = 6
        base.zPosition = -14
        world.addChild(base)

        for angle in stride(from: CGFloat(0), to: CGFloat.pi * 2, by: CGFloat.pi / 4) {
            let rune = SKShapeNode(circleOfRadius: 7)
            rune.position = CGPoint(x: position.x + cos(angle) * 120, y: position.y + sin(angle) * 120)
            rune.fillColor = team == 0 ? .systemCyan : .systemPink
            rune.strokeColor = .clear
            rune.zPosition = -13
            world.addChild(rune)
        }
    }

    private func lanePoints(_ lane: Lane) -> [CGPoint] {
        switch lane {
        case .top:
            return [
                CGPoint(x: 260, y: 900), CGPoint(x: 450, y: 1280), CGPoint(x: 800, y: 1450),
                CGPoint(x: 1500, y: 1450), CGPoint(x: 2200, y: 1450), CGPoint(x: 2550, y: 1280),
                CGPoint(x: 2740, y: 900)
            ]
        case .mid:
            return [
                CGPoint(x: 260, y: 900), CGPoint(x: 650, y: 900), CGPoint(x: 1050, y: 900),
                CGPoint(x: 1500, y: 900), CGPoint(x: 1950, y: 900), CGPoint(x: 2350, y: 900),
                CGPoint(x: 2740, y: 900)
            ]
        case .bottom:
            return [
                CGPoint(x: 260, y: 900), CGPoint(x: 450, y: 520), CGPoint(x: 800, y: 350),
                CGPoint(x: 1500, y: 350), CGPoint(x: 2200, y: 350), CGPoint(x: 2550, y: 520),
                CGPoint(x: 2740, y: 900)
            ]
        }
    }

    // MARK: - Units and structures

    private func buildStructures() {
        for lane in Lane.allCases {
            let points = lanePoints(lane)
            let bluePositions = [points[1], points[2], interpolate(points[2], points[3], 0.57)]
            let redPositions = [points[5], points[4], interpolate(points[4], points[3], 0.57)]

            for (index, position) in bluePositions.enumerated() {
                let tower = TowerUnit(team: 0, lane: lane, tier: index + 1, position: position)
                towers.append(tower)
                world.addChild(tower.node)
            }
            for (index, position) in redPositions.enumerated() {
                let tower = TowerUnit(team: 1, lane: lane, tier: index + 1, position: position)
                towers.append(tower)
                world.addChild(tower.node)
            }
        }

        let blueCore = TowerUnit(team: 0, lane: nil, tier: 0, position: CGPoint(x: 180, y: 900))
        let redCore = TowerUnit(team: 1, lane: nil, tier: 0, position: CGPoint(x: worldWidth - 180, y: 900))
        towers.append(contentsOf: [blueCore, redCore])
        world.addChild(blueCore.node)
        world.addChild(redCore.node)
    }

    private func buildPlayer() {
        player = heroVisual(heroClass: heroClass, team: 0, name: heroName(for: heroClass))
        player.position = CGPoint(x: 330, y: 900)
        player.zPosition = 18
        world.addChild(player)
    }

    private func buildBots() {
        let alliedClasses = alliedBotClasses(for: heroClass)
        for (index, botClass) in alliedClasses.enumerated() {
            let lane = laneForClass(botClass)
            let bot = BotUnit(
                team: 0,
                lane: lane,
                heroClass: botClass,
                heroName: heroName(for: botClass),
                position: botSpawn(team: 0, lane: lane, offset: CGFloat(index * 30)),
                isJungler: botClass == .assassin
            )
            bots.append(bot)
            world.addChild(bot.node)
        }

        let enemyClasses: [HeroClass] = [.fighter, .assassin, .mage, .marksman, .tank]
        for (index, botClass) in enemyClasses.enumerated() {
            let lane = laneForClass(botClass)
            let bot = BotUnit(
                team: 1,
                lane: lane,
                heroClass: botClass,
                heroName: enemyHeroName(for: botClass),
                position: botSpawn(team: 1, lane: lane, offset: CGFloat(index * 30)),
                isJungler: botClass == .assassin
            )
            bots.append(bot)
            world.addChild(bot.node)
        }
    }

    private func buildCamps() {
        let definitions: [(CGPoint, Bool)] = [
            (CGPoint(x: 840, y: 690), false), (CGPoint(x: 1010, y: 1110), true),
            (CGPoint(x: 1210, y: 690), false), (CGPoint(x: 1790, y: 1110), false),
            (CGPoint(x: 1990, y: 690), true), (CGPoint(x: 2160, y: 1110), false)
        ]
        for definition in definitions {
            let camp = CampUnit(position: definition.0, elite: definition.1)
            camps.append(camp)
            world.addChild(camp.node)
        }
    }

    private func buildObjectives() {
        let turtle = ObjectiveUnit(kind: .turtle, position: CGPoint(x: 1500, y: 625), spawnAt: 12)
        let lord = ObjectiveUnit(kind: .lord, position: CGPoint(x: 1500, y: 1175), spawnAt: 90)
        objectives = [turtle, lord]
        world.addChild(turtle.node)
        world.addChild(lord.node)
    }

    private func heroVisual(heroClass: HeroClass, team: Int, name: String) -> SKNode {
        let node = SKNode()

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 56, height: 20))
        shadow.position = CGPoint(x: 0, y: -25)
        shadow.fillColor = .black.withAlphaComponent(0.30)
        shadow.strokeColor = .clear
        node.addChild(shadow)

        let cape = SKShapeNode(rectOf: CGSize(width: 42, height: 48), cornerRadius: 13)
        cape.fillColor = color(for: heroClass).withAlphaComponent(team == 0 ? 1 : 0.78)
        cape.strokeColor = .white.withAlphaComponent(0.9)
        cape.lineWidth = 2.5
        node.addChild(cape)

        let head = SKShapeNode(circleOfRadius: 13)
        head.position = CGPoint(x: 0, y: 27)
        head.fillColor = .white
        head.strokeColor = color(for: heroClass)
        head.lineWidth = 2
        node.addChild(head)

        let emblem = SKLabelNode(fontNamed: "AvenirNext-Bold")
        emblem.text = String(heroClass.rawValue.prefix(1))
        emblem.fontSize = 12
        emblem.fontColor = .black
        emblem.verticalAlignmentMode = .center
        emblem.position = CGPoint(x: 0, y: 27)
        node.addChild(emblem)

        let nameLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        nameLabel.text = name
        nameLabel.fontSize = 10
        nameLabel.fontColor = .white
        nameLabel.position = CGPoint(x: 0, y: 45)
        node.addChild(nameLabel)
        return node
    }

    private func alliedBotClasses(for selected: HeroClass) -> [HeroClass] {
        let core: [HeroClass] = [.fighter, .assassin, .mage, .marksman]
        var result = core.filter { $0 != selected }
        if selected != .tank && selected != .support {
            result.append(.tank)
        }
        if result.count < 4 && selected != .support { result.append(.support) }
        return Array(result.prefix(4))
    }

    private func laneForClass(_ heroClass: HeroClass) -> Lane {
        switch heroClass {
        case .fighter: return .top
        case .mage: return .mid
        case .marksman, .tank, .support: return .bottom
        case .assassin: return .mid
        }
    }

    private func heroName(for heroClass: HeroClass) -> String {
        switch heroClass {
        case .tank: return "Bastion"
        case .fighter: return "Kael"
        case .assassin: return "Nyx"
        case .mage: return "Lyra"
        case .marksman: return "Orion"
        case .support: return "Mira"
        }
    }

    private func enemyHeroName(for heroClass: HeroClass) -> String {
        switch heroClass {
        case .tank: return "Grom"
        case .fighter: return "Raze"
        case .assassin: return "Vex"
        case .mage: return "Sable"
        case .marksman: return "Kestrel"
        case .support: return "Eira"
        }
    }

    // MARK: - HUD and minimap

    private func buildCameraAndHUD() {
        camera = gameCamera
        gameCamera.position = player.position
        gameCamera.setScale(1)
        addChild(gameCamera)

        hpBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpBack.zPosition = 100
        gameCamera.addChild(hpBack)

        hpBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpBar.zPosition = 101
        gameCamera.addChild(hpBar)

        manaBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        manaBack.zPosition = 100
        gameCamera.addChild(manaBack)

        manaBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        manaBar.zPosition = 101
        gameCamera.addChild(manaBar)

        scoreLabel.fontSize = 17
        scoreLabel.zPosition = 101
        gameCamera.addChild(scoreLabel)

        statusLabel.fontSize = 11
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.zPosition = 101
        gameCamera.addChild(statusLabel)

        objectiveLabel.fontSize = 10
        objectiveLabel.horizontalAlignmentMode = .right
        objectiveLabel.zPosition = 101
        gameCamera.addChild(objectiveLabel)

        messageLabel.fontSize = 15
        messageLabel.alpha = 0
        messageLabel.zPosition = 101
        gameCamera.addChild(messageLabel)

        miniMap.fillColor = .black.withAlphaComponent(0.66)
        miniMap.strokeColor = .white.withAlphaComponent(0.35)
        miniMap.lineWidth = 1.5
        miniMap.zPosition = 100
        gameCamera.addChild(miniMap)
        buildMiniMapStatic()
        miniMap.addChild(miniMapDynamic)

        layoutHUD()
        updateCameraPosition(immediate: true)
        updateMiniMap()
    }

    private func buildMiniMapStatic() {
        let miniW: CGFloat = 166
        let miniH: CGFloat = 94

        for lane in Lane.allCases {
            let path = CGMutablePath()
            let points = lanePoints(lane).map { miniPoint($0, width: miniW, height: miniH) }
            if let first = points.first {
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            let laneLine = SKShapeNode(path: path)
            laneLine.strokeColor = .white.withAlphaComponent(0.24)
            laneLine.lineWidth = 3
            laneLine.zPosition = 1
            miniMap.addChild(laneLine)
        }

        let river = SKShapeNode(rectOf: CGSize(width: 8, height: miniH), cornerRadius: 3)
        river.fillColor = .systemBlue.withAlphaComponent(0.45)
        river.strokeColor = .clear
        river.zPosition = 0
        miniMap.addChild(river)

        let t = miniLabel("T", at: miniPoint(CGPoint(x: 1500, y: 625), width: miniW, height: miniH), color: .systemGreen)
        let l = miniLabel("L", at: miniPoint(CGPoint(x: 1500, y: 1175), width: miniW, height: miniH), color: .systemPurple)
        miniMap.addChild(t)
        miniMap.addChild(l)
    }

    private func miniLabel(_ text: String, at position: CGPoint, color: SKColor) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 9
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.position = position
        label.zPosition = 3
        return label
    }

    private func updateMiniMap() {
        guard miniMap.parent != nil else { return }
        miniMapDynamic.removeAllChildren()
        let miniW: CGFloat = 166
        let miniH: CGFloat = 94

        let playerDot = SKShapeNode(circleOfRadius: 4)
        playerDot.position = miniPoint(player.position, width: miniW, height: miniH)
        playerDot.fillColor = .systemYellow
        playerDot.strokeColor = .white
        playerDot.lineWidth = 1
        playerDot.zPosition = 6
        miniMapDynamic.addChild(playerDot)

        for bot in bots where bot.respawnAt == nil && !bot.node.isHidden {
            let dot = SKShapeNode(circleOfRadius: bot.isJungler ? 3.6 : 3)
            dot.position = miniPoint(bot.node.position, width: miniW, height: miniH)
            dot.fillColor = bot.team == 0 ? .systemCyan : .systemRed
            dot.strokeColor = .clear
            dot.zPosition = 5
            miniMapDynamic.addChild(dot)
        }

        for tower in towers where tower.hp > 0 && tower.node.parent != nil {
            let dot = SKShapeNode(rectOf: CGSize(width: tower.tier == 0 ? 6 : 4, height: tower.tier == 0 ? 6 : 4), cornerRadius: 1)
            dot.position = miniPoint(tower.node.position, width: miniW, height: miniH)
            dot.fillColor = tower.team == 0 ? .systemBlue : .systemPink
            dot.strokeColor = .clear
            dot.zPosition = 4
            miniMapDynamic.addChild(dot)
        }

        for objective in objectives where !objective.node.isHidden {
            let ring = SKShapeNode(circleOfRadius: objective.kind == .turtle ? 4.5 : 5.5)
            ring.position = miniPoint(objective.node.position, width: miniW, height: miniH)
            ring.fillColor = objective.kind == .turtle ? .systemGreen : .systemPurple
            ring.strokeColor = .systemYellow
            ring.lineWidth = 1
            ring.zPosition = 7
            miniMapDynamic.addChild(ring)
        }

        for summon in lordPushes where summon.hp > 0 && summon.node.parent != nil {
            let dot = SKShapeNode(circleOfRadius: 4.5)
            dot.position = miniPoint(summon.node.position, width: miniW, height: miniH)
            dot.fillColor = summon.team == 0 ? .systemIndigo : .systemRed
            dot.strokeColor = .systemYellow
            dot.lineWidth = 1
            miniMapDynamic.addChild(dot)
        }
    }

    private func miniPoint(_ point: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x / worldWidth) * width - width / 2,
            y: (point.y / worldHeight) * height - height / 2
        )
    }

    private func layoutHUD() {
        guard gameCamera.parent != nil else { return }
        let halfW = max(300, size.width / 2)
        let halfH = max(170, size.height / 2)
        let left = -halfW + 18
        let right = halfW - 24
        let top = halfH - 22

        miniMap.position = CGPoint(x: left + 92, y: top - 55)

        let statsX = left + 196
        hpBack.position = CGPoint(x: statsX, y: top - 3)
        hpBar.position = CGPoint(x: statsX + 2, y: top - 3)
        manaBack.position = CGPoint(x: statsX, y: top - 21)
        manaBar.position = CGPoint(x: statsX + 2, y: top - 21)
        statusLabel.position = CGPoint(x: statsX, y: top - 42)

        scoreLabel.position = CGPoint(x: 0, y: top - 2)
        objectiveLabel.position = CGPoint(x: right, y: top - 4)
        messageLabel.position = CGPoint(x: 0, y: -halfH + 80)
    }

    // MARK: - Player controls, levels and items

    func setMovement(_ vector: CGVector) {
        movement = vector
    }

    func buyRecommendedItem() {
        guard !gameOver else { return }
        let items = recommendedItems()
        guard ownedItems.count < items.count else {
            showMessage("All 6 items completed")
            return
        }

        let item = items[ownedItems.count]
        guard playerLevel >= item.requiredLevel else {
            showMessage("\(item.name) unlocks at Lv \(item.requiredLevel)")
            return
        }
        guard playerGold >= item.cost else {
            showMessage("Need \(item.cost - playerGold) more gold")
            return
        }

        playerGold -= item.cost
        let oldMaxHP = playerMaxHP
        ownedItems.append(item)
        let hpGain = max(0, playerMaxHP - oldMaxHP)
        playerHP = min(playerMaxHP, playerHP + hpGain)
        playerMana = min(playerMaxMana, playerMana + item.mana)
        showMessage("Bought \(item.name)")
        updateHUD()
    }

    private func recommendedItems() -> [ItemSpec] {
        let levels = [2, 4, 6, 9, 12, 15]
        switch heroClass {
        case .tank:
            return [
                ItemSpec(name: "Stoneguard", cost: 420, requiredLevel: levels[0], attack: 0, hp: 180, mana: 0, moveSpeed: 0),
                ItemSpec(name: "Iron Mantle", cost: 620, requiredLevel: levels[1], attack: 0, hp: 250, mana: 50, moveSpeed: 0),
                ItemSpec(name: "Frost Aegis", cost: 820, requiredLevel: levels[2], attack: 8, hp: 300, mana: 80, moveSpeed: 0),
                ItemSpec(name: "Guardian Heart", cost: 1050, requiredLevel: levels[3], attack: 0, hp: 420, mana: 0, moveSpeed: 0),
                ItemSpec(name: "Titan Plate", cost: 1320, requiredLevel: levels[4], attack: 12, hp: 520, mana: 0, moveSpeed: 0),
                ItemSpec(name: "World Bastion", cost: 1680, requiredLevel: levels[5], attack: 18, hp: 680, mana: 100, moveSpeed: 8)
            ]
        case .fighter:
            return fighterItems(levels)
        case .assassin:
            return assassinItems(levels)
        case .mage:
            return mageItems(levels)
        case .marksman:
            return marksmanItems(levels)
        case .support:
            return supportItems(levels)
        }
    }

    private func fighterItems(_ levels: [Int]) -> [ItemSpec] {
        [
            ItemSpec(name: "Iron Cleaver", cost: 430, requiredLevel: levels[0], attack: 18, hp: 80, mana: 0, moveSpeed: 0),
            ItemSpec(name: "War Boots", cost: 600, requiredLevel: levels[1], attack: 10, hp: 80, mana: 0, moveSpeed: 18),
            ItemSpec(name: "Blood Edge", cost: 820, requiredLevel: levels[2], attack: 30, hp: 120, mana: 0, moveSpeed: 0),
            ItemSpec(name: "Breaker Axe", cost: 1060, requiredLevel: levels[3], attack: 38, hp: 180, mana: 0, moveSpeed: 0),
            ItemSpec(name: "Phoenix Guard", cost: 1330, requiredLevel: levels[4], attack: 28, hp: 300, mana: 0, moveSpeed: 0),
            ItemSpec(name: "Ascendant Blade", cost: 1700, requiredLevel: levels[5], attack: 62, hp: 220, mana: 0, moveSpeed: 8)
        ]
    }

    private func assassinItems(_ levels: [Int]) -> [ItemSpec] {
        [
            ItemSpec(name: "Shadow Knife", cost: 430, requiredLevel: levels[0], attack: 22, hp: 0, mana: 0, moveSpeed: 5),
            ItemSpec(name: "Night Boots", cost: 610, requiredLevel: levels[1], attack: 12, hp: 0, mana: 0, moveSpeed: 22),
            ItemSpec(name: "Void Fang", cost: 840, requiredLevel: levels[2], attack: 34, hp: 0, mana: 40, moveSpeed: 0),
            ItemSpec(name: "Hunter Claw", cost: 1080, requiredLevel: levels[3], attack: 44, hp: 80, mana: 0, moveSpeed: 4),
            ItemSpec(name: "Eclipse Edge", cost: 1350, requiredLevel: levels[4], attack: 55, hp: 0, mana: 0, moveSpeed: 0),
            ItemSpec(name: "Abyss Reaver", cost: 1740, requiredLevel: levels[5], attack: 76, hp: 100, mana: 0, moveSpeed: 8)
        ]
    }

    private func mageItems(_ levels: [Int]) -> [ItemSpec] {
        [
            ItemSpec(name: "Arc Tome", cost: 420, requiredLevel: levels[0], attack: 14, hp: 0, mana: 100, moveSpeed: 0),
            ItemSpec(name: "Mystic Shoes", cost: 600, requiredLevel: levels[1], attack: 8, hp: 0, mana: 80, moveSpeed: 18),
            ItemSpec(name: "Prism Core", cost: 830, requiredLevel: levels[2], attack: 28, hp: 80, mana: 140, moveSpeed: 0),
            ItemSpec(name: "Astral Crown", cost: 1060, requiredLevel: levels[3], attack: 38, hp: 0, mana: 180, moveSpeed: 0),
            ItemSpec(name: "Starfire Orb", cost: 1340, requiredLevel: levels[4], attack: 52, hp: 100, mana: 140, moveSpeed: 0),
            ItemSpec(name: "Celestial Codex", cost: 1720, requiredLevel: levels[5], attack: 70, hp: 120, mana: 220, moveSpeed: 6)
        ]
    }

    private func marksmanItems(_ levels: [Int]) -> [ItemSpec] {
        [
            ItemSpec(name: "Swift Bow", cost: 420, requiredLevel: levels[0], attack: 18, hp: 0, mana: 0, moveSpeed: 4),
            ItemSpec(name: "Gale Boots", cost: 600, requiredLevel: levels[1], attack: 10, hp: 0, mana: 0, moveSpeed: 22),
            ItemSpec(name: "Piercing Quiver", cost: 820, requiredLevel: levels[2], attack: 30, hp: 0, mana: 0, moveSpeed: 0),
            ItemSpec(name: "Storm String", cost: 1050, requiredLevel: levels[3], attack: 40, hp: 60, mana: 0, moveSpeed: 4),
            ItemSpec(name: "Deadeye Lens", cost: 1330, requiredLevel: levels[4], attack: 54, hp: 0, mana: 0, moveSpeed: 0),
            ItemSpec(name: "Sunpiercer", cost: 1700, requiredLevel: levels[5], attack: 72, hp: 80, mana: 0, moveSpeed: 8)
        ]
    }

    private func supportItems(_ levels: [Int]) -> [ItemSpec] {
        [
            ItemSpec(name: "Kindle Charm", cost: 400, requiredLevel: levels[0], attack: 6, hp: 90, mana: 100, moveSpeed: 0),
            ItemSpec(name: "Pilgrim Boots", cost: 580, requiredLevel: levels[1], attack: 0, hp: 90, mana: 70, moveSpeed: 20),
            ItemSpec(name: "Harmony Bell", cost: 800, requiredLevel: levels[2], attack: 12, hp: 160, mana: 130, moveSpeed: 0),
            ItemSpec(name: "Guardian Lantern", cost: 1020, requiredLevel: levels[3], attack: 8, hp: 260, mana: 120, moveSpeed: 0),
            ItemSpec(name: "Sanctuary Veil", cost: 1280, requiredLevel: levels[4], attack: 14, hp: 340, mana: 160, moveSpeed: 0),
            ItemSpec(name: "Radiant Oath", cost: 1620, requiredLevel: levels[5], attack: 22, hp: 460, mana: 220, moveSpeed: 6)
        ]
    }

    private var playerMaxHP: CGFloat {
        heroClass.maxHP + CGFloat(playerLevel - 1) * 58 + ownedItems.reduce(0) { $0 + $1.hp }
    }

    private var playerMaxMana: CGFloat {
        heroClass.maxMana + CGFloat(playerLevel - 1) * 22 + ownedItems.reduce(0) { $0 + $1.mana }
    }

    private var playerAttackDamage: CGFloat {
        heroClass.attackDamage * (1 + CGFloat(playerLevel - 1) * 0.055) + ownedItems.reduce(0) { $0 + $1.attack }
    }

    private var playerMoveSpeed: CGFloat {
        heroClass.moveSpeed + ownedItems.reduce(0) { $0 + $1.moveSpeed }
    }

    private func xpNeeded(for level: Int) -> Int {
        85 + max(0, level - 1) * 48
    }

    private func grantPlayerProgress(xp: Int, gold: Int) {
        playerGold += gold
        guard playerLevel < 15 else { return }
        playerXP += xp

        var leveled = false
        while playerLevel < 15 && playerXP >= xpNeeded(for: playerLevel) {
            playerXP -= xpNeeded(for: playerLevel)
            playerLevel += 1
            leveled = true
            playerHP = min(playerMaxHP, playerHP + 150)
            playerMana = min(playerMaxMana, playerMana + 80)
        }

        if leveled {
            let nextItem = recommendedItems().dropFirst(ownedItems.count).first
            if let nextItem, nextItem.requiredLevel == playerLevel {
                showMessage("LEVEL \(playerLevel) • \(nextItem.name) unlocked")
            } else {
                showMessage("LEVEL \(playerLevel)")
            }
        }
    }

    func basicAttack() {
        guard !gameOver, !player.isHidden else { return }
        let now = runtimeNow
        let cooldown: TimeInterval = now < attackBuffUntil ? 0.34 : (heroClass == .marksman ? 0.52 : 0.70)
        guard now - lastAttackTime >= cooldown else { return }
        lastAttackTime = now

        let teamBuff = now < blueTeamBuffUntil ? 1.16 : 1
        let damage = playerAttackDamage * (now < attackBuffUntil ? 1.25 : 1) * teamBuff

        if let bot = nearestBot(team: 1, from: player.position), distance(player.position, bot.node.position) <= heroClass.attackRange {
            performAttack(to: bot.node.position) { [weak self, weak bot] in
                guard let self, let bot else { return }
                self.damage(bot: bot, amount: damage, sourceTeam: 0)
            }
            return
        }

        if let minion = nearestMinion(team: 1, from: player.position), distance(player.position, minion.node.position) <= heroClass.attackRange {
            performAttack(to: minion.node.position) { [weak self, weak minion] in
                guard let self, let minion else { return }
                minion.hp -= damage
                self.cleanupMinions()
            }
            return
        }

        if let objective = nearestActiveObjective(from: player.position), distance(player.position, objective.node.position) <= heroClass.attackRange + 55 {
            performAttack(to: objective.node.position) { [weak self, weak objective] in
                guard let self, let objective else { return }
                self.damage(objective: objective, amount: damage, sourceTeam: 0)
            }
            return
        }

        if let tower = nearestTower(team: 1, from: player.position), distance(player.position, tower.node.position) <= heroClass.attackRange + 40 {
            performAttack(to: tower.node.position) { [weak self, weak tower] in
                guard let self, let tower else { return }
                self.damage(tower: tower, amount: damage, sourceTeam: 0)
            }
            return
        }

        if let camp = nearestCamp(from: player.position), distance(player.position, camp.node.position) <= heroClass.attackRange + 35 {
            performAttack(to: camp.node.position) { [weak self, weak camp] in
                guard let self, let camp else { return }
                camp.hp -= damage
                if camp.hp <= 0 { self.kill(camp: camp) }
            }
        }
    }

    func castSkill(_ index: Int) {
        guard !gameOver, !player.isHidden, heroClass.skills.indices.contains(index) else { return }
        let unlockLevels = [1, 2, 3, 4]
        guard playerLevel >= unlockLevels[index] else {
            showMessage("Skill \(index + 1) unlocks at Lv \(unlockLevels[index])")
            return
        }

        let now = runtimeNow
        let skill = heroClass.skills[index]
        if let last = skillLastUsed[index], now - last < skill.cooldown {
            showMessage("\(Int(ceil(skill.cooldown - (now - last))))s cooldown")
            return
        }
        guard playerMana >= skill.mana else {
            showMessage("Not enough mana")
            return
        }

        playerMana -= skill.mana
        skillLastUsed[index] = now
        let aim = aimDirection()
        let levelScale = 1 + CGFloat(playerLevel - 1) * 0.035

        switch heroClass {
        case .tank:
            if index == 0 { areaDamage(radius: 155, amount: 130 * levelScale) }
            else if index == 1 { dash(amount: 190, direction: aim); areaDamage(radius: 115, amount: 105 * levelScale) }
            else if index == 2 { shieldHP = min(780, shieldHP + 360 + CGFloat(playerLevel * 18)); ring(at: player.position, radius: 80) }
            else { areaDamage(radius: 270, amount: 250 * levelScale) }
        case .fighter:
            if index == 0 { areaDamage(radius: 145, amount: 165 * levelScale) }
            else if index == 1 { dash(amount: 170, direction: aim); areaDamage(radius: 110, amount: 130 * levelScale) }
            else if index == 2 { attackBuffUntil = now + 6; playerHP = min(playerMaxHP, playerHP + 140 + CGFloat(playerLevel * 8)) }
            else { areaDamage(radius: 220, amount: 350 * levelScale) }
        case .assassin:
            if index == 0 { dash(amount: 250, direction: aim); areaDamage(radius: 100, amount: 190 * levelScale) }
            else if index == 1 { lineDamage(range: 390, amount: 175 * levelScale) }
            else if index == 2 { stealthUntil = now + 3.2; player.alpha = 0.42; dash(amount: 150, direction: aim) }
            else { lineDamage(range: 430, amount: 390 * levelScale) }
        case .mage:
            if index == 0 { lineDamage(range: 520, amount: 165 * levelScale) }
            else if index == 1 { areaDamage(radius: 190, amount: 145 * levelScale) }
            else if index == 2 { dash(amount: 185, direction: aim) }
            else { areaDamage(radius: 330, amount: 410 * levelScale) }
        case .marksman:
            if index == 0 { lineDamage(range: 650, amount: 190 * levelScale) }
            else if index == 1 { dash(amount: 180, direction: aim) }
            else if index == 2 { attackBuffUntil = now + 6.5 }
            else { lineDamage(range: 760, amount: 380 * levelScale) }
        case .support:
            if index == 0 { playerHP = min(playerMaxHP, playerHP + 260 + CGFloat(playerLevel * 10)); ring(at: player.position, radius: 130) }
            else if index == 1 { lineDamage(range: 480, amount: 120 * levelScale) }
            else if index == 2 { shieldHP = min(760, shieldHP + 300 + CGFloat(playerLevel * 12)) }
            else {
                playerHP = min(playerMaxHP, playerHP + 420 + CGFloat(playerLevel * 14))
                shieldHP = min(900, shieldHP + 260 + CGFloat(playerLevel * 12))
                ring(at: player.position, radius: 280)
            }
        }
        updateHUD()
    }

    // MARK: - Main loop

    override func update(_ currentTime: TimeInterval) {
        guard didBootstrap else { return }
        sceneNow = currentTime
        if matchStartTime == 0 { matchStartTime = currentTime }
        matchElapsed = max(0, currentTime - matchStartTime)

        if lastFrameTime == 0 { lastFrameTime = currentTime }
        let dt = min(max(currentTime - lastFrameTime, 0), 1.0 / 20.0)
        lastFrameTime = currentTime

        if currentTime - lastWaveTime >= 11 {
            lastWaveTime = currentTime
            spawnWave()
        }

        updateObjectiveSpawns(now: currentTime)
        handleRespawns(now: currentTime)
        guard !gameOver else { return }

        playerMana = min(playerMaxMana, playerMana + CGFloat(dt) * (16 + CGFloat(playerLevel) * 0.5))
        if heroClass == .support { playerHP = min(playerMaxHP, playerHP + CGFloat(dt) * 3.2) }
        if currentTime >= stealthUntil && !isInGrass(player.position) { player.alpha = 1 }

        if !player.isHidden {
            player.position.x += movement.dx * playerMoveSpeed * CGFloat(dt)
            player.position.y += movement.dy * playerMoveSpeed * CGFloat(dt)
            player.position.x = min(max(player.position.x, 90), worldWidth - 90)
            player.position.y = min(max(player.position.y, 90), worldHeight - 90)
            if isInGrass(player.position) && currentTime >= stealthUntil { player.alpha = 0.72 }
        }

        updateBotLevels()
        updateMinions(now: currentTime, dt: dt)
        updateBots(now: currentTime, dt: dt)
        updateObjectives(now: currentTime)
        updateLordPushes(now: currentTime, dt: dt)
        updateTowers(now: currentTime)
        updateCameraPosition(immediate: false)
        cleanupMinions()

        if currentTime - lastMiniMapUpdate >= 0.15 {
            lastMiniMapUpdate = currentTime
            updateMiniMap()
        }
        updateHUD()
    }

    private var runtimeNow: TimeInterval {
        sceneNow > 0 ? sceneNow : CACurrentMediaTime()
    }

    private func spawnWave() {
        for lane in Lane.allCases {
            let path = lanePoints(lane)
            guard let blueStart = path.first, let redStart = path.last else { continue }

            for i in 0..<4 {
                let siege = i == 3 && Int(matchElapsed / 33).isMultiple(of: 2)
                let blue = MinionUnit(
                    team: 0,
                    lane: lane,
                    position: CGPoint(x: blueStart.x + CGFloat(i * 30), y: blueStart.y + CGFloat((i - 1) * 20)),
                    siege: siege
                )
                minions.append(blue)
                world.addChild(blue.node)

                let red = MinionUnit(
                    team: 1,
                    lane: lane,
                    position: CGPoint(x: redStart.x - CGFloat(i * 30), y: redStart.y + CGFloat((i - 1) * 20)),
                    siege: siege
                )
                minions.append(red)
                world.addChild(red.node)
            }
        }
    }

    private func updateBotLevels() {
        let targetLevel = min(15, 1 + Int(matchElapsed / 28))
        for bot in bots where bot.level < targetLevel {
            let oldMax = bot.maxHP
            bot.level = targetLevel
            bot.hp = min(bot.maxHP, bot.hp + max(0, bot.maxHP - oldMax) + 80)
        }
    }

    private func updateMinions(now: TimeInterval, dt: TimeInterval) {
        let active = minions.filter { $0.hp > 0 && $0.node.parent != nil }
        for minion in active {
            if let enemy = nearestMinion(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, enemy.node.position) < 58 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.9
                    enemy.hp -= 34
                    flash(at: enemy.node.position, color: minion.team == 0 ? .systemTeal : .systemRed)
                }
                continue
            }

            if let bot = nearestBot(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, bot.node.position) < 72 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 1
                    damage(bot: bot, amount: 29, sourceTeam: minion.team)
                }
                continue
            }

            if minion.team == 1 && !player.isHidden && canEnemySeePlayer(from: minion.node.position) && distance(minion.node.position, player.position) < 72 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 1
                    damagePlayer(amount: 29)
                }
                continue
            }

            if let tower = nearestTower(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, tower.node.position) < 80 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 1
                    damage(tower: tower, amount: 32, sourceTeam: minion.team)
                }
                continue
            }

            moveMinion(minion, dt: dt)
        }
    }

    private func moveMinion(_ minion: MinionUnit, dt: TimeInterval) {
        let original = lanePoints(minion.lane)
        let points = minion.team == 0 ? original : Array(original.reversed())
        guard points.count > 1 else { return }
        let nextIndex = min(minion.waypointIndex + 1, points.count - 1)
        let target = points[nextIndex]
        move(node: minion.node, toward: target, speed: 78, dt: dt)
        if distance(minion.node.position, target) < 28 && minion.waypointIndex < points.count - 2 {
            minion.waypointIndex += 1
        }
    }

    private func updateBots(now: TimeInterval, dt: TimeInterval) {
        for bot in bots where bot.respawnAt == nil && !bot.node.isHidden {
            let teamBuff = now < (bot.team == 0 ? blueTeamBuffUntil : redTeamBuffUntil) ? 1.16 : 1

            if bot.isJungler, let objective = objectiveForBot(bot), distance(bot.node.position, objective.node.position) < 900 {
                if distance(bot.node.position, objective.node.position) <= bot.attackRange + 55 {
                    if now >= bot.nextAttack {
                        bot.nextAttack = now + 0.72
                        damage(objective: objective, amount: bot.attackDamage * 1.15 * teamBuff, sourceTeam: bot.team)
                    }
                } else {
                    move(node: bot.node, toward: objective.node.position, speed: bot.moveSpeed, dt: dt)
                }
                continue
            }

            if let enemy = nearestBot(team: 1 - bot.team, from: bot.node.position, excluding: bot), distance(bot.node.position, enemy.node.position) < bot.attackRange + 45 {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + attackCooldown(for: bot.heroClass)
                    damage(bot: enemy, amount: bot.attackDamage * teamBuff, sourceTeam: bot.team)
                    if now >= bot.nextSkill {
                        bot.nextSkill = now + 7.5
                        damage(bot: enemy, amount: bot.attackDamage * 0.75, sourceTeam: bot.team)
                        ring(at: enemy.node.position, radius: 72, color: color(for: bot.heroClass))
                    }
                }
                continue
            }

            if bot.team == 1 && !player.isHidden && canEnemySeePlayer(from: bot.node.position) && distance(bot.node.position, player.position) < bot.attackRange + 60 {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + attackCooldown(for: bot.heroClass)
                    damagePlayer(amount: bot.attackDamage * teamBuff)
                    if now >= bot.nextSkill {
                        bot.nextSkill = now + 8
                        damagePlayer(amount: bot.attackDamage * 0.65)
                        ring(at: player.position, radius: 78, color: color(for: bot.heroClass))
                    }
                }
                continue
            }

            if let minion = nearestMinion(team: 1 - bot.team, from: bot.node.position), distance(bot.node.position, minion.node.position) < bot.attackRange + 35 {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + attackCooldown(for: bot.heroClass)
                    minion.hp -= bot.attackDamage * 0.82
                    bot.gold += 18
                }
                continue
            }

            if bot.isJungler, let camp = nearestCamp(from: bot.node.position), distance(bot.node.position, camp.node.position) < 620 {
                if distance(bot.node.position, camp.node.position) <= bot.attackRange + 45 {
                    if now >= bot.nextAttack {
                        bot.nextAttack = now + 0.78
                        camp.hp -= bot.attackDamage
                        if camp.hp <= 0 {
                            camp.hp = 0
                            camp.node.isHidden = true
                            camp.respawnAt = now + 24
                            bot.gold += camp.elite ? 90 : 55
                        }
                    }
                } else {
                    move(node: bot.node, toward: camp.node.position, speed: bot.moveSpeed, dt: dt)
                }
                continue
            }

            if let tower = nearestTower(team: 1 - bot.team, from: bot.node.position), distance(bot.node.position, tower.node.position) < bot.attackRange + 70,
               hasFriendlyMinion(team: bot.team, near: tower.node.position) {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + attackCooldown(for: bot.heroClass)
                    damage(tower: tower, amount: bot.attackDamage * 0.78 * teamBuff, sourceTeam: bot.team)
                }
                continue
            }

            let lanePath = lanePoints(bot.lane)
            let destination: CGPoint
            if bot.isJungler {
                destination = bot.team == 0 ? CGPoint(x: 1320, y: 770) : CGPoint(x: 1680, y: 1030)
            } else {
                destination = bot.team == 0 ? lanePath[4] : lanePath[2]
            }
            move(node: bot.node, toward: destination, speed: bot.moveSpeed, dt: dt)
        }
    }

    private func attackCooldown(for heroClass: HeroClass) -> TimeInterval {
        switch heroClass {
        case .marksman: return 0.58
        case .assassin: return 0.68
        case .fighter: return 0.75
        case .mage: return 0.88
        case .support: return 0.92
        case .tank: return 0.96
        }
    }

    private func updateObjectiveSpawns(now: TimeInterval) {
        for objective in objectives {
            if matchElapsed >= objective.spawnAt && objective.respawnAt == nil && objective.hp > 0 {
                objective.node.isHidden = false
            }
            if let respawn = objective.respawnAt, now >= respawn {
                objective.respawnAt = nil
                objective.hp = objective.maxHP
                objective.node.isHidden = false
                showMessage("\(objective.kind.rawValue) has returned")
            }
        }
    }

    private func updateObjectives(now: TimeInterval) {
        for objective in objectives where !objective.node.isHidden && objective.hp > 0 {
            guard now >= objective.nextAttack else { continue }

            if !player.isHidden && distance(objective.node.position, player.position) < 250 {
                objective.nextAttack = now + 1.1
                damagePlayer(amount: objective.kind == .lord ? 135 : 88)
                flash(at: player.position, color: objective.kind == .lord ? .systemPurple : .systemGreen)
                continue
            }

            if let bot = bots.filter({ $0.respawnAt == nil && !$0.node.isHidden }).min(by: { distance(objective.node.position, $0.node.position) < distance(objective.node.position, $1.node.position) }), distance(objective.node.position, bot.node.position) < 250 {
                objective.nextAttack = now + 1.1
                damage(bot: bot, amount: objective.kind == .lord ? 125 : 82, sourceTeam: -1)
            }
        }
    }

    private func updateLordPushes(now: TimeInterval, dt: TimeInterval) {
        for summon in lordPushes where summon.hp > 0 && summon.node.parent != nil {
            if let tower = nearestTower(team: 1 - summon.team, from: summon.node.position) {
                if distance(summon.node.position, tower.node.position) < 145 {
                    if now >= summon.nextAttack {
                        summon.nextAttack = now + 0.9
                        damage(tower: tower, amount: 210, sourceTeam: summon.team)
                        ring(at: tower.node.position, radius: 92, color: .systemIndigo)
                    }
                } else {
                    move(node: summon.node, toward: tower.node.position, speed: 95, dt: dt)
                }
            }
        }
    }

    private func updateTowers(now: TimeInterval) {
        for tower in towers where tower.hp > 0 && tower.node.parent != nil {
            guard now >= tower.nextAttack else { continue }

            if let minion = nearestMinion(team: 1 - tower.team, from: tower.node.position), distance(tower.node.position, minion.node.position) <= 292 {
                tower.nextAttack = now + 0.95
                minion.hp -= tower.tier == 0 ? 150 : 108
                beam(from: tower.node.position, to: minion.node.position, color: tower.team == 0 ? .systemCyan : .systemPink)
                continue
            }

            if let summon = lordPushes.first(where: { $0.team != tower.team && $0.hp > 0 && $0.node.parent != nil && distance(tower.node.position, $0.node.position) <= 292 }) {
                tower.nextAttack = now + 0.95
                summon.hp -= tower.tier == 0 ? 180 : 130
                beam(from: tower.node.position, to: summon.node.position, color: tower.team == 0 ? .systemCyan : .systemPink)
                if summon.hp <= 0 { summon.node.removeFromParent() }
                continue
            }

            if let bot = nearestBot(team: 1 - tower.team, from: tower.node.position), distance(tower.node.position, bot.node.position) <= 292 {
                tower.nextAttack = now + 1
                damage(bot: bot, amount: tower.tier == 0 ? 170 : 120, sourceTeam: tower.team)
                beam(from: tower.node.position, to: bot.node.position, color: tower.team == 0 ? .systemCyan : .systemPink)
                continue
            }

            if tower.team == 1 && !player.isHidden && canEnemySeePlayer(from: tower.node.position) && distance(tower.node.position, player.position) <= 292 {
                tower.nextAttack = now + 1
                damagePlayer(amount: tower.tier == 0 ? 175 : 124)
                beam(from: tower.node.position, to: player.position, color: .systemPink)
            }
        }
    }

    private func handleRespawns(now: TimeInterval) {
        if let respawn = playerRespawnAt, now >= respawn {
            playerRespawnAt = nil
            player.isHidden = false
            player.alpha = 1
            playerHP = playerMaxHP
            playerMana = playerMaxMana
            player.position = CGPoint(x: 330, y: 900)
            showMessage("Respawned")
        }

        for bot in bots {
            if let respawn = bot.respawnAt, now >= respawn {
                bot.respawnAt = nil
                bot.hp = bot.maxHP
                bot.node.isHidden = false
                bot.node.alpha = 1
                bot.node.position = botSpawn(team: bot.team, lane: bot.lane, offset: 0)
            }
        }

        for camp in camps {
            if let respawn = camp.respawnAt, now >= respawn {
                camp.respawnAt = nil
                camp.hp = camp.maxHP
                camp.node.isHidden = false
            }
        }
    }

    // MARK: - Combat and objectives

    private func damagePlayer(amount: CGFloat) {
        var remaining = amount
        if shieldHP > 0 {
            let absorbed = min(shieldHP, remaining)
            shieldHP -= absorbed
            remaining -= absorbed
        }
        playerHP -= remaining
        flash(at: player.position, color: .systemRed)

        if playerHP <= 0 && playerRespawnAt == nil {
            playerHP = 0
            redKills += 1
            player.isHidden = true
            let respawnSeconds = min(28, 6 + playerLevel)
            playerRespawnAt = runtimeNow + TimeInterval(respawnSeconds)
            showMessage("Defeated • respawn in \(respawnSeconds)s")
        }
    }

    private func damage(bot: BotUnit, amount: CGFloat, sourceTeam: Int) {
        guard bot.respawnAt == nil else { return }
        bot.hp -= amount
        flash(at: bot.node.position, color: .white)

        if bot.hp <= 0 {
            bot.hp = 0
            bot.node.isHidden = true
            bot.respawnAt = runtimeNow + TimeInterval(min(28, 7 + bot.level))
            if bot.team == 1 { blueKills += 1 } else { redKills += 1 }
            if bot.team == 1 && sourceTeam == 0 {
                grantPlayerProgress(xp: 120, gold: 145)
            }
        }
    }

    private func damage(tower: TowerUnit, amount: CGFloat, sourceTeam: Int) {
        guard tower.hp > 0 else { return }
        guard isTowerVulnerable(tower) else {
            if sourceTeam == 0 { showMessage("Destroy the outer tower first") }
            return
        }
        tower.hp -= amount
        tower.node.alpha = max(0.25, tower.hp / tower.maxHP)
        flash(at: tower.node.position, color: .systemYellow)

        if tower.hp <= 0 {
            tower.hp = 0
            tower.node.removeAllActions()
            tower.node.run(.sequence([.fadeOut(withDuration: 0.22), .removeFromParent()]))
            if sourceTeam == 0 { grantPlayerProgress(xp: 90, gold: 120) }
            if tower.tier == 0 {
                gameOver = true
                showMessage(tower.team == 1 ? "VICTORY" : "DEFEAT")
            }
        }
    }

    private func isTowerVulnerable(_ tower: TowerUnit) -> Bool {
        if tower.tier == 0 {
            return towers.contains { $0.team == tower.team && $0.tier == 1 && $0.hp <= 0 }
        }
        guard let lane = tower.lane else { return true }
        if tower.tier == 3 { return true }
        let requiredTier = tower.tier + 1
        return towers.contains { $0.team == tower.team && $0.lane == lane && $0.tier == requiredTier && $0.hp <= 0 }
    }

    private func damage(objective: ObjectiveUnit, amount: CGFloat, sourceTeam: Int) {
        guard !objective.node.isHidden, objective.hp > 0 else { return }
        objective.hp -= amount
        objective.node.alpha = max(0.35, objective.hp / objective.maxHP)
        flash(at: objective.node.position, color: objective.kind == .turtle ? .systemGreen : .systemPurple)

        if objective.hp <= 0 {
            objective.hp = 0
            objective.node.isHidden = true
            objective.node.alpha = 1
            objective.respawnAt = runtimeNow + objective.respawnDelay
            awardObjective(objective.kind, team: sourceTeam == 1 ? 1 : 0)
        }
    }

    private func awardObjective(_ kind: ObjectiveKind, team: Int) {
        if kind == .turtle {
            if team == 0 {
                shieldHP = min(1100, shieldHP + 420 + CGFloat(playerLevel * 18))
                grantPlayerProgress(xp: 150, gold: 180)
                blueTeamBuffUntil = max(blueTeamBuffUntil, runtimeNow + 55)
            } else {
                redTeamBuffUntil = max(redTeamBuffUntil, runtimeNow + 55)
            }
            showMessage("\(team == 0 ? "Allies" : "Enemies") secured TURTLE")
        } else {
            if team == 0 {
                grantPlayerProgress(xp: 260, gold: 280)
                blueTeamBuffUntil = max(blueTeamBuffUntil, runtimeNow + 90)
            } else {
                redTeamBuffUntil = max(redTeamBuffUntil, runtimeNow + 90)
            }
            spawnLordPush(team: team)
            showMessage("\(team == 0 ? "Allies" : "Enemies") secured LORD")
        }
    }

    private func spawnLordPush(team: Int) {
        let spawn = CGPoint(x: team == 0 ? 320 : worldWidth - 320, y: 900)
        let lord = LordPushUnit(team: team, position: spawn)
        lordPushes.append(lord)
        world.addChild(lord.node)
    }

    private func kill(camp: CampUnit) {
        camp.hp = 0
        camp.node.isHidden = true
        camp.respawnAt = runtimeNow + 24
        let xp = camp.elite ? 88 : 52
        let gold = camp.elite ? 96 : 58
        grantPlayerProgress(xp: xp, gold: gold)
        playerHP = min(playerMaxHP, playerHP + (camp.elite ? 130 : 75))
        attackBuffUntil = max(attackBuffUntil, runtimeNow + (camp.elite ? 10 : 6))
        showMessage(camp.elite ? "Major jungle buff" : "Jungle buff")
    }

    private func cleanupMinions() {
        for minion in minions where minion.hp <= 0 && minion.node.parent != nil {
            if !minion.rewarded && minion.team == 1 && distance(player.position, minion.node.position) <= 520 {
                minion.rewarded = true
                grantPlayerProgress(xp: minion.maxHP > 300 ? 42 : 28, gold: minion.maxHP > 300 ? 42 : 24)
            }
            minion.node.removeFromParent()
        }
        minions.removeAll { $0.hp <= 0 && $0.node.parent == nil }
    }

    private func areaDamage(radius: CGFloat, amount: CGFloat) {
        ring(at: player.position, radius: radius)
        for minion in minions where minion.team == 1 && minion.hp > 0 && distance(player.position, minion.node.position) <= radius {
            minion.hp -= amount
        }
        for bot in bots where bot.team == 1 && bot.respawnAt == nil && distance(player.position, bot.node.position) <= radius {
            damage(bot: bot, amount: amount, sourceTeam: 0)
        }
        for camp in camps where camp.respawnAt == nil && distance(player.position, camp.node.position) <= radius {
            camp.hp -= amount
            if camp.hp <= 0 { kill(camp: camp) }
        }
        for objective in objectives where !objective.node.isHidden && objective.hp > 0 && distance(player.position, objective.node.position) <= radius {
            damage(objective: objective, amount: amount * 0.72, sourceTeam: 0)
        }
        cleanupMinions()
    }

    private func lineDamage(range: CGFloat, amount: CGFloat) {
        let direction = aimDirection()
        let end = CGPoint(x: player.position.x + direction.dx * range, y: player.position.y + direction.dy * range)
        beam(from: player.position, to: end, color: color(for: heroClass))

        for bot in bots where bot.team == 1 && bot.respawnAt == nil {
            if distancePointToSegment(bot.node.position, player.position, end) < 74 && distance(player.position, bot.node.position) <= range {
                damage(bot: bot, amount: amount, sourceTeam: 0)
            }
        }
        for minion in minions where minion.team == 1 && minion.hp > 0 {
            if distancePointToSegment(minion.node.position, player.position, end) < 42 && distance(player.position, minion.node.position) <= range {
                minion.hp -= amount * 0.72
            }
        }
        for objective in objectives where !objective.node.isHidden && objective.hp > 0 {
            if distancePointToSegment(objective.node.position, player.position, end) < 80 && distance(player.position, objective.node.position) <= range {
                damage(objective: objective, amount: amount * 0.58, sourceTeam: 0)
            }
        }
        cleanupMinions()
    }

    // MARK: - Helpers

    private func dash(amount: CGFloat, direction: CGVector) {
        player.position.x = min(max(player.position.x + direction.dx * amount, 90), worldWidth - 90)
        player.position.y = min(max(player.position.y + direction.dy * amount, 90), worldHeight - 90)
        flash(at: player.position, color: color(for: heroClass))
    }

    private func performAttack(to point: CGPoint, completion: @escaping () -> Void) {
        if heroClass.attackRange > 150 {
            let projectile = SKShapeNode(circleOfRadius: 6)
            projectile.position = player.position
            projectile.fillColor = color(for: heroClass)
            projectile.strokeColor = .white
            projectile.zPosition = 30
            world.addChild(projectile)
            let duration = max(0.08, Double(distance(player.position, point) / 900))
            projectile.run(.sequence([.move(to: point, duration: duration), .run(completion), .removeFromParent()]))
        } else {
            flash(at: point, color: color(for: heroClass))
            completion()
        }
    }

    private func beam(from: CGPoint, to: CGPoint, color: SKColor) {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        let line = SKShapeNode(path: path)
        line.strokeColor = color
        line.lineWidth = 5
        line.glowWidth = 3
        line.zPosition = 28
        world.addChild(line)
        line.run(.sequence([.fadeOut(withDuration: 0.16), .removeFromParent()]))
    }

    private func ring(at point: CGPoint, radius: CGFloat, color: SKColor? = nil) {
        let drawColor = color ?? self.color(for: heroClass)
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = point
        node.fillColor = drawColor.withAlphaComponent(0.10)
        node.strokeColor = drawColor.withAlphaComponent(0.85)
        node.lineWidth = 4
        node.zPosition = 26
        node.setScale(0.25)
        world.addChild(node)
        node.run(.sequence([.group([.scale(to: 1, duration: 0.18), .fadeOut(withDuration: 0.28)]), .removeFromParent()]))
    }

    private func flash(at point: CGPoint, color: SKColor) {
        let node = SKShapeNode(circleOfRadius: 17)
        node.position = point
        node.fillColor = color
        node.strokeColor = .clear
        node.zPosition = 35
        world.addChild(node)
        node.run(.sequence([.scale(to: 1.7, duration: 0.09), .fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    private func updateCameraPosition(immediate: Bool) {
        guard gameCamera.parent != nil, !player.isHidden else { return }
        let halfW = max(280, size.width / 2)
        let halfH = max(170, size.height / 2)
        let target = CGPoint(
            x: min(max(player.position.x, halfW), worldWidth - halfW),
            y: min(max(player.position.y, halfH), worldHeight - halfH)
        )
        if immediate {
            gameCamera.position = target
        } else {
            gameCamera.position.x += (target.x - gameCamera.position.x) * 0.14
            gameCamera.position.y += (target.y - gameCamera.position.y) * 0.14
        }
    }

    private func updateHUD() {
        hpBar.xScale = max(0, min(1, playerHP / max(1, playerMaxHP)))
        manaBar.xScale = max(0, min(1, playerMana / max(1, playerMaxMana)))

        let minutes = Int(matchElapsed) / 60
        let seconds = Int(matchElapsed) % 60
        scoreLabel.text = String(format: "%02d:%02d   %d  •  %d", minutes, seconds, blueKills, redKills)

        let xpText: String
        if playerLevel >= 15 {
            xpText = "MAX"
        } else {
            xpText = "\(playerXP)/\(xpNeeded(for: playerLevel)) XP"
        }
        statusLabel.text = "Lv \(playerLevel)  \(xpText)  •  \(playerGold)g  •  Items \(ownedItems.count)/6"

        let turtle = objectives.first { $0.kind == .turtle }
        let lord = objectives.first { $0.kind == .lord }
        let turtleText = objectiveStateText(turtle)
        let lordText = objectiveStateText(lord)
        objectiveLabel.text = "T \(turtleText)   L \(lordText)   •   \(laneName())"
    }

    private func objectiveStateText(_ objective: ObjectiveUnit?) -> String {
        guard let objective else { return "--" }
        if !objective.node.isHidden && objective.hp > 0 { return "UP" }
        if matchElapsed < objective.spawnAt { return "\(max(0, Int(objective.spawnAt - matchElapsed)))s" }
        if let respawn = objective.respawnAt { return "\(max(0, Int(respawn - runtimeNow)))s" }
        return "--"
    }

    private func laneName() -> String {
        if isInGrass(player.position) { return "GRASS" }
        if player.position.y > 1180 { return "TOP" }
        if player.position.y < 620 { return "BOTTOM" }
        if abs(player.position.y - 900) < 210 { return "MID" }
        return "JUNGLE"
    }

    private func showMessage(_ text: String) {
        guard messageLabel.parent != nil else { return }
        messageLabel.removeAllActions()
        messageLabel.text = text
        messageLabel.alpha = 1
        messageLabel.run(.sequence([.wait(forDuration: 1.45), .fadeOut(withDuration: 0.25)]))
    }

    private func color(for heroClass: HeroClass) -> SKColor {
        switch heroClass {
        case .tank: return .systemCyan
        case .fighter: return .systemOrange
        case .assassin: return .systemPurple
        case .mage: return .systemIndigo
        case .marksman: return .systemYellow
        case .support: return .systemGreen
        }
    }

    private func aimDirection() -> CGVector {
        let magnitude = sqrt(movement.dx * movement.dx + movement.dy * movement.dy)
        if magnitude > 0.18 {
            return CGVector(dx: movement.dx / magnitude, dy: movement.dy / magnitude)
        }
        if let bot = nearestBot(team: 1, from: player.position) {
            let dx = bot.node.position.x - player.position.x
            let dy = bot.node.position.y - player.position.y
            let length = max(1, sqrt(dx * dx + dy * dy))
            return CGVector(dx: dx / length, dy: dy / length)
        }
        return CGVector(dx: 1, dy: 0)
    }

    private func nearestMinion(team: Int, from point: CGPoint) -> MinionUnit? {
        minions
            .filter { $0.team == team && $0.hp > 0 && $0.node.parent != nil }
            .min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func nearestBot(team: Int, from point: CGPoint, excluding: BotUnit? = nil) -> BotUnit? {
        bots
            .filter { $0.team == team && $0.respawnAt == nil && !$0.node.isHidden && $0 !== excluding }
            .min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func nearestTower(team: Int, from point: CGPoint) -> TowerUnit? {
        towers
            .filter { $0.team == team && $0.hp > 0 && $0.node.parent != nil && isTowerVulnerable($0) }
            .min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func nearestCamp(from point: CGPoint) -> CampUnit? {
        camps
            .filter { $0.respawnAt == nil && !$0.node.isHidden && $0.hp > 0 }
            .min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func nearestActiveObjective(from point: CGPoint) -> ObjectiveUnit? {
        objectives
            .filter { !$0.node.isHidden && $0.hp > 0 }
            .min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func objectiveForBot(_ bot: BotUnit) -> ObjectiveUnit? {
        let active = objectives.filter { !$0.node.isHidden && $0.hp > 0 }
        if let lord = active.first(where: { $0.kind == .lord }), matchElapsed >= 90 { return lord }
        return active.first(where: { $0.kind == .turtle })
    }

    private func hasFriendlyMinion(team: Int, near point: CGPoint) -> Bool {
        minions.contains { $0.team == team && $0.hp > 0 && $0.node.parent != nil && distance($0.node.position, point) < 300 }
    }

    private func botSpawn(team: Int, lane: Lane, offset: CGFloat) -> CGPoint {
        let points = lanePoints(lane)
        let point = team == 0 ? points[1] : points[5]
        return CGPoint(x: point.x + (team == 0 ? offset : -offset), y: point.y + offset * 0.2)
    }

    private func isInGrass(_ point: CGPoint) -> Bool {
        grassCenters.contains { distance(point, $0) < 72 }
    }

    private func canEnemySeePlayer(from point: CGPoint) -> Bool {
        if runtimeNow < stealthUntil { return distance(point, player.position) < 110 }
        if isInGrass(player.position) { return distance(point, player.position) < 125 }
        return true
    }

    private func move(node: SKNode, toward point: CGPoint, speed: CGFloat, dt: TimeInterval) {
        let dx = point.x - node.position.x
        let dy = point.y - node.position.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        node.position.x += dx / length * speed * CGFloat(dt)
        node.position.y += dy / length * speed * CGFloat(dt)
    }

    private func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let denominator = max(0.0001, abx * abx + aby * aby)
        let t = min(1, max(0, (apx * abx + apy * aby) / denominator))
        let closest = CGPoint(x: a.x + abx * t, y: a.y + aby * t)
        return distance(p, closest)
    }
}
