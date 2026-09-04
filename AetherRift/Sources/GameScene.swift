import SpriteKit
import Foundation

private enum Lane: CaseIterable {
    case top, mid, bottom

    var y: CGFloat {
        switch self {
        case .top: return 1460
        case .mid: return 900
        case .bottom: return 340
        }
    }
}

private final class LaneMinion {
    let node: SKShapeNode
    let team: Int
    let lane: Lane
    var hp: CGFloat = 250
    var nextAttack: TimeInterval = 0
    var waypointIndex = 0

    init(team: Int, lane: Lane, position: CGPoint) {
        self.team = team
        self.lane = lane
        node = SKShapeNode(circleOfRadius: 15)
        node.fillColor = team == 0 ? .systemTeal : .systemRed
        node.strokeColor = .white.withAlphaComponent(0.55)
        node.lineWidth = 1.5
        node.position = position
        node.zPosition = 6
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
        self.maxHP = tier == 0 ? 3600 : (1900 + CGFloat(3 - tier) * 220)
        self.hp = maxHP
        node = SKShapeNode(rectOf: CGSize(width: tier == 0 ? 82 : 56, height: tier == 0 ? 82 : 90), cornerRadius: 14)
        node.fillColor = team == 0 ? .systemCyan : .systemPink
        node.strokeColor = .white.withAlphaComponent(0.65)
        node.lineWidth = 2
        node.position = position
        node.zPosition = 7
    }
}

private final class BotHero {
    let node = SKShapeNode(circleOfRadius: 24)
    let team: Int
    let lane: Lane
    let maxHP: CGFloat = 1180
    var hp: CGFloat = 1180
    var nextAttack: TimeInterval = 0
    var respawnAt: TimeInterval?

    init(team: Int, lane: Lane, position: CGPoint, index: Int) {
        self.team = team
        self.lane = lane
        node.fillColor = team == 0 ? .systemBlue : .systemRed
        node.strokeColor = .white
        node.lineWidth = 2
        node.position = position
        node.zPosition = 10

        let core = SKShapeNode(circleOfRadius: 8)
        core.fillColor = index % 2 == 0 ? .white : .systemYellow
        core.strokeColor = .clear
        node.addChild(core)
    }
}

private final class JungleCamp {
    let node = SKShapeNode(circleOfRadius: 27)
    var hp: CGFloat = 900
    let maxHP: CGFloat = 900
    var respawnAt: TimeInterval?

    init(position: CGPoint, elite: Bool) {
        node.position = position
        node.fillColor = elite ? .systemPurple : .systemGreen
        node.strokeColor = .white.withAlphaComponent(0.5)
        node.lineWidth = 2
        node.zPosition = 5
    }
}

final class GameScene: SKScene {
    private let heroClass: HeroClass

    private let worldWidth: CGFloat = 3000
    private let worldHeight: CGFloat = 1800
    private let worldRoot = SKNode()
    private let gameCamera = SKCameraNode()

    private let player = SKShapeNode(circleOfRadius: 27)
    private var minions: [LaneMinion] = []
    private var towers: [TowerUnit] = []
    private var bots: [BotHero] = []
    private var jungleCamps: [JungleCamp] = []

    private var movement = CGVector.zero
    private var lastFrameTime: TimeInterval = 0
    private var lastWaveTime: TimeInterval = -99
    private var lastAttackTime: TimeInterval = -99
    private var skillLastUsed: [Int: TimeInterval] = [:]
    private var playerRespawnAt: TimeInterval?
    private var playerHP: CGFloat = 1
    private var playerMana: CGFloat = 1
    private var shieldHP: CGFloat = 0
    private var attackBuffUntil: TimeInterval = 0
    private var stealthUntil: TimeInterval = 0
    private var blueKills = 0
    private var redKills = 0
    private var gameOver = false

    private let hpBar = SKSpriteNode(color: .systemGreen, size: CGSize(width: 210, height: 11))
    private let manaBar = SKSpriteNode(color: .systemBlue, size: CGSize(width: 210, height: 7))
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let laneLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let messageLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    init(size: CGSize, heroClass: HeroClass) {
        self.heroClass = heroClass
        super.init(size: size)
        scaleMode = .aspectFill
        backgroundColor = .black
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        restartMatch()
    }

