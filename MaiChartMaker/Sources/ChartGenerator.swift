import Foundation

enum ChartGenerator {
    static func generateAll(analysis: AudioAnalysis) -> [GeneratedChart] {
        // One musical "idea seed" per generation pass. Every difficulty shares
        // the same song structure but interprets it differently.
        let generationSeed = UInt64.random(in: UInt64.min...UInt64.max)

        return ChartDifficulty.allCases.map { difficulty in
            GeneratedChart(
                difficulty: difficulty,
                level: suggestedLevel(for: difficulty, analysis: analysis),
                noteText: generate(
                    difficulty: difficulty,
                    analysis: analysis,
                    seed: generationSeed &+ UInt64(difficulty.rawValue) &* 0x9E3779B97F4A7C15
                )
            )
        }
    }

    static func maidata(
        title: String,
        artist: String,
        analysis: AudioAnalysis,
        charts: [GeneratedChart],
        trackFilename: String = "track.mp3"
    ) -> String {
        var lines: [String] = []
        lines.append("&title=\(escape(title.isEmpty ? "Untitled" : title))")
        lines.append("&artist=\(escape(artist.isEmpty ? "Unknown" : artist))")
        lines.append("&wholebpm=\(String(format: "%.3f", analysis.bpm))")
        lines.append("&first=\(String(format: "%.4f", analysis.firstBeat))")
        lines.append("&track=\(trackFilename)")
        lines.append("&des=MaiChart Maker")
        lines.append("&smsg=Humanized phrase-aware auto chart; remix or edit freely.")

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

    private enum PhraseMotion: CaseIterable {
        case orbitCW
        case orbitCCW
        case mirror
        case bounce
        case diagonal
        case answer
        case spiral
        case scattered
    }

    private enum Gesture {
        case tap
        case hold
        case double
        case breakTap
        case slide
    }

    private static func generate(
        difficulty: ChartDifficulty,
        analysis: AudioAnalysis,
        seed: UInt64
    ) -> String {
        var rng = SplitMix64(seed: seed)
        let bpm = max(1, analysis.bpm)
        let secondsPerStep = 60.0 / bpm / 4.0
        let totalSteps = max(
            1,
            Int(ceil(max(0, analysis.duration - analysis.firstBeat) / secondsPerStep))
        )

        let normalizedStrengths = normalize(analysis.strengths)
        var onsetByStep: [Int: Double] = [:]

        for (index, onset) in analysis.onsets.enumerated() where onset >= analysis.firstBeat {
            let step = Int(((onset - analysis.firstBeat) / secondsPerStep).rounded())
            guard step >= 0 && step < totalSteps else { continue }
            let strength = normalizedStrengths.indices.contains(index)
                ? normalizedStrengths[index]
                : 0.5
            onsetByStep[step] = max(onsetByStep[step] ?? 0, strength)
        }

        let phraseLength = 64 // four 4/4 bars at 16th-note resolution
        let phraseCount = max(1, Int(ceil(Double(totalSteps) / Double(phraseLength))))
        var tokens = Array(repeating: "", count: totalSteps + 1)

        var lane = rng.int(in: 1...8)
        var lastPlaced = -999
        var lastGesture: Gesture = .tap
        var previousMotion: PhraseMotion?
        var previousMotif: [Int] = []
        var noteNumber = 0

        for phrase in 0..<phraseCount {
            let start = phrase * phraseLength
            let end = min(totalSteps, start + phraseLength)
            guard start < end else { continue }

            let phraseStrength = averageOnsetStrength(
                start: start,
                end: end,
                onsetByStep: onsetByStep
            )

            var motion = PhraseMotion.allCases[rng.int(in: 0..<(PhraseMotion.allCases.count))]
            if motion == previousMotion {
                motion = PhraseMotion.allCases[
                    (PhraseMotion.allCases.firstIndex(of: motion)! + 1 + rng.int(in: 0...2))
                    % PhraseMotion.allCases.count
                ]
            }

            var motif = motifFor(
                motion: motion,
                difficulty: difficulty,
                rng: &rng
            )

            // Human-chart-like callback: occasionally reuse a previous idea but
            // transpose/mirror it instead of repeating it verbatim.
            if phrase > 0, !previousMotif.isEmpty, rng.chance(difficulty.rawValue >= 4 ? 0.30 : 0.18) {
                motif = previousMotif.map { rng.chance(0.5) ? -$0 : $0 }
                if rng.chance(0.45) { motif.rotateLeft(by: rng.int(in: 1...max(1, motif.count - 1))) }
            }

            previousMotion = motion
            previousMotif = motif

            let breathingRoom = phraseStrength < 0.30
                ? rng.int(in: 4...12)
                : rng.int(in: 0...6)
            let restStart = start + rng.int(in: 0...max(0, phraseLength - breathingRoom - 1))
            let restEnd = min(end, restStart + breathingRoom)

            var motifIndex = 0

            for step in start..<end {
                let strength = onsetByStep[step] ?? 0
                let sixteenth = step % 4
                let beat = step % 16

                let accent: Double
                switch sixteenth {
                case 0: accent = 0.23
                case 2: accent = difficulty.rawValue >= 3 ? 0.09 : 0.03
                default: accent = difficulty.rawValue >= 4 ? 0.05 : 0
                }

                let barAccent = beat == 0 ? 0.10 : 0
                let jitter = rng.double(in: -0.08...0.10)
                let score = strength + accent + barAccent + jitter

                let threshold: Double
                switch difficulty {
                case .easy: threshold = 0.76
                case .basic: threshold = 0.67
                case .advanced: threshold = 0.56
                case .expert: threshold = 0.46
                case .master: threshold = 0.38
                case .remaster: threshold = 0.32
                }

                var candidate = score >= threshold

                // Musical pickup/syncopation: harder charts may deliberately
                // place a weak-note response between stronger detected hits.
                if !candidate, difficulty.rawValue >= 4, sixteenth != 0 {
                    let nearbyStrong = max(
                        onsetByStep[step - 1] ?? 0,
                        onsetByStep[step + 1] ?? 0
                    )
                    candidate = nearbyStrong > 0.72 && rng.chance(0.18 + Double(difficulty.rawValue) * 0.025)
                }

                // Easy/Basic keep strong pulse anchors without machine-gunning
                // every beat.
                if !candidate, sixteenth == 0, rng.chance(difficulty.density * 0.26) {
                    candidate = true
                }

                if step >= restStart && step < restEnd, strength < 0.82 {
                    candidate = false
                }

                guard candidate else { continue }
                guard step - lastPlaced >= difficulty.minimumGapSteps else { continue }

                let delta = motif[motifIndex % motif.count]
                motifIndex += 1

                lane = wrapped(lane + delta)

                // Add a small human positional surprise, but not on every note.
                if difficulty.rawValue >= 3, rng.chance(0.16) {
                    lane = wrapped(lane + (rng.chance(0.5) ? 1 : -1) * rng.int(in: 1...2))
                }

                noteNumber += 1
                let gesture = chooseGesture(
                    difficulty: difficulty,
                    strength: strength,
                    phraseStrength: phraseStrength,
                    lastGesture: lastGesture,
                    noteNumber: noteNumber,
                    rng: &rng
                )

                tokens[step] = token(
                    gesture: gesture,
                    lane: lane,
                    strength: strength,
                    difficulty: difficulty,
                    rng: &rng
                )

                lastGesture = gesture
                lastPlaced = step
            }
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

    private static func motifFor(
        motion: PhraseMotion,
        difficulty: ChartDifficulty,
        rng: inout SplitMix64
    ) -> [Int] {
        let base: [Int]
        switch motion {
        case .orbitCW:
            base = [1, 1, 2, 1, -1, 1]
        case .orbitCCW:
            base = [-1, -1, -2, -1, 1, -1]
        case .mirror:
            base = [2, -2, 3, -3, 1, -1]
        case .bounce:
            base = [3, -2, 2, -3, 1, 2]
        case .diagonal:
            base = [4, -1, 3, -4, 2, -2]
        case .answer:
            base = [1, 2, 1, -3, -1, -2, -1, 3]
        case .spiral:
            base = [1, 2, 2, 3, -1, -2, -3]
        case .scattered:
            base = [rng.int(in: -4...4), rng.int(in: -3...3), rng.int(in: -4...4), rng.int(in: -2...2)]
        }

        if difficulty.rawValue <= 2 {
            return base.map {
                let sign = $0 < 0 ? -1 : 1
                return sign * min(2, max(1, abs($0)))
            }
        }

        return base.map { $0 == 0 ? (rng.chance(0.5) ? 1 : -1) : $0 }
    }

    private static func chooseGesture(
        difficulty: ChartDifficulty,
        strength: Double,
        phraseStrength: Double,
        lastGesture: Gesture,
        noteNumber: Int,
        rng: inout SplitMix64
    ) -> Gesture {
        guard difficulty.rawValue >= 3 else { return .tap }

        let strong = strength > 0.68
        let veryStrong = strength > 0.88
        let roll = rng.double(in: 0...1)

        var gesture: Gesture = .tap

        switch difficulty {
        case .easy, .basic:
            gesture = .tap

        case .advanced:
            if strong && roll < 0.11 { gesture = .hold }

        case .expert:
            if veryStrong && roll < 0.10 {
                gesture = .double
            } else if strong && roll < 0.23 {
                gesture = .hold
            } else if veryStrong && roll < 0.31 {
                gesture = .breakTap
            }

        case .master:
            if veryStrong && roll < 0.14 {
                gesture = .slide
            } else if veryStrong && roll < 0.26 {
                gesture = .double
            } else if strong && roll < 0.38 {
                gesture = .hold
            } else if strong && roll < 0.48 {
                gesture = .breakTap
            }

        case .remaster:
            if veryStrong && roll < 0.20 {
                gesture = .slide
            } else if strong && roll < 0.35 {
                gesture = .double
            } else if strong && roll < 0.47 {
                gesture = .hold
            } else if roll < 0.57 && phraseStrength > 0.45 {
                gesture = .breakTap
            }
        }

        // Prevent the "same gimmick every N notes" machine feeling.
        if gesture == lastGesture && gesture != .tap && rng.chance(0.72) {
            gesture = .tap
        }

        // Sparse highlight on phrase-sized landmarks rather than fixed modulo spam.
        if noteNumber > 8, noteNumber % rng.int(in: 9...17) == 0, veryStrong, difficulty.rawValue >= 4 {
            gesture = rng.chance(0.5) ? .breakTap : .double
        }

        return gesture
    }

    private static func token(
        gesture: Gesture,
        lane: Int,
        strength: Double,
        difficulty: ChartDifficulty,
        rng: inout SplitMix64
    ) -> String {
        switch gesture {
        case .tap:
            return "\(lane)"

        case .hold:
            let duration = strength > 0.82 ? "4:1" : "8:1"
            return "\(lane)h[\(duration)]"

        case .double:
            var other = wrapped(lane + rng.int(in: 2...6))
            if other == lane { other = opposite(lane) }
            return "\(lane)/\(other)"

        case .breakTap:
            return "\(lane)b"

        case .slide:
            let distances = difficulty == .remaster ? [2, 3, 4, 5, 6] : [2, 3, 4, 5]
            let distance = distances[rng.int(in: 0..<distances.count)]
            let signed = rng.chance(0.5) ? distance : -distance
            let destination = wrapped(lane + signed)
            let duration = strength > 0.90 ? "8:1" : (rng.chance(0.5) ? "4:1" : "8:1")
            return "\(lane)-\(destination)[\(duration)]"
        }
    }

    private static func averageOnsetStrength(
        start: Int,
        end: Int,
        onsetByStep: [Int: Double]
    ) -> Double {
        guard end > start else { return 0 }
        var sum = 0.0
        var count = 0

        for step in start..<end {
            if let value = onsetByStep[step] {
                sum += value
                count += 1
            }
        }

        return count == 0 ? 0 : sum / Double(count)
    }

    private static func normalize(_ values: [Double]) -> [Double] {
        guard let maxValue = values.max(), maxValue > 0 else {
            return values.map { _ in 0 }
        }
        return values.map { min(1, max(0, $0 / maxValue)) }
    }

    private static func opposite(_ lane: Int) -> Int {
        wrapped(lane + 4)
    }

    private static func wrapped(_ lane: Int) -> Int {
        let zero = ((lane - 1) % 8 + 8) % 8
        return zero + 1
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+%\\")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    mutating func int(in range: Range<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound)
        return range.lowerBound + Int(next() % span)
    }

    mutating func chance(_ probability: Double) -> Bool {
        double(in: 0...1) < min(1, max(0, probability))
    }
}

private extension Array {
    mutating func rotateLeft(by amount: Int) {
        guard !isEmpty else { return }
        let shift = ((amount % count) + count) % count
        guard shift != 0 else { return }
        self = Array(self[shift...]) + Array(self[..<shift])
    }
}
