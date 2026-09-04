import SpriteKit
import Foundation

private final class LaneMinion {
    let node: SKShapeNode
    let team: Int
    var hp: CGFloat = 220
    var nextAttack: TimeInterval = 0

    init(team: Int, position: CGPoint) {
        self.team = team
        node = SKShapeNode(circleOfRadius: 13)
        node.fillColor = team == 0 ? .systemTeal : .systemRed
        node.strokeColor = .white.withAlphaComponent(0.45)
        node.lineWidth = 1
        node.position = position
        node.zPosition = 3
    }
}

private final class TowerUnit {
    let node: SKShapeNode
    let team: Int
    let maxHP: CGFloat = 1700
    var hp: CGFloat = 1700
    var nextAttack: TimeInterval = 0

    init(team: Int, position: CGPoint) {
        self.team = team
        node = SKShapeNode(rectOf: CGSize(width: 52, height: 82), cornerRadius: 12)
        node.fillColor = team == 0 ? .systemCyan : .systemPink
        node.strokeColor = .white.withAlphaComponent(0.5)
        node.lineWidth = 2
        node.position = position
        node.zPosition = 4
    }
}

final class GameScene: SKScene {
    private let heroClass: HeroClass

    private let player = SKShapeNode(circleOfRadius: 26)
    private let enemyHero = SKShapeNode(circleOfRadius: 27)
    private var allyTower: TowerUnit!
    private var enemyTower: TowerUnit!
    private var minions: [LaneMinion] = []

    private var movement = CGVector.zero
    private var lastFrameTime: TimeInterval = 0
    private var lastWaveTime: TimeInterval = -99
    private var lastAttackTime: TimeInterval = -99
    private var enemyLastAttackTime: TimeInterval = -99
    private var skillLastUsed: [Int: TimeInterval] = [:]
    private var enemyStunnedUntil: TimeInterval = 0
    private var attackBuffUntil: TimeInterval = 0
    private var veilUntil: TimeInterval = 0
    private var playerRespawnAt: TimeInterval?
    private var enemyRespawnAt: TimeInterval?
    private var gameOver = false

    private var playerHP: CGFloat = 1
    private var playerMana: CGFloat = 1
    private var shieldHP: CGFloat = 0
    private var enemyHP: CGFloat = 1250
    private let enemyMaxHP: CGFloat = 1250
    private var blueKills = 0
    private var redKills = 0

    private let playerHPBar = SKSpriteNode(color: .systemGreen, size: CGSize(width: 260, height: 12))
    private let playerManaBar = SKSpriteNode(color: .systemBlue, size: CGSize(width: 260, height: 8))
    private let enemyHPBar = SKSpriteNode(color: .systemRed, size: CGSize(width: 260, height: 12))
    private let statusLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let messageLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let towerLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var messageToken = 0

    init(size: CGSize, heroClass: HeroClass) {
        self.heroClass = heroClass
        super.init(size: size)
        backgroundColor = SKColor(red: 0.035, green: 0.075, blue: 0.075, alpha: 1)
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
        minions.removeAll()
        movement = .zero
        lastFrameTime = 0
        lastWaveTime = -99
        lastAttackTime = -99
        enemyLastAttackTime = -99
        skillLastUsed.removeAll()
        enemyStunnedUntil = 0
        attackBuffUntil = 0
        veilUntil = 0
        playerRespawnAt = nil
        enemyRespawnAt = nil
        gameOver = false
        blueKills = 0
        redKills = 0
        playerHP = heroClass.maxHP
        playerMana = heroClass.maxMana
        shieldHP = 0
        enemyHP = enemyMaxHP

        setupMap()
        setupUnits()
        setupHUD()
        spawnWave()
    }