    func restartMatch() {
        removeAllActions()
        removeAllChildren()
        worldRoot.removeAllChildren()
        minions.removeAll()
        towers.removeAll()
        bots.removeAll()
        jungleCamps.removeAll()
        movement = .zero
        lastFrameTime = 0
        lastWaveTime = -99
        lastAttackTime = -99
        skillLastUsed.removeAll()
        playerRespawnAt = nil
        playerHP = heroClass.maxHP
        playerMana = heroClass.maxMana
        shieldHP = 0
        attackBuffUntil = 0
        stealthUntil = 0
        blueKills = 0
        redKills = 0
        gameOver = false

        addChild(worldRoot)
        setupMap()
        setupStructures()
        setupPlayer()
        setupBots()
        setupJungle()
        setupCameraHUD()
        spawnWave()
    }

    private func setupMap() {
        let ground = SKSpriteNode(color: SKColor(red: 0.045, green: 0.16, blue: 0.10, alpha: 1), size: CGSize(width: worldWidth, height: worldHeight))
        ground.anchorPoint = .zero
        ground.position = .zero
        ground.zPosition = -20
        worldRoot.addChild(ground)

        let river = SKShapeNode(rectOf: CGSize(width: 175, height: worldHeight + 100), cornerRadius: 50)
        river.position = CGPoint(x: worldWidth / 2, y: worldHeight / 2)
        river.fillColor = SKColor(red: 0.05, green: 0.32, blue: 0.42, alpha: 0.82)
        river.strokeColor = .white.withAlphaComponent(0.06)
        river.lineWidth = 4
        river.zPosition = -15
        worldRoot.addChild(river)

        for lane in Lane.allCases {
            let path = CGMutablePath()
            let points = lanePoints(lane)
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }

            let laneNode = SKShapeNode(path: path)
            laneNode.lineWidth = 145
            laneNode.strokeColor = SKColor(red: 0.22, green: 0.23, blue: 0.18, alpha: 1)
            laneNode.lineCap = .round
            laneNode.lineJoin = .round
            laneNode.zPosition = -12
            worldRoot.addChild(laneNode)

            let edge = SKShapeNode(path: path)
            edge.lineWidth = 151
            edge.strokeColor = .white.withAlphaComponent(0.05)
            edge.lineCap = .round
            edge.lineJoin = .round
            edge.zPosition = -13
            worldRoot.addChild(edge)
        }

        for x in stride(from: CGFloat(520), through: worldWidth - 520, by: 300) {
            for y in [CGFloat(610), CGFloat(1180)] {
                let bush = SKShapeNode(ellipseOf: CGSize(width: 110, height: 75))
                bush.fillColor = SKColor(red: 0.04, green: 0.27, blue: 0.08, alpha: 0.95)
                bush.strokeColor = .clear
                bush.position = CGPoint(x: x + (Int(x) % 2 == 0 ? 40 : -40), y: y)
                bush.zPosition = -5
                worldRoot.addChild(bush)
            }
        }

        for p in [CGPoint(x: 1180, y: 900), CGPoint(x: 1820, y: 900), CGPoint(x: 1500, y: 620), CGPoint(x: 1500, y: 1180)] {
            let bridge = SKShapeNode(rectOf: CGSize(width: 160, height: 58), cornerRadius: 20)
            bridge.fillColor = SKColor(red: 0.28, green: 0.25, blue: 0.19, alpha: 1)
            bridge.strokeColor = .white.withAlphaComponent(0.08)
            bridge.position = p
            bridge.zPosition = -7
            worldRoot.addChild(bridge)
        }

        let blueBase = SKShapeNode(circleOfRadius: 150)
        blueBase.position = CGPoint(x: 190, y: 900)
        blueBase.fillColor = .systemBlue.withAlphaComponent(0.18)
        blueBase.strokeColor = .systemCyan.withAlphaComponent(0.5)
        blueBase.lineWidth = 5
        blueBase.zPosition = -4
        worldRoot.addChild(blueBase)

