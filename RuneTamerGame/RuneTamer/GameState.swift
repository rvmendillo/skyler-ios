import Foundation
import SwiftUI

@MainActor
final class GameState: ObservableObject {
    enum Screen { case world, collection, quests }

    @Published var screen: Screen = .world
    @Published var playerLevel = 1
    @Published var exp = 0
    @Published var coins = 120
    @Published var potions = 4
    @Published var captures = 0
    @Published var activeCreature: Creature
    @Published var collection: [Creature]
    @Published var encounter: Creature?
    @Published var battleMessage = ""
    @Published var playerHP = 100
    @Published var quests: [Quest] = [
        Quest(title: "First Bond", detail: "Capture 1 wild creature", progress: 0, target: 1, reward: 80),
        Quest(title: "Rune Scout", detail: "Win 3 encounters", progress: 0, target: 3, reward: 140)
    ]
    @Published var wins = 0

    let skills: [Skill] = [
        Skill(name: "Rune Strike", icon: "sparkles", multiplier: 1.0, element: .spirit),
        Skill(name: "Element Burst", icon: "burst.fill", multiplier: 1.25, element: .ember),
        Skill(name: "Quick Fang", icon: "hare.fill", multiplier: 0.85, element: .storm),
        Skill(name: "Guard Break", icon: "shield.slash.fill", multiplier: 1.1, element: .stone)
    ]

    init() {
        let starter = Creature(species: CreatureSpecies.catalog[1], level: 5)
        activeCreature = starter
        collection = [starter]
    }

    func beginEncounter(_ creature: Creature) {
        encounter = creature
        battleMessage = "A wild \(creature.species.name) appeared!"
    }

    func useSkill(_ skill: Skill) {
        guard var foe = encounter else { return }
        let variance = Int.random(in: -2...3)
        let damage = max(3, Int(Double(activeCreature.power) * skill.multiplier) + variance)
        foe.currentHP = max(0, foe.currentHP - damage)
        battleMessage = "\(activeCreature.displayName) used \(skill.name) for \(damage)!"

        if foe.currentHP <= 0 {
            encounter = nil
            wins += 1
            gainXP(35 + foe.level * 4)
            coins += 18 + foe.level * 3
            updateQuests()
            return
        }

        let retaliation = max(2, foe.power / 3 + Int.random(in: 0...4))
        playerHP = max(1, playerHP - retaliation)
        encounter = foe
    }

    func tryCapture() {
        guard let foe = encounter else { return }
        let missingRatio = 1.0 - Double(foe.currentHP) / Double(foe.maxHP)
        let chance = min(0.86, 0.28 + missingRatio * 0.58)
        if Double.random(in: 0...1) < chance {
            collection.append(foe)
            captures += 1
            battleMessage = "Bond formed with \(foe.species.name)!"
            encounter = nil
            coins += 10
            updateQuests()
        } else {
            battleMessage = "The bond rune shattered. Weaken it first!"
            playerHP = max(1, playerHP - max(2, foe.power / 4))
        }
    }

    func heal() {
        guard potions > 0 else {
            battleMessage = "No potions left."
            return
        }
        potions -= 1
        playerHP = min(100, playerHP + 42)
        battleMessage = "Recovered vitality."
    }

    func setActive(_ creature: Creature) {
        activeCreature = creature
        screen = .world
    }

    func claim(_ quest: Quest) {
        guard let idx = quests.firstIndex(where: { $0.id == quest.id }), quests[idx].progress >= quests[idx].target, !quests[idx].isClaimed else { return }
        coins += quests[idx].reward
        quests[idx].isClaimed = true
    }

    private func gainXP(_ amount: Int) {
        exp += amount
        let needed = playerLevel * 100
        if exp >= needed {
            exp -= needed
            playerLevel += 1
            playerHP = 100
        }
    }

    private func updateQuests() {
        if quests.indices.contains(0) { quests[0].progress = min(quests[0].target, captures) }
        if quests.indices.contains(1) { quests[1].progress = min(quests[1].target, wins) }
    }
}