    private func setupMap() {
        let ground = SKSpriteNode(color: SKColor(red: 0.05, green: 0.16, blue: 0.12, alpha: 1), size: size)
        ground.anchorPoint = .zero
        ground.position = .zero
        ground.zPosition = -10
        addChild(ground)

        let lane = SKShapeNode(rectOf: CGSize(width: size.width - 120, height: 185), cornerRadius: 60)
        lane.fillColor = SKColor(red: 0.17, green: 0.20, blue: 0.17, alpha: 1)
        lane.strokeColor = .white.withAlphaComponent(0.07)
        lane.lineWidth = 4
        lane.position = CGPoint(x: size.width / 2, y: size.height / 2)
        lane.zPosition = -7
        addChild(lane)

        let river = SKShapeNode(rectOf: CGSize(width: 90, height: size.height + 100))
        river.fillColor = SKColor(red: 0.06, green: 0.28, blue: 0.34, alpha: 0.7)
        river.strokeColor = .clear
        river.position = CGPoint(x: size.width / 2, y: size.height / 2)
        river.zPosition = -6
        addChild(river)

        for x in stride(from: CGFloat(300), through: size.width - 300, by: 170) {
            for y in [CGFloat(125), size.height - 125] {
                let bush = SKShapeNode(circleOfRadius: 34)
                bush.fillColor = SKColor(red: 0.07, green: 0.28, blue: 0.10, alpha: 0.85)
                bush.strokeColor = .clear
                bush.position = CGPoint(x: x, y: y)
                bush.zPosition = -4
                addChild(bush)
            }
        }

        let centerMark = SKShapeNode(circleOfRadius: 56)
        centerMark.fillColor = .clear
        centerMark.strokeColor = .white.withAlphaComponent(0.10)
        centerMark.lineWidth = 3
        centerMark.position = CGPoint(x: size.width / 2, y: size.height / 2)
        centerMark.zPosition = -3
        addChild(centerMark)
    }

    private func setupUnits() {
        allyTower = TowerUnit(team: 0, position: CGPoint(x: 125, y: size.height / 2))
        enemyTower = TowerUnit(team: 1, position: CGPoint(x: size.width - 125, y: size.height / 2))
        addChild(allyTower.node)
        addChild(enemyTower.node)

        player.fillColor = playerColor()
        player.strokeColor = .white
        player.lineWidth = 3
        player.position = CGPoint(x: 260, y: size.height / 2)
        player.zPosition = 8
        addChild(player)

        let playerCore = SKShapeNode(circleOfRadius: 10)
        playerCore.fillColor = .white.withAlphaComponent(0.9)
        playerCore.strokeColor = .clear
        playerCore.name = "core"
        player.addChild(playerCore)

        enemyHero.fillColor = .systemRed
        enemyHero.strokeColor = .white
        enemyHero.lineWidth = 3
        enemyHero.position = CGPoint(x: size.width - 260, y: size.height / 2)
        enemyHero.zPosition = 8
        addChild(enemyHero)

        let enemyCore = SKShapeNode(circleOfRadius: 10)
        enemyCore.fillColor = .white.withAlphaComponent(0.9)
        enemyCore.strokeColor = .clear
        enemyHero.addChild(enemyCore)
    }

    private func setupHUD() {
        let hpBack = SKSpriteNode(color: .black.withAlphaComponent(0.55), size: CGSize(width: 264, height: 16))
        hpBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpBack.position = CGPoint(x: 20, y: size.height - 30)
        hpBack.zPosition = 30
        addChild(hpBack)

        playerHPBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        playerHPBar.position = CGPoint(x: 22, y: size.height - 30)
        playerHPBar.zPosition = 31
        addChild(playerHPBar)

        let manaBack = SKSpriteNode(color: .black.withAlphaComponent(0.55), size: CGSize(width: 264, height: 12))
        manaBack.anchorPoint = CGPoint(x: 0, y: 0.5)
        manaBack.position = CGPoint(x: 20, y: size.height - 48)
        manaBack.zPosition = 30
        addChild(manaBack)

        playerManaBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        playerManaBar.position = CGPoint(x: 22, y: size.height - 48)
        playerManaBar.zPosition = 31
        addChild(playerManaBar)

        let enemyBack = SKSpriteNode(color: .black.withAlphaComponent(0.55), size: CGSize(width: 264, height: 16))
        enemyBack.anchorPoint = CGPoint(x: 1, y: 0.5)
        enemyBack.position = CGPoint(x: size.width - 20, y: size.height - 30)
        enemyBack.zPosition = 30
        addChild(enemyBack)

        enemyHPBar.anchorPoint = CGPoint(x: 1, y: 0.5)
        enemyHPBar.position = CGPoint(x: size.width - 22, y: size.height - 30)
        enemyHPBar.zPosition = 31
        addChild(enemyHPBar)

        statusLabel.fontSize = 16
        statusLabel.horizontalAlignmentMode = .left
        statusLabel.position = CGPoint(x: 22, y: size.height - 75)
        statusLabel.zPosition = 32
        addChild(statusLabel)

        scoreLabel.fontSize = 18
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height - 36)
        scoreLabel.zPosition = 32
        addChild(scoreLabel)