        let redBase = SKShapeNode(circleOfRadius: 150)
        redBase.position = CGPoint(x: worldWidth - 190, y: 900)
        redBase.fillColor = .systemRed.withAlphaComponent(0.18)
        redBase.strokeColor = .systemPink.withAlphaComponent(0.5)
        redBase.lineWidth = 5
        redBase.zPosition = -4
        worldRoot.addChild(redBase)
    }

    private func lanePoints(_ lane: Lane) -> [CGPoint] {
        switch lane {
        case .top:
            return [
                CGPoint(x: 250, y: 900), CGPoint(x: 430, y: 1320), CGPoint(x: 780, y: 1460),
                CGPoint(x: 1500, y: 1460), CGPoint(x: 2220, y: 1460), CGPoint(x: 2570, y: 1320), CGPoint(x: 2750, y: 900)
            ]
        case .mid:
            return [CGPoint(x: 250, y: 900), CGPoint(x: 1500, y: 900), CGPoint(x: 2750, y: 900)]
        case .bottom:
            return [
                CGPoint(x: 250, y: 900), CGPoint(x: 430, y: 480), CGPoint(x: 780, y: 340),
                CGPoint(x: 1500, y: 340), CGPoint(x: 2220, y: 340), CGPoint(x: 2570, y: 480), CGPoint(x: 2750, y: 900)
            ]
        }
    }

    private func setupStructures() {
        for lane in Lane.allCases {
            let points = lanePoints(lane)
            let bluePositions = [points[1], points[2], interpolate(points[2], points[3], 0.48)]
            let redPositions = [points[points.count - 2], points[points.count - 3], interpolate(points[points.count - 3], points[points.count - 4], 0.48)]

            for (index, p) in bluePositions.enumerated() {
                let tower = TowerUnit(team: 0, lane: lane, tier: index + 1, position: p)
                towers.append(tower)
                worldRoot.addChild(tower.node)
            }
            for (index, p) in redPositions.enumerated() {
                let tower = TowerUnit(team: 1, lane: lane, tier: index + 1, position: p)
                towers.append(tower)
                worldRoot.addChild(tower.node)
            }
        }

        let blueCore = TowerUnit(team: 0, lane: nil, tier: 0, position: CGPoint(x: 180, y: 900))
        let redCore = TowerUnit(team: 1, lane: nil, tier: 0, position: CGPoint(x: worldWidth - 180, y: 900))
        towers.append(contentsOf: [blueCore, redCore])
        worldRoot.addChild(blueCore.node)
        worldRoot.addChild(redCore.node)
    }

    private func setupPlayer() {
        player.removeAllChildren()
        player.fillColor = playerColor()
        player.strokeColor = .white
        player.lineWidth = 3
        player.position = CGPoint(x: 330, y: 900)
        player.zPosition = 15
        player.alpha = 1
        player.isHidden = false
        worldRoot.addChild(player)

        let core = SKShapeNode(circleOfRadius: 10)
        core.fillColor = .white
        core.strokeColor = .clear
        player.addChild(core)
    }

    private func setupBots() {
        let allyLanes: [Lane] = [.top, .mid, .bottom, .bottom]
        let enemyLanes: [Lane] = [.top, .top, .mid, .bottom, .bottom]

        for (i, lane) in allyLanes.enumerated() {
            let bot = BotHero(team: 0, lane: lane, position: spawnPosition(team: 0, lane: lane, offset: CGFloat(i * 38)), index: i)
            bots.append(bot)
            worldRoot.addChild(bot.node)
        }
        for (i, lane) in enemyLanes.enumerated() {
            let bot = BotHero(team: 1, lane: lane, position: spawnPosition(team: 1, lane: lane, offset: CGFloat(i * 38)), index: i)
            bots.append(bot)
            worldRoot.addChild(bot.node)
        }
    }

    private func setupJungle() {
        let positions: [(CGPoint, Bool)] = [
            (CGPoint(x: 940, y: 650), false), (CGPoint(x: 1050, y: 1160), true),
            (CGPoint(x: 1320, y: 650), false), (CGPoint(x: 1680, y: 1150), false),
            (CGPoint(x: 1950, y: 640), true), (CGPoint(x: 2070, y: 1160), false)
        ]
        for item in positions {
            let camp = JungleCamp(position: item.0, elite: item.1)
            jungleCamps.append(camp)
            worldRoot.addChild(camp.node)
        }
    }

    private func setupCameraHUD() {
        camera = gameCamera
        addChild(gameCamera)
        gameCamera.position = player.position
        gameCamera.setScale(0.95)

        let hpBack = SKSpriteNode(color: .black.withAlphaComponent(0.55), size: CGSize(width: 214, height: 15))
        hpBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpBack.position = CGPoint(x: -440, y: 180)
        hpBack.zPosition = 100
        gameCamera.addChild(hpBack)

        hpBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpBar.position = CGPoint(x: -438, y: 180)
        hpBar.zPosition = 101
        gameCamera.addChild(hpBar)

        let manaBack = SKSpriteNode(color: .black.withAlphaComponent(0.55), size: CGSize(width: 214, height: 11))
        manaBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        manaBack.position = CGPoint(x: -440, y: 162)
        manaBack.zPosition = 100
        gameCamera.addChild(manaBack)

        manaBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        manaBar.position = CGPoint(x: -438, y: 162)
        manaBar.zPosition = 101
        gameCamera.addChild(manaBar)

        scoreLabel.fontSize = 18
        scoreLabel.position = CGPoint(x: 0, y: 178)
        scoreLabel.zPosition = 101
        gameCamera.addChild(scoreLabel)

        laneLabel.fontSize = 13
        laneLabel.horizontalAlignmentMode = .right
        laneLabel.position = CGPoint(x: 438, y: 176)
        laneLabel.zPosition = 101
        gameCamera.addChild(laneLabel)

        messageLabel.fontSize = 16
        messageLabel.position = CGPoint(x: 0, y: -150)
        messageLabel.alpha = 0
        messageLabel.zPosition = 101
        gameCamera.addChild(messageLabel)

        let mini = SKShapeNode(rectOf: CGSize(width: 150, height: 90), cornerRadius: 8)
        mini.fillColor = .black.withAlphaComponent(0.42)
        mini.strokeColor = .white.withAlphaComponent(0.25)
        mini.lineWidth = 1
        mini.position = CGPoint(x: 350, y: 118)
        mini.zPosition = 100
        gameCamera.addChild(mini)

        for y in [-22.0, 0.0, 22.0] {
            let line = SKShapeNode(rectOf: CGSize(width: 120, height: 4), cornerRadius: 2)
            line.fillColor = .white.withAlphaComponent(0.18)
            line.strokeColor = .clear
            line.position = CGPoint(x: 0, y: y)
            mini.addChild(line)
        }

        updateHUD()
    }

    func setMovement(_ vector: CGVector) {
        movement = vector
    }

    func basicAttack() {
        guard !gameOver, !player.isHidden else { return }
        let now = CACurrentMediaTime()
        let cd: TimeInterval = now < attackBuffUntil ? 0.36 : (heroClass == .marksman ? 0.55 : 0.72)
        guard now - lastAttackTime >= cd else { return }
        lastAttackTime = now
        let damage = heroClass.attackDamage * (now < attackBuffUntil ? 1.25 : 1)

        if let minion = nearestMinion(team: 1, from: player.position), distance(player.position, minion.node.position) <= heroClass.attackRange {
            attackVisual(to: minion.node.position) { [weak self, weak minion] in
                guard let self, let minion else { return }
                minion.hp -= damage
                self.cleanupDeadUnits()
            }
            return
        }

        if let bot = nearestBot(team: 1, from: player.position), distance(player.position, bot.node.position) <= heroClass.attackRange {
            attackVisual(to: bot.node.position) { [weak self, weak bot] in
                guard let self, let bot else { return }
                self.damageBot(bot, damage)
            }
            return
        }

        if let tower = nearestTower(team: 1, from: player.position), distance(player.position, tower.node.position) <= heroClass.attackRange + 30 {
            attackVisual(to: tower.node.position) { [weak self, weak tower] in
                guard let self, let tower else { return }
                self.damageTower(tower, damage)
            }
            return
        }

        if let camp = nearestCamp(from: player.position), distance(player.position, camp.node.position) <= heroClass.attackRange + 25 {
            attackVisual(to: camp.node.position) { [weak self, weak camp] in
                guard let self, let camp else { return }
                camp.hp -= damage
                if camp.hp <= 0 { self.killCamp(camp) }
            }
        }
    }

    func castSkill(_ index: Int) {
        guard !gameOver, !player.isHidden, heroClass.skills.indices.contains(index) else { return }
        let now = CACurrentMediaTime()
        let spec = heroClass.skills[index]
        if let last = skillLastUsed[index], now - last < spec.cooldown {
            showMessage("\(Int(ceil(spec.cooldown - (now - last))))s cooldown")
            return
        }
        guard playerMana >= spec.mana else {
            showMessage("Not enough mana")
            return
        }
        playerMana -= spec.mana
        skillLastUsed[index] = now
        let aim = aimDirection()

        switch heroClass {
        case .tank:
            if index == 0 { areaDamage(radius: 155, amount: 130) }
            else if index == 1 { dash(190, aim); areaDamage(radius: 115, amount: 105) }
            else if index == 2 { shieldHP = min(560, shieldHP + 360); ring(at: player.position, radius: 80, color: .systemCyan) }
            else { areaDamage(radius: 270, amount: 250) }
        case .fighter:
            if index == 0 { areaDamage(radius: 145, amount: 165) }
            else if index == 1 { dash(170, aim); areaDamage(radius: 110, amount: 130) }
            else if index == 2 { attackBuffUntil = now + 6; playerHP = min(heroClass.maxHP, playerHP + 140) }
            else { areaDamage(radius: 220, amount: 350) }
        case .assassin:
            if index == 0 { dash(250, aim); areaDamage(radius: 100, amount: 190) }
            else if index == 1 { projectileDamage(range: 390, amount: 175) }
            else if index == 2 { stealthUntil = now + 3.2; player.alpha = 0.42; dash(150, aim) }
            else { projectileDamage(range: 420, amount: 390) }
        case .mage:
            if index == 0 { projectileDamage(range: 520, amount: 165) }
            else if index == 1 { areaDamage(radius: 190, amount: 145) }
            else if index == 2 { dash(185, aim) }
            else { areaDamage(radius: 330, amount: 410) }
        case .marksman:
            if index == 0 { projectileDamage(range: 650, amount: 190) }
            else if index == 1 { dash(180, aim) }
            else if index == 2 { attackBuffUntil = now + 6.5 }
            else { projectileDamage(range: 760, amount: 380) }
        case .support:
            if index == 0 { playerHP = min(heroClass.maxHP, playerHP + 260); ring(at: player.position, radius: 130, color: .systemGreen) }
            else if index == 1 { projectileDamage(range: 480, amount: 120) }
            else if index == 2 { shieldHP = min(500, shieldHP + 300) }
            else { playerHP = min(heroClass.maxHP, playerHP + 420); shieldHP = min(620, shieldHP + 260); ring(at: player.position, radius: 280, color: .systemMint) }
        }
        updateHUD()
    }

    override func update(_ currentTime: TimeInterval) {
        if lastFrameTime == 0 { lastFrameTime = currentTime }
        let dt = min(currentTime - lastFrameTime, 1.0 / 20.0)
        lastFrameTime = currentTime

        if currentTime - lastWaveTime >= 12 {
            lastWaveTime = currentTime
            spawnWave()
        }

        handleRespawns(currentTime)
        guard !gameOver else { return }

        playerMana = min(heroClass.maxMana, playerMana + CGFloat(dt) * 17)
        if heroClass == .support { playerHP = min(heroClass.maxHP, playerHP + CGFloat(dt) * 3.5) }
        if currentTime >= stealthUntil { player.alpha = 1 }

        if !player.isHidden {
            player.position.x += movement.dx * heroClass.moveSpeed * CGFloat(dt)
            player.position.y += movement.dy * heroClass.moveSpeed * CGFloat(dt)
            player.position.x = min(max(player.position.x, 90), worldWidth - 90)
            player.position.y = min(max(player.position.y, 90), worldHeight - 90)
        }

        updateMinions(currentTime, dt: dt)
        updateBots(currentTime, dt: dt)
        updateTowers(currentTime)
        updateCamera()
        cleanupDeadUnits()
        updateHUD()
    }

    private func spawnWave() {
        for lane in Lane.allCases {
            for team in [0, 1] {
                for i in 0..<4 {
                    let path = lanePoints(lane)
                    let start = team == 0 ? path[0] : path[path.count - 1]
                    let direction: CGFloat = team == 0 ? 1 : -1
                    let offset = CGFloat(i) * 32 * direction
                    let minion = LaneMinion(team: team, lane: lane, position: CGPoint(x: start.x + offset, y: start.y + CGFloat(i % 2) * 22 - 11))
                    minions.append(minion)
                    worldRoot.addChild(minion.node)
                }
            }
        }
    }

    private func updateMinions(_ now: TimeInterval, dt: TimeInterval) {
        for minion in minions where minion.hp > 0 && minion.node.parent != nil {
            if let enemy = nearestMinion(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, enemy.node.position) < 55 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.85
                    enemy.hp -= 36
                    flash(at: enemy.node.position, color: minion.team == 0 ? .systemTeal : .systemRed)
                }
                continue
            }

            if let bot = nearestBot(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, bot.node.position) < 65 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.95
                    damageBot(bot, 30)
                }
                continue
            }

            if minion.team == 1 && !player.isHidden && distance(minion.node.position, player.position) < 66 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.95
                    damagePlayer(30)
                }
                continue
            }

            if let tower = nearestTower(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, tower.node.position) < 72 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 1.0
                    damageTower(tower, 30)
                }
                continue
            }

            moveMinionAlongLane(minion, dt: dt)
        }
    }

    private func moveMinionAlongLane(_ minion: LaneMinion, dt: TimeInterval) {
        let original = lanePoints(minion.lane)
        let path = minion.team == 0 ? original : original.reversed()
        let points = Array(path)
        let index = min(minion.waypointIndex + 1, points.count - 1)
        let target = points[index]
        move(node: minion.node, toward: target, speed: 72, dt: dt)
        if distance(minion.node.position, target) < 26 && minion.waypointIndex < points.count - 2 {
            minion.waypointIndex += 1
        }
    }

    private func updateBots(_ now: TimeInterval, dt: TimeInterval) {
        for bot in bots where bot.respawnAt == nil && !bot.node.isHidden {
            if let enemyBot = nearestBot(team: 1 - bot.team, from: bot.node.position, excluding: bot), distance(bot.node.position, enemyBot.node.position) < 125 {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + 0.85
                    damageBot(enemyBot, 82)
                }
                continue
            }

            if bot.team == 1 && !player.isHidden && distance(bot.node.position, player.position) < 145 && now >= stealthUntil {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + 0.9
                    damagePlayer(86)
                }
                continue
            }

            if let minion = nearestMinion(team: 1 - bot.team, from: bot.node.position), distance(bot.node.position, minion.node.position) < 150 {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + 0.75
                    minion.hp -= 72
                }
                continue
            }

            let path = lanePoints(bot.lane)
            let target: CGPoint
            if bot.team == 0 {
                target = path[min(4, path.count - 1)]
            } else {
                target = path[max(1, path.count - 5)]
            }
            move(node: bot.node, toward: target, speed: 155, dt: dt)
        }
    }

    private func updateTowers(_ now: TimeInterval) {
        for tower in towers where tower.hp > 0 && tower.node.parent != nil {
            guard now >= tower.nextAttack else { continue }

            if let minion = nearestMinion(team: 1 - tower.team, from: tower.node.position), distance(tower.node.position, minion.node.position) <= 285 {
                tower.nextAttack = now + 0.95
                minion.hp -= tower.tier == 0 ? 125 : 96
                towerShot(from: tower.node.position, to: minion.node.position, color: tower.team == 0 ? .systemCyan : .systemPink)
                continue
            }

            if let bot = nearestBot(team: 1 - tower.team, from: tower.node.position), distance(tower.node.position, bot.node.position) <= 285 {
                tower.nextAttack = now + 1.0
                damageBot(bot, tower.tier == 0 ? 150 : 110)
                towerShot(from: tower.node.position, to: bot.node.position, color: tower.team == 0 ? .systemCyan : .systemPink)
                continue
            }

            if tower.team == 1 && !player.isHidden && distance(tower.node.position, player.position) <= 285 {
                tower.nextAttack = now + 1.0
                damagePlayer(tower.tier == 0 ? 155 : 112)
                towerShot(from: tower.node.position, to: player.position, color: .systemPink)
            }
        }
    }

    private func updateCamera() {
        guard !player.isHidden else { return }
        let halfW: CGFloat = 465
        let halfH: CGFloat = 215
        let desiredX = min(max(player.position.x, halfW), worldWidth - halfW)
        let desiredY = min(max(player.position.y, halfH), worldHeight - halfH)
        gameCamera.position.x += (desiredX - gameCamera.position.x) * 0.14
        gameCamera.position.y += (desiredY - gameCamera.position.y) * 0.14
    }

    private func handleRespawns(_ now: TimeInterval) {
        if let respawn = playerRespawnAt, now >= respawn {
            playerRespawnAt = nil
            player.isHidden = false
            player.alpha = 1
            playerHP = heroClass.maxHP
            playerMana = heroClass.maxMana
            player.position = CGPoint(x: 330, y: 900)
            showMessage("Respawned")
        }

        for bot in bots {
            if let respawn = bot.respawnAt, now >= respawn {
                bot.respawnAt = nil
                bot.hp = bot.maxHP
                bot.node.isHidden = false
                bot.node.position = spawnPosition(team: bot.team, lane: bot.lane, offset: 0)
            }
        }

        for camp in jungleCamps {
            if let respawn = camp.respawnAt, now >= respawn {
                camp.respawnAt = nil
                camp.hp = camp.maxHP
                camp.node.isHidden = false
            }
        }
    }

    private func damagePlayer(_ amount: CGFloat) {
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
            playerRespawnAt = CACurrentMediaTime() + 7
            showMessage("Defeated • respawn in 7s")
        }
    }

    private func damageBot(_ bot: BotHero, _ amount: CGFloat) {
        guard bot.respawnAt == nil else { return }
        bot.hp -= amount
        flash(at: bot.node.position, color: .white)
        if bot.hp <= 0 {
            bot.hp = 0
            bot.node.isHidden = true
            bot.respawnAt = CACurrentMediaTime() + 8
            if bot.team == 1 { blueKills += 1 } else { redKills += 1 }
        }
    }

    private func damageTower(_ tower: TowerUnit, _ amount: CGFloat) {
        guard tower.hp > 0 else { return }
        tower.hp -= amount
        tower.node.alpha = max(0.25, tower.hp / tower.maxHP)
        flash(at: tower.node.position, color: .systemYellow)
        if tower.hp <= 0 {
            tower.hp = 0
            tower.node.run(.sequence([.scale(to: 1.35, duration: 0.12), .fadeOut(withDuration: 0.25), .removeFromParent()]))
            if tower.tier == 0 {
                gameOver = true
                showMessage(tower.team == 1 ? "VICTORY" : "DEFEAT")
            }
        }
    }

    private func killCamp(_ camp: JungleCamp) {
        camp.hp = 0
        camp.node.isHidden = true
        camp.respawnAt = CACurrentMediaTime() + 22
        playerHP = min(heroClass.maxHP, playerHP + 100)
        attackBuffUntil = max(attackBuffUntil, CACurrentMediaTime() + 8)
        showMessage("Jungle buff acquired")
    }

    private func cleanupDeadUnits() {
        for minion in minions where minion.hp <= 0 && minion.node.parent != nil {
            minion.node.removeFromParent()
        }
        minions.removeAll { $0.hp <= 0 && $0.node.parent == nil }
    }

    private func areaDamage(radius: CGFloat, amount: CGFloat) {
        ring(at: player.position, radius: radius, color: playerColor())
        for minion in minions where minion.team == 1 && minion.hp > 0 && distance(player.position, minion.node.position) <= radius {
            minion.hp -= amount
        }
        for bot in bots where bot.team == 1 && bot.respawnAt == nil && distance(player.position, bot.node.position) <= radius {
            damageBot(bot, amount)
        }
        for camp in jungleCamps where camp.respawnAt == nil && distance(player.position, camp.node.position) <= radius {
            camp.hp -= amount
            if camp.hp <= 0 { killCamp(camp) }
        }
        cleanupDeadUnits()
    }

    private func projectileDamage(range: CGFloat, amount: CGFloat) {
        let dir = aimDirection()
        let end = CGPoint(x: player.position.x + dir.dx * range, y: player.position.y + dir.dy * range)
        towerShot(from: player.position, to: end, color: playerColor())

        var best: (CGFloat, BotHero)?
        for bot in bots where bot.team == 1 && bot.respawnAt == nil {
            let d = distancePointToSegment(bot.node.position, player.position, end)
            if d < 70 {
                let along = distance(player.position, bot.node.position)
                if along <= range && (best == nil || along < best!.0) { best = (along, bot) }
            }
        }
        if let bot = best?.1 { damageBot(bot, amount) }

        for minion in minions where minion.team == 1 && minion.hp > 0 {
            if distancePointToSegment(minion.node.position, player.position, end) < 42 && distance(player.position, minion.node.position) <= range {
                minion.hp -= amount * 0.75
            }
        }
        cleanupDeadUnits()
    }

    private func dash(_ amount: CGFloat, _ direction: CGVector) {
        player.position.x = min(max(player.position.x + direction.dx * amount, 90), worldWidth - 90)
        player.position.y = min(max(player.position.y + direction.dy * amount, 90), worldHeight - 90)
        flash(at: player.position, color: playerColor())
    }

    private func attackVisual(to point: CGPoint, completion: @escaping () -> Void) {
        if heroClass.attackRange > 150 {
            let bolt = SKShapeNode(circleOfRadius: 6)
            bolt.fillColor = playerColor()
            bolt.strokeColor = .white
            bolt.position = player.position
            bolt.zPosition = 30
            worldRoot.addChild(bolt)
            let duration = max(0.08, Double(distance(player.position, point) / 900))
            bolt.run(.sequence([.move(to: point, duration: duration), .run(completion), .removeFromParent()]))
        } else {
            flash(at: point, color: playerColor())
            completion()
        }
    }

    private func towerShot(from: CGPoint, to: CGPoint, color: SKColor) {
        let line = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        line.path = path
        line.strokeColor = color
        line.lineWidth = 5
        line.glowWidth = 4
        line.zPosition = 28
        worldRoot.addChild(line)
        line.run(.sequence([.fadeOut(withDuration: 0.16), .removeFromParent()]))
    }

    private func ring(at point: CGPoint, radius: CGFloat, color: SKColor) {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.position = point
        ring.fillColor = color.withAlphaComponent(0.10)
        ring.strokeColor = color.withAlphaComponent(0.85)
        ring.lineWidth = 4
        ring.zPosition = 25
        ring.setScale(0.25)
        worldRoot.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1, duration: 0.18), .fadeOut(withDuration: 0.28)]), .removeFromParent()]))
    }

    private func flash(at point: CGPoint, color: SKColor) {
        let f = SKShapeNode(circleOfRadius: 18)
        f.position = point
        f.fillColor = color
        f.strokeColor = .clear
        f.zPosition = 35
        worldRoot.addChild(f)
        f.run(.sequence([.scale(to: 1.8, duration: 0.09), .fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    private func updateHUD() {
        hpBar.xScale = max(0, playerHP / heroClass.maxHP)
        manaBar.xScale = max(0, playerMana / heroClass.maxMana)
        scoreLabel.text = "\(blueKills)   •   \(redKills)"
        laneLabel.text = "\(currentLaneName())  •  Shield \(Int(shieldHP))"
    }

    private func currentLaneName() -> String {
        let y = player.position.y
        if y > 1180 { return "TOP" }
        if y < 620 { return "BOTTOM" }
        if abs(y - 900) < 210 { return "MID" }
        return "JUNGLE"
    }

    private func showMessage(_ text: String) {
        messageLabel.removeAllActions()
        messageLabel.text = text
        messageLabel.alpha = 1
        messageLabel.run(.sequence([.wait(forDuration: 1.25), .fadeOut(withDuration: 0.25)]))
    }

    private func playerColor() -> SKColor {
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
        let len = sqrt(movement.dx * movement.dx + movement.dy * movement.dy)
        if len > 0.18 { return CGVector(dx: movement.dx / len, dy: movement.dy / len) }
        if let bot = nearestBot(team: 1, from: player.position) {
            let dx = bot.node.position.x - player.position.x
            let dy = bot.node.position.y - player.position.y
            let d = max(1, sqrt(dx * dx + dy * dy))
            return CGVector(dx: dx / d, dy: dy / d)
        }
        return CGVector(dx: 1, dy: 0)
    }

    private func nearestMinion(team: Int, from point: CGPoint) -> LaneMinion? {
        minions.filter { $0.team == team && $0.hp > 0 && $0.node.parent != nil }.min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func nearestBot(team: Int, from point: CGPoint, excluding: BotHero? = nil) -> BotHero? {
        bots.filter { $0.team == team && $0.respawnAt == nil && !$0.node.isHidden && $0 !== excluding }.min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func nearestTower(team: Int, from point: CGPoint) -> TowerUnit? {
        towers.filter { $0.team == team && $0.hp > 0 && $0.node.parent != nil }.min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func nearestCamp(from point: CGPoint) -> JungleCamp? {
        jungleCamps.filter { $0.respawnAt == nil && !$0.node.isHidden }.min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func spawnPosition(team: Int, lane: Lane, offset: CGFloat) -> CGPoint {
        let points = lanePoints(lane)
        let p = team == 0 ? points[1] : points[points.count - 2]
        return CGPoint(x: p.x + (team == 0 ? offset : -offset), y: p.y + offset * 0.25)
    }

    private func move(node: SKNode, toward point: CGPoint, speed: CGFloat, dt: TimeInterval) {
        let dx = point.x - node.position.x
        let dy = point.y - node.position.y
        let d = max(1, sqrt(dx * dx + dy * dy))
        node.position.x += dx / d * speed * CGFloat(dt)
        node.position.y += dy / d * speed * CGFloat(dt)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let ab2 = max(0.0001, abx * abx + aby * aby)
        let t = min(1, max(0, (apx * abx + apy * aby) / ab2))
        let closest = CGPoint(x: a.x + abx * t, y: a.y + aby * t)
        return distance(p, closest)
    }
}