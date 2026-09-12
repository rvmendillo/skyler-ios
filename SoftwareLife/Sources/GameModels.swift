import Foundation

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var cash: Int
    var salary: Int
    var reputation: Int
    var wellbeing: Int
    var skill: Int
    var position: Int
    var recurringIncome: Int
    var equityValue: Int
    var propertyValue: Int

    var netWorth: Int { cash + equityValue + propertyValue }
    var legacyScore: Int { netWorth + reputation * 1_000 + wellbeing * 800 + skill * 900 + recurringIncome * 12 }
}

enum TileKind: String, Codable, CaseIterable {
    case career, startup, market, property, skill, sideProject, event, wellbeing, openSource, aiFrontier
}

struct BoardTile: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let kind: TileKind
    let subtitle: String
}

enum IndustryEra: String, Codable, CaseIterable {
    case hiringBoom = "Hiring Boom"
    case fundingWinter = "Funding Winter"
    case aiAcceleration = "AI Acceleration"
    case recession = "Tech Recession"
    case platformShift = "Platform Shift"

    var salaryMultiplier: Double {
        switch self {
        case .hiringBoom: 1.20
        case .fundingWinter: 0.95
        case .aiAcceleration: 1.15
        case .recession: 0.82
        case .platformShift: 1.05
        }
    }

    var startupMultiplier: Double {
        switch self {
        case .hiringBoom: 1.10
        case .fundingWinter: 0.65
        case .aiAcceleration: 1.45
        case .recession: 0.70
        case .platformShift: 1.25
        }
    }
}

struct IndustryEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let body: String
    let cashDelta: Int
    let reputationDelta: Int
    let wellbeingDelta: Int
    let equityPercentChange: Int
}