        messageLabel.fontSize = 18
        messageLabel.position = CGPoint(x: size.width / 2, y: 92)
        messageLabel.alpha = 0
        messageLabel.zPosition = 32
        addChild(messageLabel)

        towerLabel.fontSize = 13
        towerLabel.position = CGPoint(x: size.width / 2, y: size.height - 61)
        towerLabel.zPosition = 32
        addChild(towerLabel)

        updateHUD()
    }

    func setMovement(_ vector: CGVector) {
        movement = vector
    }

    func basicAttack() {
        guard !gameOver, !player.isHidden else { return }
        let now = CACurrentMediaTime()
        let cooldown: TimeInterval = now < attackBuffUntil ? 0.38 : (heroClass == .marksman ? 0.58 : 0.72)
        guard now - lastAttackTime >= cooldown else { return }
        lastAttackTime = now

        let damage = heroClass.attackDamage * (now < attackBuffUntil ? 1.22 : 1.0)
        if let targetMinion = nearestMinion(team: 1, from: player.position), distance(player.position, targetMinion.node.position) <= heroClass.attackRange {
            performAttackVisual(to: targetMinion.node.position, ranged: heroClass.attackRange > 150) { [weak self, weak targetMinion] in
                guard let self, let targetMinion else { return }
                targetMinion.hp -= damage
                self.cleanupDeadMinions()
            }
            return
        }

        if !enemyHero.isHidden && distance(player.position, enemyHero.position) <= heroClass.attackRange {
            performAttackVisual(to: enemyHero.position, ranged: heroClass.attackRange > 150) { [weak self] in
                self?.damageEnemyHero(damage)
            }
            return
        }

        if distance(player.position, enemyTower.node.position) <= heroClass.attackRange + 20 {
            performAttackVisual(to: enemyTower.node.position, ranged: heroClass.attackRange > 150) { [weak self] in
                self?.damageTower(self?.enemyTower, amount: damage)
            }
        }
    }

    func castSkill(_ index: Int) {
        guard !gameOver, !player.isHidden, heroClass.skills.indices.contains(index) else { return }
        let now = CACurrentMediaTime()
        let skill = heroClass.skills[index]
        if let last = skillLastUsed[index], now - last < skill.cooldown {
            showMessage("\(skill.name): \(Int(ceil(skill.cooldown - (now - last))))s")
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
        case .tank: castTank(index, aim: aim, now: now)
        case .fighter: castFighter(index, aim: aim, now: now)
        case .assassin: castAssassin(index, aim: aim, now: now)
        case .mage: castMage(index, aim: aim, now: now)
        case .marksman: castMarksman(index, aim: aim, now: now)
        case .support: castSupport(index, aim: aim, now: now)
        }
        updateHUD()
    }

    private func castTank(_ index: Int, aim: CGVector, now: TimeInterval) {
        switch index {
        case 0:
            effectRing(at: player.position, radius: 150, color: .systemCyan)
            damageEnemies(around: player.position, radius: 150, amount: 120)
            if !enemyHero.isHidden && distance(player.position, enemyHero.position) <= 155 {
                enemyStunnedUntil = now + 1.0
            }
        case 1:
            dash(distance: 190, direction: aim)
            effectRing(at: player.position, radius: 120, color: .systemBlue)
            damageEnemies(around: player.position, radius: 125, amount: 105)
        case 2:
            shieldHP = min(520, shieldHP + 340)
            effectRing(at: player.position, radius: 72, color: .systemTeal)
            showMessage("Bulwark +340 shield")
        default:
            effectRing(at: player.position, radius: 270, color: .systemYellow)
            damageEnemies(around: player.position, radius: 270, amount: 210)
            if !enemyHero.isHidden && distance(player.position, enemyHero.position) <= 270 {
                enemyStunnedUntil = now + 2.0
            }
        }
    }

    private func castFighter(_ index: Int, aim: CGVector, now: TimeInterval) {
        switch index {
        case 0:
            effectRing(at: player.position, radius: 145, color: .systemOrange)
            damageEnemies(around: player.position, radius: 145, amount: 155)
        case 1:
            dash(distance: 165, direction: aim)
            damageEnemies(around: player.position, radius: 110, amount: 120)
        case 2:
            attackBuffUntil = now + 6
            playerHP = min(heroClass.maxHP, playerHP + 120)
            showMessage("Battle Surge")
        default:
            spinEffect(color: .systemOrange)
            damageEnemies(around: player.position, radius: 205, amount: 330)
        }
    }

    private func castAssassin(_ index: Int, aim: CGVector, now: TimeInterval) {
        switch index {
        case 0:
            if !enemyHero.isHidden && distance(player.position, enemyHero.position) <= 430 {
                let dx = enemyHero.position.x - player.position.x
                let dy = enemyHero.position.y - player.position.y
                let len = max(1, sqrt(dx * dx + dy * dy))
                player.position = CGPoint(x: enemyHero.position.x - dx / len * 72, y: enemyHero.position.y - dy / len * 72)
                flash(at: player.position, color: .systemPurple)
                damageEnemyHero(185)
            } else {
                dash(distance: 205, direction: aim)
            }
        case 1:
            projectileSkill(direction: aim, range: 460, color: .systemPurple, damage: 185)
        case 2:
            dash(distance: 150, direction: aim)
            veilUntil = now + 3.2
            player.alpha = 0.42
            showMessage("Veil Step")
        default:
            if !enemyHero.isHidden && distance(player.position, enemyHero.position) <= 280 {
                let missing = enemyMaxHP - enemyHP
                damageEnemyHero(220 + missing * 0.38)
                flash(at: enemyHero.position, color: .systemPink)
            } else {
                showMessage("Execution: target out of range")
            }
        }
    }

    private func castMage(_ index: Int, aim: CGVector, now: TimeInterval) {
        switch index {
        case 0:
            projectileSkill(direction: aim, range: 520, color: .systemIndigo, damage: 190)
        case 1:
            effectRing(at: player.position, radius: 185, color: .systemBlue)
            damageEnemies(around: player.position, radius: 185, amount: 125)
            if !enemyHero.isHidden && distance(player.position, enemyHero.position) <= 185 {
                enemyStunnedUntil = now + 1.35
            }
        case 2:
            flash(at: player.position, color: .white)
            dash(distance: 200, direction: aim)
            flash(at: player.position, color: .systemIndigo)
        default:
            let point = !enemyHero.isHidden ? enemyHero.position : CGPoint(x: player.position.x + aim.dx * 260, y: player.position.y + aim.dy * 260)
            meteorEffect(at: point)
            run(.sequence([.wait(forDuration: 0.55), .run { [weak self] in
                guard let self else { return }
                self.damageEnemies(around: point, radius: 220, amount: 350)
            }]))
        }
    }

    private func castMarksman(_ index: Int, aim: CGVector, now: TimeInterval) {
        switch index {
        case 0:
            projectileSkill(direction: aim, range: 620, color: .systemYellow, damage: 175)
        case 1:
            dash(distance: 155, direction: aim)
        case 2:
            attackBuffUntil = now + 6.5
            showMessage("Rapid Fire")
        default:
            if !enemyHero.isHidden && distance(player.position, enemyHero.position) <= 610 {
                for i in 0..<4 {
                    run(.sequence([.wait(forDuration: Double(i) * 0.18), .run { [weak self] in
                        guard let self, !self.enemyHero.isHidden else { return }
                        self.launchProjectile(from: self.player.position, to: self.enemyHero.position, color: .systemYellow) {
                            self.damageEnemyHero(88)
                        }
                    }]))
                }
            } else {
                showMessage("Deadeye: target out of range")
            }
        }
    }

    private func castSupport(_ index: Int, aim: CGVector, now: TimeInterval) {
        switch index {
        case 0:
            playerHP = min(heroClass.maxHP, playerHP + 245)
            effectRing(at: player.position, radius: 120, color: .systemGreen)
        case 1:
            projectileSkill(direction: aim, range: 500, color: .systemMint, damage: 105, stun: 1.55)
        case 2:
            shieldHP = min(480, shieldHP + 260)
            effectRing(at: player.position, radius: 155, color: .systemMint)
            showMessage("Guardian Aura")
        default:
            playerHP = min(heroClass.maxHP, playerHP + 390)
            shieldHP = min(520, shieldHP + 180)
            effectRing(at: player.position, radius: 260, color: .systemGreen)
            damageEnemies(around: player.position, radius: 260, amount: 130)
            if !enemyHero.isHidden && distance(player.position, enemyHero.position) <= 260 {
                enemyStunnedUntil = now + 1.0
            }
        }
    }

    override func update(_ currentTime: TimeInterval) {
        if lastFrameTime == 0 { lastFrameTime = currentTime }
        let dt = min(0.05, currentTime - lastFrameTime)
        lastFrameTime = currentTime

        if currentTime - lastWaveTime >= 6.0 && !gameOver {
            spawnWave()
            lastWaveTime = currentTime
        }

        handleRespawns(currentTime)
        guard !gameOver else { return }

        playerMana = min(heroClass.maxMana, playerMana + CGFloat(dt) * 15)
        if heroClass == .support {
            playerHP = min(heroClass.maxHP, playerHP + CGFloat(dt) * 4)
        }

        if currentTime >= veilUntil { player.alpha = 1 }

        if !player.isHidden {
            player.position.x += movement.dx * heroClass.moveSpeed * CGFloat(dt)
            player.position.y += movement.dy * heroClass.moveSpeed * CGFloat(dt)
            clampPlayer()
        }

        updateEnemyAI(currentTime, dt: dt)
        updateMinions(currentTime, dt: dt)
        updateTowers(currentTime)
        cleanupDeadMinions()
        updateHUD()
    }

    private func updateEnemyAI(_ now: TimeInterval, dt: TimeInterval) {
        guard !enemyHero.isHidden, now >= enemyStunnedUntil else { return }

        let target = player.isHidden ? CGPoint(x: 700, y: size.height / 2) : player.position
        let d = distance(enemyHero.position, target)
        let retreat = enemyHP < 340
        let desired = retreat ? CGPoint(x: size.width - 180, y: size.height / 2) : target

        if !player.isHidden && d < 145 && now >= veilUntil {
            if now - enemyLastAttackTime > 0.9 {
                enemyLastAttackTime = now
                flash(at: player.position, color: .systemRed)
                damagePlayer(88)
            }
        } else {
            move(node: enemyHero, toward: desired, speed: retreat ? 215 : 175, dt: dt)
        }

        if !player.isHidden && d < 260 && now - enemyLastAttackTime > 3.0 && now >= veilUntil {
            enemyLastAttackTime = now
            effectRing(at: enemyHero.position, radius: 170, color: .systemRed)
            damagePlayer(120)
        }
    }

    private func updateMinions(_ now: TimeInterval, dt: TimeInterval) {
        for minion in minions where minion.hp > 0 {
            let direction: CGFloat = minion.team == 0 ? 1 : -1
            let enemyTeam = minion.team == 0 ? 1 : 0

            if let other = nearestMinion(team: enemyTeam, from: minion.node.position), distance(minion.node.position, other.node.position) < 50 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.85
                    other.hp -= 34
                    flash(at: other.node.position, color: minion.team == 0 ? .systemTeal : .systemRed)
                }
                continue
            }

            if minion.team == 0 && !enemyHero.isHidden && distance(minion.node.position, enemyHero.position) < 58 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.9
                    damageEnemyHero(28)
                }
                continue
            }

            if minion.team == 1 && !player.isHidden && distance(minion.node.position, player.position) < 58 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.9
                    damagePlayer(28)
                }
                continue
            }

            let targetTower = minion.team == 0 ? enemyTower! : allyTower!
            if distance(minion.node.position, targetTower.node.position) < 58 {
                if now >= minion.nextAttack {
                    minion.nextAttack = now + 0.9
                    damageTower(targetTower, amount: 30)
                }
                continue
            }

            minion.node.position.x += direction * 88 * CGFloat(dt)
        }
    }

    private func updateTowers(_ now: TimeInterval) {
        towerAttack(allyTower, enemies: minions.filter { $0.team == 1 }, hero: enemyHero, heroHidden: enemyHero.isHidden, now: now)
        towerAttack(enemyTower, enemies: minions.filter { $0.team == 0 }, hero: player, heroHidden: player.isHidden, now: now)
    }

    private func towerAttack(_ tower: TowerUnit, enemies: [LaneMinion], hero: SKShapeNode, heroHidden: Bool, now: TimeInterval) {
        guard tower.hp > 0, now >= tower.nextAttack else { return }
        let range: CGFloat = 275

        if let minion = enemies.filter({ $0.hp > 0 && distance(tower.node.position, $0.node.position) <= range }).min(by: { distance(tower.node.position, $0.node.position) < distance(tower.node.position, $1.node.position) }) {
            tower.nextAttack = now + 1.1
            launchProjectile(from: tower.node.position, to: minion.node.position, color: tower.team == 0 ? .systemCyan : .systemPink) { [weak self, weak minion] in
                minion?.hp -= 105
                self?.cleanupDeadMinions()
            }
            return
        }

        if !heroHidden && distance(tower.node.position, hero.position) <= range {
            tower.nextAttack = now + 1.1
            launchProjectile(from: tower.node.position, to: hero.position, color: tower.team == 0 ? .systemCyan : .systemPink) { [weak self] in
                guard let self else { return }
                if tower.team == 0 { self.damageEnemyHero(125) }
                else { self.damagePlayer(125) }
            }
        }
    }

    private func spawnWave() {
        let y = size.height / 2
        for offset in [-32.0, 0.0, 32.0] {
            let blue = LaneMinion(team: 0, position: CGPoint(x: 205, y: y + offset))
            let red = LaneMinion(team: 1, position: CGPoint(x: size.width - 205, y: y + offset))
            minions.append(blue)
            minions.append(red)
            addChild(blue.node)
            addChild(red.node)
        }
    }

    private func damagePlayer(_ amount: CGFloat) {
        guard !player.isHidden else { return }
        var incoming = amount
        if shieldHP > 0 {
            let absorbed = min(shieldHP, incoming)
            shieldHP -= absorbed
            incoming -= absorbed
        }
        playerHP -= incoming
        if playerHP <= 0 {
            playerHP = 0
            redKills += 1
            player.isHidden = true
            movement = .zero
            playerRespawnAt = CACurrentMediaTime() + 4
            showMessage("Defeated • respawn in 4s")
        }
    }

    private func damageEnemyHero(_ amount: CGFloat) {
        guard !enemyHero.isHidden else { return }
        enemyHP -= amount
        if enemyHP <= 0 {
            enemyHP = 0
            blueKills += 1
            enemyHero.isHidden = true
            enemyRespawnAt = CACurrentMediaTime() + 4
            showMessage("Enemy defeated")
        }
    }

    private func damageTower(_ tower: TowerUnit?, amount: CGFloat) {
        guard let tower, tower.hp > 0 else { return }
        tower.hp -= amount
        tower.node.run(.sequence([.fadeAlpha(to: 0.35, duration: 0.06), .fadeAlpha(to: 1, duration: 0.08)]))
        if tower.hp <= 0 {
            tower.hp = 0
            tower.node.fillColor = .darkGray
            endMatch(blueWon: tower.team == 1)
        }
    }

    private func handleRespawns(_ now: TimeInterval) {
        if let time = playerRespawnAt, now >= time {
            playerRespawnAt = nil
            playerHP = heroClass.maxHP
            playerMana = heroClass.maxMana
            shieldHP = 0
            player.position = CGPoint(x: 235, y: size.height / 2)
            player.isHidden = false
            flash(at: player.position, color: playerColor())
        }
        if let time = enemyRespawnAt, now >= time {
            enemyRespawnAt = nil
            enemyHP = enemyMaxHP
            enemyHero.position = CGPoint(x: size.width - 235, y: size.height / 2)
            enemyHero.isHidden = false
            flash(at: enemyHero.position, color: .systemRed)
        }
    }

    private func endMatch(blueWon: Bool) {
        gameOver = true
        movement = .zero
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = blueWon ? "VICTORY" : "DEFEAT"
        label.fontSize = 64
        label.position = CGPoint(x: size.width / 2, y: size.height / 2 + 75)
        label.zPosition = 100
        addChild(label)

        let sub = SKLabelNode(fontNamed: "AvenirNext-Medium")
        sub.text = "Destroying the enemy tower ends this prototype match"
        sub.fontSize = 18
        sub.position = CGPoint(x: size.width / 2, y: size.height / 2 + 28)
        sub.zPosition = 100
        addChild(sub)
    }

    private func projectileSkill(direction: CGVector, range: CGFloat, color: SKColor, damage: CGFloat, stun: TimeInterval = 0) {
        let start = player.position
        let end = CGPoint(x: start.x + direction.dx * range, y: start.y + direction.dy * range)
        let projectile = SKShapeNode(circleOfRadius: 11)
        projectile.fillColor = color
        projectile.strokeColor = .white
        projectile.lineWidth = 1
        projectile.position = start
        projectile.zPosition = 15
        addChild(projectile)

        projectile.run(.sequence([.move(to: end, duration: 0.38), .run { [weak self, weak projectile] in
            guard let self, let projectile else { return }
            if !self.enemyHero.isHidden && self.distance(projectile.position, self.enemyHero.position) <= 90 {
                self.damageEnemyHero(damage)
                if stun > 0 { self.enemyStunnedUntil = CACurrentMediaTime() + stun }
            }
            for minion in self.minions where minion.team == 1 && minion.hp > 0 && self.distance(projectile.position, minion.node.position) <= 80 {
                minion.hp -= damage
            }
            self.cleanupDeadMinions()
        }, .removeFromParent()]))
    }

    private func damageEnemies(around point: CGPoint, radius: CGFloat, amount: CGFloat) {
        if !enemyHero.isHidden && distance(point, enemyHero.position) <= radius {
            damageEnemyHero(amount)
        }
        for minion in minions where minion.team == 1 && minion.hp > 0 && distance(point, minion.node.position) <= radius {
            minion.hp -= amount
        }
        cleanupDeadMinions()
    }

    private func performAttackVisual(to point: CGPoint, ranged: Bool, completion: @escaping () -> Void) {
        if ranged {
            launchProjectile(from: player.position, to: point, color: playerColor(), completion: completion)
        } else {
            flash(at: point, color: playerColor())
            completion()
        }
    }

    private func launchProjectile(from: CGPoint, to: CGPoint, color: SKColor, completion: @escaping () -> Void) {
        let orb = SKShapeNode(circleOfRadius: 7)
        orb.fillColor = color
        orb.strokeColor = .white.withAlphaComponent(0.7)
        orb.lineWidth = 1
        orb.position = from
        orb.zPosition = 14
        addChild(orb)
        orb.run(.sequence([.move(to: to, duration: 0.18), .run(completion), .removeFromParent()]))
    }

    private func dash(distance value: CGFloat, direction: CGVector) {
        let p = CGPoint(x: player.position.x + direction.dx * value, y: player.position.y + direction.dy * value)
        player.position = p
        clampPlayer()
        flash(at: player.position, color: playerColor())
    }

    private func aimDirection() -> CGVector {
        let length = sqrt(movement.dx * movement.dx + movement.dy * movement.dy)
        if length > 0.15 {
            return CGVector(dx: movement.dx / length, dy: movement.dy / length)
        }
        if !enemyHero.isHidden {
            let dx = enemyHero.position.x - player.position.x
            let dy = enemyHero.position.y - player.position.y
            let len = max(1, sqrt(dx * dx + dy * dy))
            return CGVector(dx: dx / len, dy: dy / len)
        }
        return CGVector(dx: 1, dy: 0)
    }

    private func nearestMinion(team: Int, from point: CGPoint) -> LaneMinion? {
        minions.filter { $0.team == team && $0.hp > 0 }.min { distance(point, $0.node.position) < distance(point, $1.node.position) }
    }

    private func cleanupDeadMinions() {
        for minion in minions where minion.hp <= 0 {
            minion.node.removeFromParent()
        }
        minions.removeAll { $0.hp <= 0 }
    }

    private func move(node: SKNode, toward target: CGPoint, speed: CGFloat, dt: TimeInterval) {
        let dx = target.x - node.position.x
        let dy = target.y - node.position.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        node.position.x += dx / len * speed * CGFloat(dt)
        node.position.y += dy / len * speed * CGFloat(dt)
    }

    private func clampPlayer() {
        player.position.x = min(size.width - 50, max(50, player.position.x))
        player.position.y = min(size.height - 92, max(92, player.position.y))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
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

    private func effectRing(at point: CGPoint, radius: CGFloat, color: SKColor) {
        let ring = SKShapeNode(circleOfRadius: 24)
        ring.fillColor = color.withAlphaComponent(0.18)
        ring.strokeColor = color
        ring.lineWidth = 3
        ring.position = point
        ring.zPosition = 12
        addChild(ring)
        let scale = radius / 24
        ring.run(.sequence([.group([.scale(to: scale, duration: 0.26), .fadeOut(withDuration: 0.30)]), .removeFromParent()]))
    }

    private func flash(at point: CGPoint, color: SKColor) {
        let spark = SKShapeNode(circleOfRadius: 18)
        spark.fillColor = color
        spark.strokeColor = .white
        spark.position = point
        spark.zPosition = 18
        addChild(spark)
        spark.run(.sequence([.group([.scale(to: 2.4, duration: 0.16), .fadeOut(withDuration: 0.18)]), .removeFromParent()]))
    }

    private func spinEffect(color: SKColor) {
        let ring = SKShapeNode(rectOf: CGSize(width: 215, height: 26), cornerRadius: 13)
        ring.fillColor = color.withAlphaComponent(0.35)
        ring.strokeColor = color
        ring.position = player.position
        ring.zPosition = 11
        addChild(ring)
        ring.run(.sequence([.group([.rotate(byAngle: .pi * 2, duration: 0.55), .fadeOut(withDuration: 0.55)]), .removeFromParent()]))
    }

    private func meteorEffect(at point: CGPoint) {
        let marker = SKShapeNode(circleOfRadius: 92)
        marker.fillColor = .systemRed.withAlphaComponent(0.12)
        marker.strokeColor = .systemOrange
        marker.lineWidth = 4
        marker.position = point
        marker.zPosition = 10
        addChild(marker)
        marker.run(.sequence([.scale(to: 0.72, duration: 0.52), .removeFromParent()]))

        let meteor = SKShapeNode(circleOfRadius: 30)
        meteor.fillColor = .systemOrange
        meteor.strokeColor = .white
        meteor.position = CGPoint(x: point.x + 160, y: size.height + 90)
        meteor.zPosition = 20
        addChild(meteor)
        meteor.run(.sequence([.move(to: point, duration: 0.55), .group([.scale(to: 3.4, duration: 0.18), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }

    private func updateHUD() {
        let hpRatio = max(0, min(1, playerHP / heroClass.maxHP))
        playerHPBar.xScale = hpRatio
        let manaRatio = max(0, min(1, playerMana / heroClass.maxMana))
        playerManaBar.xScale = manaRatio
        enemyHPBar.xScale = max(0, min(1, enemyHP / enemyMaxHP))

        let shieldText = shieldHP > 0 ? "  Shield \(Int(shieldHP))" : ""
        statusLabel.text = "\(heroClass.rawValue)  HP \(Int(playerHP))/\(Int(heroClass.maxHP))  Mana \(Int(playerMana))/\(Int(heroClass.maxMana))\(shieldText)"
        scoreLabel.text = "BLUE \(blueKills)  •  \(redKills) RED"
        towerLabel.text = "Ally Tower \(Int(max(0, allyTower.hp)))   |   Enemy Tower \(Int(max(0, enemyTower.hp)))"
    }

    private func showMessage(_ text: String) {
        messageToken += 1
        let token = messageToken
        messageLabel.removeAllActions()
        messageLabel.text = text
        messageLabel.alpha = 1
        messageLabel.run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
            guard let self, self.messageToken == token else { return }
            self.messageLabel.run(.fadeOut(withDuration: 0.25))
        }]))
    }
}
