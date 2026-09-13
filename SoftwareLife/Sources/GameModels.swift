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
    var bankrupt: Bool = false
    var skippedTurns: Int = 0

    var liquidAssets: Int { cash + equityValue + propertyValue }
}

enum TileKind: String, Codable, CaseIterable {
    case launch
    case project
    case career
    case incident
    case market
    case skill
    case wellbeing
    case openSource
    case aiFrontier
    case tax
}

enum TechDistrict: String, Codable, CaseIterable, Identifiable {
    case frontend = "Frontend Row"
    case backend = "Backend Borough"
    case mobile = "Mobile Mile"
    case dataAI = "Data & AI District"
    case cloud = "Cloud Heights"
    case devTools = "DevTools Quarter"
    case creator = "SaaS Avenue"
    case security = "Security Sector"

    var id: String { rawValue }
}

struct BoardTile: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let kind: TileKind
    let subtitle: String
    let district: TechDistrict?
    let purchasePrice: Int
    let baseRevenue: Int

    init(
        id: Int,
        title: String,
        kind: TileKind,
        subtitle: String,
        district: TechDistrict? = nil,
        purchasePrice: Int = 0,
        baseRevenue: Int = 0
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.subtitle = subtitle
        self.district = district
        self.purchasePrice = purchasePrice
        self.baseRevenue = baseRevenue
    }

    var isOwnable: Bool { kind == .project && purchasePrice > 0 }
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
        case .aiAcceleration: 1.12
        case .recession: 0.82
        case .platformShift: 1.05
        }
    }

    var revenueMultiplier: Double {
        switch self {
        case .hiringBoom: 1.10
        case .fundingWinter: 0.82
        case .aiAcceleration: 1.24
        case .recession: 0.72
        case .platformShift: 1.14
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

enum DealKind: String, Codable {
    case acquire
    case scale
}

struct DealOffer: Identifiable, Equatable {
    let id = UUID()
    let tileID: Int
    let kind: DealKind
    let cost: Int
    let projectedRevenue: Int
}
