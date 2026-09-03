import Foundation

enum ChartGenerator {
    static func generateAll(analysis: AudioAnalysis) -> [GeneratedChart] {
        ChartDifficulty.allCases.map {
            GeneratedChart(
                difficulty: $0,
                level: suggestedLevel(for: $0, analysis: analysis),
                noteText: generate(difficulty: $0, analysis: analysis)
            )
        }
    }

    static func maidata(title: String, artist: String, analysis: AudioAnalysis, charts: [GeneratedChart]) -> String {
        var lines: [String] = []
        lines.append("&title=\(escape(title.isEmpty ? "Untitled" : title))")
        lines.append("&artist=\(escape(artist.isEmpty ? "Unknown" : artist))")
        lines.append("&wholebpm=\(String(format: "%.3f", analysis.bpm))")
        lines.append("&first=\(String(format: "%.4f", analysis.firstBeat))")
        lines.append("&des=MaiChart Maker")
        lines.append("&smsg=Auto-generated from onset and beat analysis; edit to taste.")

        for chart in charts.sorted(by: { $0.difficulty.rawValue < $1.difficulty.rawValue }) {
            lines.append("&lv_\(chart.difficulty.rawValue)=\(chart.level)")
            lines.append("&des_\(chart.difficulty.rawValue)=MaiChart Maker")
        }

        for chart in charts.sorted(by: { $0.difficulty.rawValue < $1.difficulty.rawValue }) {
            lines.append("&inote_\(chart.difficulty.rawValue)=")
            lines.append(chart.noteText)
        }
        return lines.joined(separator: "\n")
    }

    private static func suggestedLevel(for difficulty: ChartDifficulty, analysis: AudioAnalysis) -> String {
        let density = Double(analysis.onsets.count) / max(1, analysis.duration)
        let base: Double
        switch difficulty {
        case .easy: base = 1.8
        case .basic: base = 3.6
        case .advanced: base = 6.4
        case .expert: base = 9.2
        case .master: base = 11.4
        case .remaster: base = 12.5
        }
        let tempoBonus = max(0, (analysis.bpm - 110) / 45)
        let densityBonus = min(2.0, density / 2.5)
        let value = min(14.9, base + tempoBonus + densityBonus)
        let rounded = (value * 10).rounded() / 10
        if rounded >= 10 {
            let whole = Int(floor(rounded))
            return rounded - Double(whole) >= 0.6 ? "\(whole)+" : "\(whole)"
        }
        return "\(max(1, Int(rounded.rounded())))"
    }

    private static func generate(difficulty: ChartDifficulty, analysis: AudioAnalysis) -> String {
        let bpm = max(1, analysis.bpm)
        let secondsPerStep = 60.0 / bpm / 4.0
        let totalSteps = max(1, Int(ceil(max(0, analysis.duration - analysis.firstBeat) / secondsPerStep)))
        let strengths = normalize(analysis.strengths)

        var onsetByStep: [Int: Double] = [:]
        for (index, onset) in analysis.onsets.enumerated() where onset >= analysis.firstBeat {
            let step = Int(((onset - analysis.firstBeat) / secondsPerStep).rounded())
            guard step >= 0 && step < totalSteps else { continue }
            onsetByStep[step] = max(onsetByStep[step] ?? 0, strengths.indices.contains(index) ? strengths[index] : 0.5)
        }

        var tokens = Array(repeating: "", count: totalSteps + 1)
        var lane = 1 + difficulty.rawValue % 8
        var lastPlaced = -999
        var noteNumber = 0

        for step in 0..<totalSteps {
            let isBeat = step % 4 == 0
            let strength = onsetByStep[step] ?? 0
            let accent = isBeat ? 0.32 : 0.0
            let score = min(1, strength + accent)

            let deterministic = pseudo(step: step, salt: difficulty.rawValue)
            let threshold = 1.03 - difficulty.density
            let candidate = score > threshold || (isBeat && deterministic < difficulty.density * 0.48)
            guard candidate else { continue }
            guard step - lastPlaced >= difficulty.minimumGapSteps else { continue }

            lane = nextLane(lane: lane, step: step, difficulty: difficulty)
            noteNumber += 1
            let strong = strength > 0.72
            let veryStrong = strength > 0.9

            switch difficulty {
            case .easy, .basic:
                tokens[step] = "\(lane)"
            case .advanced:
                if strong && noteNumber % 10 == 0 {
                    tokens[step] = "\(lane)h[4:1]"
                } else {
                    tokens[step] = "\(lane)"
                }
            case .expert:
                if veryStrong && noteNumber % 8 == 0 {
                    let other = opposite(lane)
                    tokens[step] = "\(lane)/\(other)"
                } else if strong && noteNumber % 7 == 0 {
                    tokens[step] = "\(lane)h[8:1]"
                } else {
                    tokens[step] = "\(lane)"
                }
            case .master:
                if veryStrong && noteNumber % 6 == 0 {
                    let dest = wrapped(lane + 3)
                    tokens[step] = "\(lane)-\(dest)[8:1]"
                } else if strong && noteNumber % 5 == 0 {
                    tokens[step] = "\(lane)b"
                } else if noteNumber % 11 == 0 {
                    tokens[step] = "\(lane)/\(opposite(lane))"
                } else {
                    tokens[step] = "\(lane)"
                }
            case .remaster:
                if veryStrong && noteNumber % 4 == 0 {
                    let dest = wrapped(lane + (noteNumber % 2 == 0 ? 3 : 5))
                    tokens[step] = "\(lane)-\(dest)[8:1]"
                } else if strong && noteNumber % 5 == 0 {
                    tokens[step] = "\(lane)b/\(opposite(lane))"
                } else if noteNumber % 7 == 0 {
                    tokens[step] = "\(lane)h[8:1]"
                } else {
                    tokens[step] = "\(lane)"
                }
            }

            lastPlaced = step
        }

        var body = "(\(String(format: "%.3f", bpm))){16},\n"
        for i in tokens.indices {
            body += tokens[i]
            body += ","
            if (i + 1) % 16 == 0 { body += "\n" }
        }
        body += "\nE"
        return body
    }

    private static func normalize(_ values: [Double]) -> [Double] {
        guard let maxValue = values.max(), maxValue > 0 else { return values.map { _ in 0 } }
        return values.map { min(1, max(0, $0 / maxValue)) }
    }

    private static func nextLane(lane: Int, step: Int, difficulty: ChartDifficulty) -> Int {
        let delta: Int
        switch difficulty {
        case .easy: delta = step % 8 < 4 ? 1 : -1
        case .basic: delta = (step / 2) % 2 == 0 ? 2 : -1
        case .advanced: delta = [1, 2, -1, 3][abs(step) % 4]
        case .expert: delta = [2, -3, 1, 4][abs(step) % 4]
        case .master, .remaster: delta = [3, -2, 4, -3, 1][abs(step) % 5]
        }
        return wrapped(lane + delta)
    }

    private static func opposite(_ lane: Int) -> Int { wrapped(lane + 4) }

    private static func wrapped(_ lane: Int) -> Int {
        let zero = ((lane - 1) % 8 + 8) % 8
        return zero + 1
    }

    private static func pseudo(step: Int, salt: Int) -> Double {
        let value = abs(sin(Double(step * 92821 + salt * 68917))) * 10_000
        return value - floor(value)
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+%\\")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
