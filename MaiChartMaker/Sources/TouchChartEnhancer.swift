import Foundation

enum TouchChartEnhancer {
    static func apply(
        to charts: [GeneratedChart],
        analysis: AudioAnalysis
    ) -> [GeneratedChart] {
        guard !analysis.melodyBeatPositions.isEmpty else {
            return charts
        }

        let candidates = touchCandidates(analysis: analysis)
        guard !candidates.isEmpty else { return charts }

        var output = charts

        for index in output.indices {
            switch output[index].difficulty {
            case .remaster:
                output[index].noteText = insertingTouches(
                    into: output[index].noteText,
                    candidates: candidates,
                    minimumStrength: 0.58,
                    minimumStepGap: 6,
                    keepEvery: 1
                )

            case .master:
                // MASTER keeps a sparse subset of the same touch timings so
                // it remains direct practice for Re:MASTER.
                output[index].noteText = insertingTouches(
                    into: output[index].noteText,
                    candidates: candidates,
                    minimumStrength: 0.76,
                    minimumStepGap: 12,
                    keepEvery: 2
                )

            case .expert, .advanced, .basic, .easy:
                break
            }
        }

        return output
    }

    private struct Candidate {
        let step: Int
        let strength: Double
        let pitch: UInt8
    }

    private static func touchCandidates(
        analysis: AudioAnalysis
    ) -> [Candidate] {
        var byStep: [Int: Candidate] = [:]

        for index in analysis.melodyBeatPositions.indices {
            guard analysis.melodyPitches.indices.contains(index) else {
                continue
            }

            let step = Int(
                (analysis.melodyBeatPositions[index] * 4.0).rounded()
            )
            let strength = analysis.melodyStrengths.indices.contains(index)
                ? analysis.melodyStrengths[index]
                : 0.62
            let pitch = analysis.melodyPitches[index]

            let candidate = Candidate(
                step: step,
                strength: strength,
                pitch: pitch
            )

            if let old = byStep[step] {
                if candidate.strength > old.strength {
                    byStep[step] = candidate
                }
            } else {
                byStep[step] = candidate
            }
        }

        return byStep.values.sorted { $0.step < $1.step }
    }

    private static func insertingTouches(
        into noteText: String,
        candidates: [Candidate],
        minimumStrength: Double,
        minimumStepGap: Int,
        keepEvery: Int
    ) -> String {
        var parts = noteText.components(separatedBy: ",")
        guard parts.count > 2 else { return noteText }

        var lastTouchStep = -999
        var acceptedIndex = 0

        for candidate in candidates {
            guard candidate.strength >= minimumStrength else { continue }
            guard candidate.step - lastTouchStep >= minimumStepGap else {
                continue
            }

            // Header occupies parts[0], so chart step N is parts[N + 1].
            let partIndex = candidate.step + 1
            guard parts.indices.contains(partIndex) else { continue }

            let original = parts[partIndex]
            guard let parsed = simpleLaneToken(original) else {
                continue
            }

            acceptedIndex += 1
            guard acceptedIndex % max(1, keepEvery) == 0 else {
                continue
            }

            // Alternate B/E sensor rings while preserving the outer-lane
            // direction inherited from the parent chart. The pitch changes
            // the alternation so repeated phrases do not look mechanical.
            let useInner = (candidate.step / 4 + Int(candidate.pitch)) % 2 == 0
            let region = useInner ? "B" : "E"
            let touch = "\(region)\(parsed.lane)"

            parts[partIndex] = parsed.prefix + touch + parsed.suffix
            lastTouchStep = candidate.step
        }

        return parts.joined(separator: ",")
    }

    private struct LaneToken {
        let prefix: String
        let lane: Int
        let suffix: String
    }

    private static func simpleLaneToken(_ raw: String) -> LaneToken? {
        let newlinePrefix = raw.prefix { $0 == "\n" || $0 == "\r" || $0 == " " || $0 == "\t" }
        let newlineSuffix = raw.reversed().prefix { $0 == "\n" || $0 == "\r" || $0 == " " || $0 == "\t" }.reversed()
        var core = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !core.isEmpty, core != "E" else { return nil }

        var tempoPrefix = ""
        if core.hasPrefix("("), let close = core.firstIndex(of: ")") {
            tempoPrefix = String(core[...close])
            core = String(core[core.index(after: close)...])
        }

        guard core.count == 1,
              let character = core.first,
              let lane = character.wholeNumberValue,
              (1...8).contains(lane) else {
            return nil
        }

        return LaneToken(
            prefix: String(newlinePrefix) + tempoPrefix,
            lane: lane,
            suffix: String(newlineSuffix)
        )
    }
}
