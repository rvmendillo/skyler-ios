import SpriteKit
import Foundation

private enum Lane: CaseIterable {
    case top, mid, bottom
}

private final class MinionUnit {
    let node: SKShapeNode
    let team: Int
    let lane: Lane
    var hp: CGFloat = 240
    var nextAttack: TimeInterval = 0
    var waypointIndex = 0

    init(team: Int, lane: Lane, position: CGPoint) {
        self.team = team
        self.lane = lane
        node = SKShapeNode(circleOfRadius: 14)
        node.position = position
        node.fillColor = team == 0 ? .systemTeal : .systemRed
        node.strokeColor = .white.withAlphaComponent(0.55)
        node.lineWidth = 1.5
        node.zPosition = 8
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
        maxHP = tier == 0 ? 3800 : 1900 + CGFloat(3 - tier) * 220
        hp = maxHP
        node = SKShapeNode(rectOf: CGSize(width: tier == 0 ? 84 : 54, height: tier == 0 ? 84 : 86), cornerRadius: 13)
        node.position = position
        node.fillColor = team == 0 ? .systemCyan : .systemPink
        node.strokeColor = .white.withAlphaComponent(0.65)
        node.lineWidth = 2
        node.zPosition = 10
    }
}

private final class BotUnit {
    let node: SKShapeNode
    let team: Int
    let lane: Lane
    let maxHP: CGFloat = 1120
    var hp: CGFloat = 1120
    var nextAttack: TimeInterval = 0
    var respawnAt: TimeInterval?

    init(team: Int, lane: Lane, position: CGPoint, index: Int) {
        self.team = team
        self.lane = lane
        node = SKShapeNode(circleOfRadius: 23)
        node.position = position
        node.fillColor = team == 0 ? .systemBlue : .systemRed
        node.strokeColor = .white
        node.lineWidth = 2
        node.zPosition = 14

        let core = SKShapeNode(circleOfRadius: 8)
        core.fillColor = index.isMultiple(of: 2) ? .white : .systemYellow
        core.strokeColor = .clear
        node.addChild(core)
    }
}

private final class CampUnit {
    let node: SKShapeNode
    let maxHP: CGFloat
    var hp: CGFloat
    var respawnAt: TimeInterval?

    init(position: CGPoint, elite: Bool) {
        maxHP = elite ? 1250 : 820
        hp = maxHP
        node = SKShapeNode(circleOfRadius: elite ? 31 : 26)
        node.position = position
        node.fillColor = elite ? .systemPurple : .systemGreen
        node.strokeColor = .white.withAlphaComponent(0.55)
        node.lineWidth = 2
        node.zPosition = 7
    }
}

final class GameScene: SKScene {
    private let heroClass: HeroClass
    private let worldWidth: CGFloat = 3000
    private let worldHeight: CGFloat = 1800

    private var world = SKNode()
    private var gameCamera = SKCameraNode()
    private var player = SKShapeNode(circleOfRadius: 27)
    private var hpBar = SKSpriteNode(color: .systemGreen, size: CGSize(width: 210, height: 11))
    private var manaBar = SKSpriteNode(color: .systemBlue, size: CGSize(width: 210, height: 7))
    private var scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var laneLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private var messageLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    private var minions: [MinionUnit] = []
    private var towers: [TowerUnit] = []
    private var bots: [BotUnit] = []
    private var camps: [CampUnit] = []

    private var didBootstrap = false
    private var movement = CGVector.zero
    private var lastFrameTime: TimeInterval = 0
    private var lastWaveTime: TimeInterval = -100
    private var lastAttackTime: TimeInterval = -100
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
        player = SKShapeNode(circleOfRadius: 27)
        hpBar = SKSpriteNode(color: .systemGreen, size: CGSize(width: 210, height: 11))
        manaBar = SKSpriteNode(color: .systemBlue, size: CGSize(width: 210, height: 7))
        scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        laneLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        messageLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

        minions.removeAll()
        towers.removeAll()
        bots.removeAll()
        camps.removeAll()
        movement = .zero
        lastFrameTime = 0
        lastWaveTime = -100
        lastAttackTime = -100
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

