import Foundation
import SwiftUI

struct CreatureSpecies: Identifiable, Hashable {
    let id: String
    let name: String
    let element: Element
    let baseHP: Int
    let basePower: Int
    let glyph: String
    let description: String

    enum Element: String, CaseIterable {
        case ember, tide, grove, storm, stone, spirit

        var tint: Color {
            switch self {
            case .ember: .orange
            case .tide: .cyan
            case .grove: .green
            case .storm: .yellow
            case .stone: .brown
            case .spirit: .purple
            }
        }

        var icon: String {
            switch self {
            case .ember: "flame.fill"
            case .tide: "drop.fill"
            case .grove: "leaf.fill"
            case .storm: "bolt.fill"
            case .stone: "mountain.2.fill"
            case .spirit: "sparkles"
            }
        }
    }
}

struct Creature: Identifiable, Hashable {
    let id: UUID
    let species: CreatureSpecies
    var level: Int
    var currentHP: Int
    var nickname: String?

    init(species: CreatureSpecies, level: Int) {
        self.id = UUID()
        self.species = species
        self.level = level
        self.currentHP = species.baseHP + level * 6
    }

    var maxHP: Int { species.baseHP + level * 6 }
    var power: Int { species.basePower + level * 3 }
    var displayName: String { nickname ?? species.name }
}

struct Skill: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let multiplier: Double
    let element: CreatureSpecies.Element
}

struct Quest: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    var progress: Int
    let target: Int
    let reward: Int
    var isClaimed: Bool = false
}

struct WorldMonster: Identifiable, Hashable {
    let id: UUID
    let creature: Creature
    let x: Double
    let y: Double
}

extension CreatureSpecies {
    static let catalog: [CreatureSpecies] = [
        .init(id: "cindrake", name: "Cindrake", element: .ember, baseHP: 62, basePower: 18, glyph: "C", description: "A tiny furnace-backed drake that stores heat in rune-like scales."),
        .init(id: "mosskin", name: "Mosskin", element: .grove, baseHP: 72, basePower: 14, glyph: "M", description: "A round forest guardian with antler buds and living moss armor."),
        .init(id: "voltwing", name: "Voltwing", element: .storm, baseHP: 55, basePower: 21, glyph: "V", description: "A swift glider that charges translucent wing-fins during storms."),
        .init(id: "aqualume", name: "Aqualume", element: .tide, baseHP: 68, basePower: 16, glyph: "A", description: "A lantern-tailed river spirit that bends water into protective rings."),
        .init(id: "craglet", name: "Craglet", element: .stone, baseHP: 84, basePower: 13, glyph: "R", description: "A stubborn crystal-shelled burrower prized by mountain tamers."),
        .init(id: "whispling", name: "Whispling", element: .spirit, baseHP: 58, basePower: 20, glyph: "W", description: "A curious dusk spirit that communicates through floating light motes.")
    ]
}
