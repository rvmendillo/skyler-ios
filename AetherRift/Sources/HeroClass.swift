import Foundation

struct SkillSpec: Identifiable {
    let id = UUID()
    let name: String
    let cooldown: TimeInterval
    let mana: CGFloat
}

enum HeroClass: String, CaseIterable, Identifiable {
    case tank = "Tank"
    case fighter = "Fighter"
    case assassin = "Assassin"
    case mage = "Mage"
    case marksman = "Marksman"
    case support = "Support"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tank: return "shield.fill"
        case .fighter: return "flame.fill"
        case .assassin: return "bolt.fill"
        case .mage: return "sparkles"
        case .marksman: return "scope"
        case .support: return "cross.fill"
        }
    }

    var tagline: String {
        switch self {
        case .tank: return "Frontline control and protection"
        case .fighter: return "Durable melee pressure"
        case .assassin: return "Burst, mobility, execution"
        case .mage: return "Ranged magic and area control"
        case .marksman: return "Sustained ranged damage"
        case .support: return "Healing, shielding, crowd control"
        }
    }

    var maxHP: CGFloat {
        switch self {
        case .tank: return 1650
        case .fighter: return 1325
        case .assassin: return 980
        case .mage: return 1020
        case .marksman: return 950
        case .support: return 1120
        }
    }

    var maxMana: CGFloat {
        switch self {
        case .fighter: return 560
        case .tank: return 520
        case .assassin: return 470
        case .mage: return 780
        case .marksman: return 520
        case .support: return 720
        }
    }

    var attackDamage: CGFloat {
        switch self {
        case .tank: return 72
        case .fighter: return 96
        case .assassin: return 112
        case .mage: return 66
        case .marksman: return 92
        case .support: return 58
        }
    }

    var attackRange: CGFloat {
        switch self {
        case .tank, .fighter, .assassin: return 120
        case .mage, .support: return 310
        case .marksman: return 390
        }
    }

    var moveSpeed: CGFloat {
        switch self {
        case .tank: return 245
        case .fighter: return 260
        case .assassin: return 310
        case .mage: return 270
        case .marksman: return 275
        case .support: return 265
        }
    }

    var skills: [SkillSpec] {
        switch self {
        case .tank:
            return [
                SkillSpec(name: "Shield Bash", cooldown: 5, mana: 45),
                SkillSpec(name: "Iron Rush", cooldown: 8, mana: 60),
                SkillSpec(name: "Bulwark", cooldown: 11, mana: 70),
                SkillSpec(name: "Titan Quake", cooldown: 28, mana: 120)
            ]
        case .fighter:
            return [
                SkillSpec(name: "Cleave", cooldown: 4, mana: 35),
                SkillSpec(name: "Lunge", cooldown: 7, mana: 50),
                SkillSpec(name: "Battle Surge", cooldown: 10, mana: 60),
                SkillSpec(name: "Cyclone", cooldown: 25, mana: 105)
            ]
        case .assassin:
            return [
                SkillSpec(name: "Blink Strike", cooldown: 6, mana: 45),
                SkillSpec(name: "Shadow Blade", cooldown: 5, mana: 40),
                SkillSpec(name: "Veil Step", cooldown: 10, mana: 65),
                SkillSpec(name: "Execution", cooldown: 26, mana: 110)
            ]
        case .mage:
            return [
                SkillSpec(name: "Arc Bolt", cooldown: 4, mana: 50),
                SkillSpec(name: "Frost Ring", cooldown: 8, mana: 75),
                SkillSpec(name: "Phase Step", cooldown: 10, mana: 70),
                SkillSpec(name: "Meteor Storm", cooldown: 30, mana: 135)
            ]
        case .marksman:
            return [
                SkillSpec(name: "Piercing Shot", cooldown: 5, mana: 45),
                SkillSpec(name: "Combat Roll", cooldown: 8, mana: 50),
                SkillSpec(name: "Rapid Fire", cooldown: 12, mana: 65),
                SkillSpec(name: "Deadeye Volley", cooldown: 27, mana: 115)
            ]
        case .support:
            return [
                SkillSpec(name: "Heal Pulse", cooldown: 7, mana: 65),
                SkillSpec(name: "Binding Orb", cooldown: 7, mana: 60),
                SkillSpec(name: "Guardian Aura", cooldown: 12, mana: 80),
                SkillSpec(name: "Sanctuary", cooldown: 30, mana: 135)
            ]
        }
    }
}
