import Foundation

struct AudioAnalysis: Sendable {
    let duration: Double
    let bpm: Double
    let firstBeat: Double
    let onsets: [Double]
    let strengths: [Double]
}

enum ChartDifficulty: Int, CaseIterable, Identifiable, Sendable {
    case easy = 1
    case basic = 2
    case advanced = 3
    case expert = 4
    case master = 5
    case remaster = 6

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .easy: return "EASY"
        case .basic: return "BASIC"
        case .advanced: return "ADVANCED"
        case .expert: return "EXPERT"
        case .master: return "MASTER"
        case .remaster: return "Re:MASTER"
        }
    }

    var defaultLevel: String {
        switch self {
        case .easy: return "2"
        case .basic: return "4"
        case .advanced: return "7"
        case .expert: return "10+"
        case .master: return "12+"
        case .remaster: return "13+"
        }
    }

    var density: Double {
        switch self {
        case .easy: return 0.24
        case .basic: return 0.36
        case .advanced: return 0.52
        case .expert: return 0.72
        case .master: return 0.88
        case .remaster: return 1.00
        }
    }

    var minimumGapSteps: Int {
        switch self {
        case .easy: return 4
        case .basic: return 3
        case .advanced: return 2
        case .expert: return 1
        case .master, .remaster: return 1
        }
    }
}

struct GeneratedChart: Identifiable, Sendable {
    let difficulty: ChartDifficulty
    var level: String
    var noteText: String

    var id: Int { difficulty.id }
}

enum ImportSource: String, CaseIterable, Identifiable {
    case file = "Audio File"
    case youtube = "YouTube"
    var id: String { rawValue }
}
