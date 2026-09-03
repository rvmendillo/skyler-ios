import Foundation

struct TempoPoint: Sendable, Hashable {
    let beat: Double
    let bpm: Double
}

struct AudioAnalysis: Sendable {
    let duration: Double
    let bpm: Double
    let firstBeat: Double
    let onsets: [Double]
    let strengths: [Double]
    let beatPositions: [Double]?
    let durationBeats: Double?
    let tempoMap: [TempoPoint]
    let exactScoreTiming: Bool
    let drumBeatPositions: [Double]
    let drumStrengths: [Double]
    let drumNoteNumbers: [UInt8]
    let melodyBeatPositions: [Double]
    let melodyPitches: [UInt8]
    let melodyStrengths: [Double]

    init(
        duration: Double,
        bpm: Double,
        firstBeat: Double,
        onsets: [Double],
        strengths: [Double],
        beatPositions: [Double]? = nil,
        durationBeats: Double? = nil,
        tempoMap: [TempoPoint] = [],
        exactScoreTiming: Bool = false,
        drumBeatPositions: [Double] = [],
        drumStrengths: [Double] = [],
        drumNoteNumbers: [UInt8] = [],
        melodyBeatPositions: [Double] = [],
        melodyPitches: [UInt8] = [],
        melodyStrengths: [Double] = []
    ) {
        self.duration = duration
        self.bpm = bpm
        self.firstBeat = firstBeat
        self.onsets = onsets
        self.strengths = strengths
        self.beatPositions = beatPositions
        self.durationBeats = durationBeats
        self.tempoMap = tempoMap
        self.exactScoreTiming = exactScoreTiming
        self.drumBeatPositions = drumBeatPositions
        self.drumStrengths = drumStrengths
        self.drumNoteNumbers = drumNoteNumbers
        self.melodyBeatPositions = melodyBeatPositions
        self.melodyPitches = melodyPitches
        self.melodyStrengths = melodyStrengths
    }
    func replacingFirstBeat(_ value: Double) -> AudioAnalysis {
        AudioAnalysis(
            duration: duration,
            bpm: bpm,
            firstBeat: max(0, value),
            onsets: onsets,
            strengths: strengths,
            beatPositions: beatPositions,
            durationBeats: durationBeats,
            tempoMap: tempoMap,
            exactScoreTiming: exactScoreTiming,
            drumBeatPositions: drumBeatPositions,
            drumStrengths: drumStrengths,
            drumNoteNumbers: drumNoteNumbers,
            melodyBeatPositions: melodyBeatPositions,
            melodyPitches: melodyPitches,
            melodyStrengths: melodyStrengths
        )
    }
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
    case file = "Audio"
    case score = "Score"
    case youtube = "YouTube"
    var id: String { rawValue }
}

struct GMInstrument: Identifiable, Hashable {
    let program: Int
    let name: String
    var id: Int { program }

    static let popular: [GMInstrument] = [
        .init(program: 0, name: "Acoustic Grand Piano"),
        .init(program: 1, name: "Bright Acoustic Piano"),
        .init(program: 4, name: "Electric Piano"),
        .init(program: 6, name: "Harpsichord"),
        .init(program: 16, name: "Drawbar Organ"),
        .init(program: 24, name: "Nylon Guitar"),
        .init(program: 25, name: "Steel Guitar"),
        .init(program: 32, name: "Acoustic Bass"),
        .init(program: 40, name: "Violin"),
        .init(program: 42, name: "Cello"),
        .init(program: 48, name: "String Ensemble"),
        .init(program: 52, name: "Choir Aahs"),
        .init(program: 56, name: "Trumpet"),
        .init(program: 60, name: "French Horn"),
        .init(program: 64, name: "Soprano Sax"),
        .init(program: 73, name: "Flute"),
        .init(program: 80, name: "Square Lead"),
        .init(program: 88, name: "Fantasia Pad")
    ]
}