        addChild(world)
        buildMap()
        buildStructures()
        buildPlayer()
        buildBots()
        buildCamps()
        buildCameraAndHUD()
        spawnWave()
        updateHUD()
    }

    private func buildMap() {
        let ground = SKSpriteNode(
            color: SKColor(red: 0.045, green: 0.16, blue: 0.10, alpha: 1),
            size: CGSize(width: worldWidth, height: worldHeight)
        )
        ground.anchorPoint = .zero
        ground.position = .zero
        ground.zPosition = -30
        world.addChild(ground)

        let river = SKShapeNode(rectOf: CGSize(width: 175, height: worldHeight + 100), cornerRadius: 48)
        river.position = CGPoint(x: worldWidth / 2, y: worldHeight / 2)
        river.fillColor = SKColor(red: 0.05, green: 0.31, blue: 0.42, alpha: 0.84)
        river.strokeColor = .white.withAlphaComponent(0.07)
        river.lineWidth = 4
        river.zPosition = -24
        world.addChild(river)

        for lane in Lane.allCases {
            let points = lanePoints(lane)
            let path = CGMutablePath()
            if let first = points.first {
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }

            let border = SKShapeNode(path: path)
            border.strokeColor = .white.withAlphaComponent(0.06)
            border.lineWidth = 154
            border.lineCap = .round
            border.lineJoin = .round
            border.zPosition = -23
            world.addChild(border)

            let road = SKShapeNode(path: path)
            road.strokeColor = SKColor(red: 0.22, green: 0.23, blue: 0.18, alpha: 1)
            road.lineWidth = 144
            road.lineCap = .round
            road.lineJoin = .round
            road.zPosition = -22
            world.addChild(road)
        }

        for x in stride(from: CGFloat(560), through: worldWidth - 560, by: 320) {
            for y in [CGFloat(610), CGFloat(1190)] {
                let bush = SKShapeNode(ellipseOf: CGSize(width: 120, height: 78))
                bush.position = CGPoint(x: x, y: y)
                bush.fillColor = SKColor(red: 0.04, green: 0.28, blue: 0.08, alpha: 0.95)
                bush.strokeColor = .clear
                bush.zPosition = -15
                world.addChild(bush)
            }
        }

        let blueBase = SKShapeNode(circleOfRadius: 155)
        blueBase.position = CGPoint(x: 180, y: 900)
        blueBase.fillColor = .systemBlue.withAlphaComponent(0.18)
        blueBase.strokeColor = .systemCyan.withAlphaComponent(0.5)
        blueBase.lineWidth = 5
        blueBase.zPosition = -12
        world.addChild(blueBase)

        let redBase = SKShapeNode(circleOfRadius: 155)
        redBase.position = CGPoint(x: worldWidth - 180, y: 900)
        redBase.fillColor = .systemRed.withAlphaComponent(0.18)
        redBase.strokeColor = .systemPink.withAlphaComponent(0.5)
        redBase.lineWidth = 5
        redBase.zPosition = -12
        world.addChild(redBase)
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

    private func buildStructures() {
        for lane in Lane.allCases {
            let points = lanePoints(lane)
            let bluePositions = [
                points[1], points[2], interpolate(points[2], points[3], 0.55)
            ]
            let redPositions = [
                points[5], points[4], interpolate(points[4], points[3], 0.55)
            ]

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
        player.position = CGPoint(x: 330, y: 900)
        player.fillColor = playerColor()
        player.strokeColor = .white
        player.lineWidth = 3
        player.zPosition = 18
        player.alpha = 1
        player.isHidden = false

        let core = SKShapeNode(circleOfRadius: 10)
        core.fillColor = .white
        core.strokeColor = .clear
        player.addChild(core)
        world.addChild(player)
    }

    private func buildBots() {
        let allyLanes: [Lane] = [.top, .mid, .bottom, .bottom]
        let enemyLanes: [Lane] = [.top, .top, .mid, .bottom, .bottom]

        for (index, lane) in allyLanes.enumerated() {
            let bot = BotUnit(team: 0, lane: lane, position: botSpawn(team: 0, lane: lane, offset: CGFloat(index * 34)), index: index)
            bots.append(bot)
            world.addChild(bot.node)
        }
        for (index, lane) in enemyLanes.enumerated() {
            let bot = BotUnit(team: 1, lane: lane, position: botSpawn(team: 1, lane: lane, offset: CGFloat(index * 34)), index: index)
            bots.append(bot)
            world.addChild(bot.node)
        }
    }

    private func buildCamps() {
        let definitions: [(CGPoint, Bool)] = [
            (CGPoint(x: 920, y: 650), false), (CGPoint(x: 1060, y: 1160), true),
            (CGPoint(x: 1300, y: 650), false), (CGPoint(x: 1700, y: 1150), false),
            (CGPoint(x: 1940, y: 640), true), (CGPoint(x: 2080, y: 1160), false)
        ]
        for definition in definitions {
            let camp = CampUnit(position: definition.0, elite: definition.1)
            camps.append(camp)
            world.addChild(camp.node)
        }
    }

    private func buildCameraAndHUD() {
        camera = gameCamera
        gameCamera.position = player.position
        gameCamera.setScale(1)
        addChild(gameCamera)

        let hpBack = SKSpriteNode(color: .black.withAlphaComponent(0.60), size: CGSize(width: 214, height: 15))
        hpBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpBack.zPosition = 100
        gameCamera.addChild(hpBack)

        hpBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpBar.zPosition = 101
        gameCamera.addChild(hpBar)

        let manaBack = SKSpriteNode(color: .black.withAlphaComponent(0.60), size: CGSize(width: 214, height: 11))
        manaBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        manaBack.zPosition = 100
        manaBack.name = "manaBack"
        gameCamera.addChild(manaBack)

        manaBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        manaBar.zPosition = 101
        gameCamera.addChild(manaBar)

        scoreLabel.fontSize = 18
        scoreLabel.zPosition = 101
        gameCamera.addChild(scoreLabel)

        laneLabel.fontSize = 13
        laneLabel.horizontalAlignmentMode = .right
        laneLabel.zPosition = 101
        gameCamera.addChild(laneLabel)

        messageLabel.fontSize = 16
        messageLabel.alpha = 0
        messageLabel.zPosition = 101
        gameCamera.addChild(messageLabel)

        let mini = SKShapeNode(rectOf: CGSize(width: 150, height: 90), cornerRadius: 8)
        mini.name = "mini"
        mini.fillColor = .black.withAlphaComponent(0.42)
        mini.strokeColor = .white.withAlphaComponent(0.25)
        mini.lineWidth = 1
        mini.zPosition = 100
        gameCamera.addChild(mini)

        for y in [-22.0, 0.0, 22.0] {
            let line = SKShapeNode(rectOf: CGSize(width: 120, height: 4), cornerRadius: 2)
            line.fillColor = .white.withAlphaComponent(0.18)
            line.strokeColor = .clear
            line.position = CGPoint(x: 0, y: y)
            mini.addChild(line)
        }

        layoutHUD()
        updateCameraPosition(immediate: true)
    }

    private func layoutHUD() {
        guard gameCamera.parent != nil else { return }
        let halfW = max(300, size.width / 2)
        let halfH = max(170, size.height / 2)
        let left = -halfW + 26
        let right = halfW - 26
        let top = halfH - 28

        if gameCamera.children.count > 0 {
            for child in gameCamera.children where child !== hpBar && child !== manaBar && child !== scoreLabel && child !== laneLabel && child !== messageLabel {
                if child.name == "manaBack" { child.position = CGPoint(x: left, y: top - 18) }
                else if child.name == "mini" { child.position = CGPoint(x: right - 80, y: top - 62) }
                else if child is SKSpriteNode && child !== hpBar && child !== manaBar { child.position = CGPoint(x: left, y: top) }
            }
        }

        hpBar.position = CGPoint(x: left + 2, y: top)
        manaBar.position = CGPoint(x: left + 2, y: top - 18)
        scoreLabel.position = CGPoint(x: 0, y: top - 2)
        laneLabel.position = CGPoint(x: right, y: top - 4)
        messageLabel.position = CGPoint(x: 0, y: -halfH + 80)
    }

    func setMovement(_ vector: CGVector) {
        movement = vector
    }

    func basicAttack() {
        guard !gameOver, !player.isHidden else { return }
        let now = CACurrentMediaTime()
        let cooldown: TimeInterval = now < attackBuffUntil ? 0.36 : (heroClass == .marksman ? 0.55 : 0.72)
        guard now - lastAttackTime >= cooldown else { return }
        lastAttackTime = now

        let damage = heroClass.attackDamage * (now < attackBuffUntil ? 1.25 : 1)

        if let minion = nearestMinion(team: 1, from: player.position), distance(player.position, minion.node.position) <= heroClass.attackRange {
            performAttack(to: minion.node.position) { [weak self, weak minion] in
                guard let self, let minion else { return }
                minion.hp -= damage
                self.cleanupMinions()
            }
            return
        }

        if let bot = nearestBot(team: 1, from: player.position), distance(player.position, bot.node.position) <= heroClass.attackRange {
            performAttack(to: bot.node.position) { [weak self, weak bot] in
                guard let self, let bot else { return }
                self.damage(bot: bot, amount: damage)
            }
            return
        }

        if let tower = nearestTower(team: 1, from: player.position), distance(player.position, tower.node.position) <= heroClass.attackRange + 30 {
            performAttack(to: tower.node.position) { [weak self, weak tower] in
                guard let self, let tower else { return }
                self.damage(tower: tower, amount: damage)
            }
            return
        }

        if let camp = nearestCamp(from: player.position), distance(player.position, camp.node.position) <= heroClass.attackRange + 30 {
            performAttack(to: camp.node.position) { [weak self, weak camp] in
                guard let self, let camp else { return }
                camp.hp -= damage
                if camp.hp <= 0 { self.kill(camp: camp) }
            }
        }
    }

    func castSkill(_ index: Int) {
        guard !gameOver, !player.isHidden, heroClass.skills.indices.contains(index) else { return }
        let now = CACurrentMediaTime()
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

        switch heroClass {
        case .tank:
            if index == 0 { areaDamage(radius: 155, amount: 130) }
            else if index == 1 { dash(amount: 190, direction: aim); areaDamage(radius: 115, amount: 105) }
            else if index == 2 { shieldHP = min(560, shieldHP + 360); ring(at: player.position, radius: 80) }
            else { areaDamage(radius: 270, amount: 250) }

        case .fighter:
            if index == 0 { areaDamage(radius: 145, amount: 165) }
            else if index == 1 { dash(amount: 170, direction: aim); areaDamage(radius: 110, amount: 130) }
            else if index == 2 { attackBuffUntil = now + 6; playerHP = min(heroClass.maxHP, playerHP + 140) }
            else { areaDamage(radius: 220, amount: 350) }

        case .assassin:
            if index == 0 { dash(amount: 250, direction: aim); areaDamage(radius: 100, amount: 190) }
            else if index == 1 { lineDamage(range: 390, amount: 175) }
            else if index == 2 { stealthUntil = now + 3.2; player.alpha = 0.42; dash(amount: 150, direction: aim) }
            else { lineDamage(range: 430, amount: 390) }

        case .mage:
            if index == 0 { lineDamage(range: 520, amount: 165) }
            else if index == 1 { areaDamage(radius: 190, amount: 145) }
            else if index == 2 { dash(amount: 185, direction: aim) }
            else { areaDamage(radius: 330, amount: 410) }

        case .marksman:
            if index == 0 { lineDamage(range: 650, amount: 190) }
            else if index == 1 { dash(amount: 180, direction: aim) }
            else if index == 2 { attackBuffUntil = now + 6.5 }
            else { lineDamage(range: 760, amount: 380) }

        case .support:
            if index == 0 { playerHP = min(heroClass.maxHP, playerHP + 260); ring(at: player.position, radius: 130) }
            else if index == 1 { lineDamage(range: 480, amount: 120) }
            else if index == 2 { shieldHP = min(500, shieldHP + 300) }
            else {
                playerHP = min(heroClass.maxHP, playerHP + 420)
                shieldHP = min(620, shieldHP + 260)
                ring(at: player.position, radius: 280)
            }
        }
        updateHUD()
    }

    override func update(_ currentTime: TimeInterval) {
        guard didBootstrap else { return }
        if lastFrameTime == 0 { lastFrameTime = currentTime }
        let dt = min(max(currentTime - lastFrameTime, 0), 1.0 / 20.0)
        lastFrameTime = currentTime

        if currentTime - lastWaveTime >= 11 {
            lastWaveTime = currentTime
            spawnWave()
        }

        handleRespawns(now: currentTime)
        guard !gameOver else { return }

        playerMana = min(heroClass.maxMana, playerMana + CGFloat(dt) * 17)
        if heroClass == .support { playerHP = min(heroClass.maxHP, playerHP + CGFloat(dt) * 3) }
        if currentTime >= stealthUntil { player.alpha = 1 }

        if !player.isHidden {
            player.position.x += movement.dx * heroClass.moveSpeed * CGFloat(dt)
            player.position.y += movement.dy * heroClass.moveSpeed * CGFloat(dt)
            player.position.x = min(max(player.position.x, 90), worldWidth - 90)
            player.position.y = min(max(player.position.y, 90), worldHeight - 90)
        }

        updateMinions(now: currentTime, dt: dt)
        updateBots(now: currentTime, dt: dt)
        updateTowers(now: currentTime)
        updateCameraPosition(immediate: false)
        cleanupMinions()
        updateHUD()
    }

    private func spawnWave() {
        for lane in Lane.allCases {
            let path = lanePoints(lane)
            guard let blueStart = path.first, let redStart = path.last else { continue }

            for i in 0..<3 {
                let blue = MinionUnit(
                    team: 0,
                    lane: lane,
                    position: CGPoint(x: blueStart.x + CGFloat(i * 30), y: blueStart.y + CGFloat((i - 1) * 20))
                )
                minions.append(blue)
                world.addChild(blue.node)

                let red = MinionUnit(
                    team: 1,
                    lane: lane,
                    position: CGPoint(x: redStart.x - CGFloat(i * 30), y: redStart.y + CGFloat((i - 1) * 20))
                )
                minions.append(red)
                world.addChild(red.node)
            }
        }
    }

    private func updateMinions(now: TimeInterval, dt: TimeInterval) {
        let active = minions.filter { $0.hp > 0 && $0.node.parent != nil }
        for minion in active {
            if let enemy = nearestMinion(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, enemy.node.position) < 55 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.9
                    enemy.hp -= 34
                    flash(at: enemy.node.position, color: minion.team == 0 ? .systemTeal : .systemRed)
                }
                continue
            }

            if let bot = nearestBot(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, bot.node.position) < 70 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 1
                    damage(bot: bot, amount: 28)
                }
                continue
            }

            if minion.team == 1 && !player.isHidden && distance(minion.node.position, player.position) < 72 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 1
                    damagePlayer(amount: 28)
                }
                continue
            }

            if let tower = nearestTower(team: 1 - minion.team, from: minion.node.position), distance(minion.node.position, tower.node.position) < 78 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 1
                    damage(tower: tower, amount: 30)
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
        move(node: minion.node, toward: target, speed: 76, dt: dt)

        if distance(minion.node.position, target) < 28 && minion.waypointIndex < points.count - 2 {
            minion.waypointIndex += 1
        }
    }

    private func updateBots(now: TimeInterval, dt: TimeInterval) {
        for bot in bots where bot.respawnAt == nil && !bot.node.isHidden {
            if let enemy = nearestBot(team: 1 - bot.team, from: bot.node.position, excluding: bot), distance(bot.node.position, enemy.node.position) < 130 {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + 0.9
                    damage(bot: enemy, amount: 78)
                }
                continue
            }

            if bot.team == 1 && !player.isHidden && now >= stealthUntil && distance(bot.node.position, player.position) < 145 {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + 0.9
                    damagePlayer(amount: 82)
                }
                continue
            }

            if let minion = nearestMinion(team: 1 - bot.team, from: bot.node.position), distance(bot.node.position, minion.node.position) < 145 {
                if now >= bot.nextAttack {
                    bot.nextAttack = now + 0.8
                    minion.hp -= 65
                }
                continue
            }

            let points = lanePoints(bot.lane)
            let target = bot.team == 0 ? points[3] : points[3]
            move(node: bot.node, toward: target, speed: 150, dt: dt)
        }
    }

    private func updateTowers(now: TimeInterval) {
        for tower in towers where tower.hp > 0 && tower.node.parent != nil {
            guard now >= tower.nextAttack else { continue }

            if let minion = nearestMinion(team: 1 - tower.team, from: tower.node.position), distance(tower.node.position, minion.node.position) <= 285 {
                tower.nextAttack = now + 1
                minion.hp -= tower.tier == 0 ? 125 : 95
                beam(from: tower.node.position, to: minion.node.position, color: tower.team == 0 ? .systemCyan : .systemPink)
                continue
            }

            if let bot = nearestBot(team: 1 - tower.team, from: tower.node.position), distance(tower.node.position, bot.node.position) <= 285 {
                tower.nextAttack = now + 1
                damage(bot: bot, amount: tower.tier == 0 ? 145 : 108)
                beam(from: tower.node.position, to: bot.node.position, color: tower.team == 0 ? .systemCyan : .systemPink)
                continue
            }

            if tower.team == 1 && !player.isHidden && distance(tower.node.position, player.position) <= 285 {
                tower.nextAttack = now + 1
                damagePlayer(amount: tower.tier == 0 ? 155 : 112)
                beam(from: tower.node.position, to: player.position, color: .systemPink)
            }
        }
    }

    private func handleRespawns(now: TimeInterval) {
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
            playerRespawnAt = CACurrentMediaTime() + 7
            showMessage("Defeated • respawn in 7s")
        }
    }

    private func damage(bot: BotUnit, amount: CGFloat) {
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

    private func damage(tower: TowerUnit, amount: CGFloat) {
        guard tower.hp > 0 else { return }
        tower.hp -= amount
        tower.node.alpha = max(0.22, tower.hp / tower.maxHP)
        flash(at: tower.node.position, color: .systemYellow)

        if tower.hp <= 0 {
            tower.hp = 0
            tower.node.removeAllActions()
            tower.node.run(.sequence([.fadeOut(withDuration: 0.22), .removeFromParent()]))
            if tower.tier == 0 {
                gameOver = true
                showMessage(tower.team == 1 ? "VICTORY" : "DEFEAT")
            }
        }
    }

    private func kill(camp: CampUnit) {
        camp.hp = 0
        camp.node.isHidden = true
        camp.respawnAt = CACurrentMediaTime() + 22
        playerHP = min(heroClass.maxHP, playerHP + 100)
        attackBuffUntil = max(attackBuffUntil, CACurrentMediaTime() + 8)
        showMessage("Jungle buff acquired")
    }

    private func cleanupMinions() {
        for minion in minions where minion.hp <= 0 && minion.node.parent != nil {
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
            damage(bot: bot, amount: amount)
        }
        for camp in camps where camp.respawnAt == nil && distance(player.position, camp.node.position) <= radius {
            camp.hp -= amount
            if camp.hp <= 0 { kill(camp: camp) }
        }
        cleanupMinions()
    }

    private func lineDamage(range: CGFloat, amount: CGFloat) {
        let direction = aimDirection()
        let end = CGPoint(x: player.position.x + direction.dx * range, y: player.position.y + direction.dy * range)
        beam(from: player.position, to: end, color: playerColor())

        if let bot = nearestBot(team: 1, from: player.position), distancePointToSegment(bot.node.position, player.position, end) < 75 {
            damage(bot: bot, amount: amount)
        }

        for minion in minions where minion.team == 1 && minion.hp > 0 {
            if distancePointToSegment(minion.node.position, player.position, end) < 42 && distance(player.position, minion.node.position) <= range {
                minion.hp -= amount * 0.72
            }
        }
        cleanupMinions()
    }

    private func dash(amount: CGFloat, direction: CGVector) {
        player.position.x = min(max(player.position.x + direction.dx * amount, 90), worldWidth - 90)
        player.position.y = min(max(player.position.y + direction.dy * amount, 90), worldHeight - 90)
        flash(at: player.position, color: playerColor())
    }

    private func performAttack(to point: CGPoint, completion: @escaping () -> Void) {
        if heroClass.attackRange > 150 {
            let projectile = SKShapeNode(circleOfRadius: 6)
            projectile.position = player.position
            projectile.fillColor = playerColor()
            projectile.strokeColor = .white
            projectile.zPosition = 30
            world.addChild(projectile)
            let duration = max(0.08, Double(distance(player.position, point) / 900))
            projectile.run(.sequence([.move(to: point, duration: duration), .run(completion), .removeFromParent()]))
        } else {
            flash(at: point, color: playerColor())
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

    private func ring(at point: CGPoint, radius: CGFloat) {
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = point
        node.fillColor = playerColor().withAlphaComponent(0.10)
        node.strokeColor = playerColor().withAlphaComponent(0.85)
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

    private func updateHUD() {
        hpBar.xScale = max(0, playerHP / heroClass.maxHP)
        manaBar.xScale = max(0, playerMana / heroClass.maxMana)
        scoreLabel.text = "\(blueKills)   •   \(redKills)"
        laneLabel.text = "\(laneName())  •  Shield \(Int(shieldHP))"
    }

    private func laneName() -> String {
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
        messageLabel.run(.sequence([.wait(forDuration: 1.3), .fadeOut(withDuration: 0.25)]))
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
            .filter { $0.team == team && $0.hp > 0 && $0.node.parent != nil }
            .min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func nearestCamp(from point: CGPoint) -> CampUnit? {
        camps
            .filter { $0.respawnAt == nil && !$0.node.isHidden }
            .min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func botSpawn(team: Int, lane: Lane, offset: CGFloat) -> CGPoint {
        let points = lanePoints(lane)
        let point = team == 0 ? points[1] : points[5]
        return CGPoint(
            x: point.x + (team == 0 ? offset : -offset),
            y: point.y + offset * 0.2
        )
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
