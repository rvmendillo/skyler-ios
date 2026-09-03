import Foundation

enum ChartGenerator {
    static func generateAll(analysis: AudioAnalysis) -> [GeneratedChart] {
        let generationSeed = UInt64.random(in: UInt64.min...UInt64.max)
        let blueprint = buildBlueprint(analysis: analysis, seed: generationSeed)
        let enrichedRemaster = enrichRemaster(
            blueprint.events,
            analysis: analysis,
            totalSteps: blueprint.totalSteps,
            seed: generationSeed ^ 0xA57D_3C91_F0E1_22B7
        )
        let remasterEvents = enforceRemasterPlayability(
            enrichedRemaster,
            analysis: analysis
        )

        // Strict family inheritance:
        // Re:MASTER -> MASTER -> EXPERT -> ADVANCED -> BASIC -> EASY.
        // Every lower chart can only remove/simplify events from its parent.
        let descending: [ChartDifficulty] = [
            .remaster,
            .master,
            .expert,
            .advanced,
            .basic,
            .easy
        ]

        var family: [ChartDifficulty: [FamilyEvent]] = [:]
        var parentEvents = remasterEvents

        for difficulty in descending {
            let events: [FamilyEvent]
            if difficulty == .remaster {
                events = parentEvents
            } else {
                events = simplify(
                    parentEvents,
                    for: difficulty
                )
            }

            family[difficulty] = events
            parentEvents = events
        }

        return ChartDifficulty.allCases.map { difficulty in
            let familyEvents = family[difficulty] ?? []

            return GeneratedChart(
                difficulty: difficulty,
                level: suggestedLevel(for: difficulty, analysis: analysis),
                noteText: render(
                    events: familyEvents,
                    analysis: analysis,
                    totalSteps: blueprint.totalSteps
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
        lines.append("&smsg=Hierarchical drum + melody chart family; lower levels practice the same patterns as higher levels.")

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

    private static func suggestedLevel(
        for difficulty: ChartDifficulty,
        analysis: AudioAnalysis
    ) -> String {
        let density = Double(analysis.onsets.count) / max(1, analysis.duration)
        let base: Double

        switch difficulty {
        case .easy: base = 1.8
        case .basic: base = 3.6
        case .advanced: base = 6.4
        case .expert: base = 9.2
        case .master: base = 11.4
        case .remaster: base = 14.0
        }

        let tempoBonus = max(0, (analysis.bpm - 110) / 45)
        let densityBonus = min(2.0, density / 2.5)
        let rhythmicBonus = analysis.drumBeatPositions.isEmpty
            ? 0
            : min(0.7, Double(analysis.drumBeatPositions.count) / max(1, analysis.duration) / 5.0)

        let value = min(14.9, base + tempoBonus + densityBonus + rhythmicBonus)
        let rounded = (value * 10).rounded() / 10

        if rounded >= 10 {
            let whole = Int(floor(rounded))
            return rounded - Double(whole) >= 0.6 ? "\(whole)+" : "\(whole)"
        }

        return "\(max(1, Int(rounded.rounded())))"
    }

    private enum PhraseMotion: CaseIterable, Equatable {
        case orbitCW
        case orbitCCW
        case mirror
        case bounce
        case diagonal
        case answer
        case spiral
        case scattered
    }

    private enum Gesture: Equatable {
        case tap
        case hold(String)
        case double(Int)
        case breakTap
        case slide(destination: Int, duration: String)
        case centerHold(String)
        case ring([Int])
    }

    private struct FamilyEvent {
        let step: Int
        let lane: Int
        let gesture: Gesture
        let strength: Double
        let drumStrength: Double
        let drumNote: UInt8?
        let melodyPitch: UInt8?
        let melodyStrength: Double
        let melodicInterval: Int
        let importance: Double
        let phrase: Int
    }

    private struct Blueprint {
        let events: [FamilyEvent]
        let totalSteps: Int
    }

    private struct StepDrum {
        let strength: Double
        let note: UInt8?
    }

    private struct StepMelody {
        let pitch: UInt8
        let strength: Double
    }

    private static func buildBlueprint(
        analysis: AudioAnalysis,
        seed: UInt64
    ) -> Blueprint {
        var rng = SplitMix64(seed: seed)
        let bpm = max(1, analysis.bpm)
        let secondsPerStep = 60.0 / bpm / 4.0

        let totalSteps: Int
        if analysis.exactScoreTiming, let durationBeats = analysis.durationBeats {
            totalSteps = max(1, Int(ceil(durationBeats * 4.0)))
        } else {
            totalSteps = max(
                1,
                Int(ceil(max(0, analysis.duration - analysis.firstBeat) / secondsPerStep))
            )
        }

        let normalizedStrengths = normalize(analysis.strengths)
        var onsetByStep: [Int: Double] = [:]

        if analysis.exactScoreTiming,
           let beats = analysis.beatPositions,
           beats.count == analysis.onsets.count {
            for (index, beat) in beats.enumerated() {
                let step = Int((beat * 4.0).rounded())
                guard step >= 0 && step < totalSteps else { continue }

                let strength = normalizedStrengths.indices.contains(index)
                    ? normalizedStrengths[index]
                    : 0.5
                onsetByStep[step] = max(onsetByStep[step] ?? 0, strength)
            }
        } else {
            for (index, onset) in analysis.onsets.enumerated()
            where onset >= analysis.firstBeat {
                let step = Int(((onset - analysis.firstBeat) / secondsPerStep).rounded())
                guard step >= 0 && step < totalSteps else { continue }

                let strength = normalizedStrengths.indices.contains(index)
                    ? normalizedStrengths[index]
                    : 0.5
                onsetByStep[step] = max(onsetByStep[step] ?? 0, strength)
            }
        }

        var drumByStep: [Int: StepDrum] = [:]
        for index in analysis.drumBeatPositions.indices {
            let step = Int((analysis.drumBeatPositions[index] * 4.0).rounded())
            guard step >= 0 && step < totalSteps else { continue }

            let strength = analysis.drumStrengths.indices.contains(index)
                ? analysis.drumStrengths[index]
                : 0.65
            let note = analysis.drumNoteNumbers.indices.contains(index)
                ? analysis.drumNoteNumbers[index]
                : nil

            if let old = drumByStep[step] {
                if strength > old.strength {
                    drumByStep[step] = StepDrum(strength: strength, note: note)
                }
            } else {
                drumByStep[step] = StepDrum(strength: strength, note: note)
            }
        }

        var melodyByStep: [Int: StepMelody] = [:]
        for index in analysis.melodyBeatPositions.indices {
            let step = Int((analysis.melodyBeatPositions[index] * 4.0).rounded())
            guard step >= 0 && step < totalSteps else { continue }
            guard analysis.melodyPitches.indices.contains(index) else { continue }

            let pitch = analysis.melodyPitches[index]
            let strength = analysis.melodyStrengths.indices.contains(index)
                ? analysis.melodyStrengths[index]
                : 0.65

            if let old = melodyByStep[step] {
                if pitch > old.pitch || (pitch == old.pitch && strength > old.strength) {
                    melodyByStep[step] = StepMelody(pitch: pitch, strength: strength)
                }
            } else {
                melodyByStep[step] = StepMelody(pitch: pitch, strength: strength)
            }
        }

        let hasDrums = !drumByStep.isEmpty
        let hasMelody = !melodyByStep.isEmpty
        let phraseLength = 64
        let phraseCount = max(1, Int(ceil(Double(totalSteps) / Double(phraseLength))))

        var events: [FamilyEvent] = []
        var lane = rng.int(in: 1...8)
        var lastPlaced = -999
        var lastGesture: Gesture = .tap
        var previousMotion: PhraseMotion?
        var previousMotif: [Int] = []
        var previousMelodyPitch: UInt8?
        var noteNumber = 0

        for phrase in 0..<phraseCount {
            let start = phrase * phraseLength
            let end = min(totalSteps, start + phraseLength)
            guard start < end else { continue }

            let phraseStrength = averageCombinedStrength(
                start: start,
                end: end,
                onsetByStep: onsetByStep,
                drumByStep: drumByStep,
                melodyByStep: melodyByStep
            )

            var motion = PhraseMotion.allCases[
                rng.int(in: 0..<PhraseMotion.allCases.count)
            ]

            if motion == previousMotion {
                motion = PhraseMotion.allCases[
                    (PhraseMotion.allCases.firstIndex(of: motion)! +
                     1 +
                     rng.int(in: 0...2))
                    % PhraseMotion.allCases.count
                ]
            }

            var motif = motifFor(
                motion: motion,
                rng: &rng
            )

            if phrase > 0,
               !previousMotif.isEmpty,
               rng.chance(0.31) {
                motif = previousMotif.map { rng.chance(0.5) ? -$0 : $0 }
                if rng.chance(0.45) {
                    motif.rotateLeft(
                        by: rng.int(in: 1...max(1, motif.count - 1))
                    )
                }
            }

            previousMotion = motion
            previousMotif = motif

            let breathingRoom = phraseStrength < 0.28
                ? rng.int(in: 5...11)
                : rng.int(in: 0...5)
            let restStart = start + rng.int(
                in: 0...max(0, phraseLength - breathingRoom - 1)
            )
            let restEnd = min(end, restStart + breathingRoom)
            var motifIndex = 0

            for step in start..<end {
                let onset = onsetByStep[step] ?? 0
                let drum = drumByStep[step]
                let melody = melodyByStep[step]
                let drumStrength = drum?.strength ?? 0
                let melodyStrength = melody?.strength ?? 0

                let sixteenth = step % 4
                let beatInBar = step % 16
                let quarterAccent = sixteenth == 0 ? 0.13 : 0
                let eighthAccent = sixteenth == 2 ? 0.05 : 0
                let barAccent = beatInBar == 0 ? 0.12 : 0

                let score: Double
                if hasDrums {
                    score =
                        onset * 0.22 +
                        drumStrength * 0.56 +
                        melodyStrength * 0.74 +
                        quarterAccent +
                        eighthAccent +
                        barAccent
                } else {
                    score =
                        onset * 0.52 +
                        melodyStrength * 0.82 +
                        quarterAccent +
                        eighthAccent +
                        barAccent
                }

                var candidate =
                    score + rng.double(in: -0.045...0.085) >= 0.31

                if drumStrength >= 0.55 {
                    candidate = true
                }

                if hasMelody,
                   melodyStrength >= 0.36 {
                    candidate = true
                }

                if step >= restStart,
                   step < restEnd,
                   drumStrength < 0.72,
                   melodyStrength < 0.50 {
                    candidate = false
                }

                guard candidate else { continue }
                guard step - lastPlaced >= 1 else { continue }

                let motifDelta = motif[motifIndex % motif.count]
                motifIndex += 1

                var melodicInterval = 0
                let laneDelta: Int

                if let melody {
                    if let previousMelodyPitch {
                        melodicInterval =
                            Int(melody.pitch) - Int(previousMelodyPitch)
                    }

                    laneDelta = melodyLaneDelta(
                        interval: melodicInterval,
                        fallback: motifDelta,
                        rng: &rng
                    )
                    previousMelodyPitch = melody.pitch
                } else {
                    laneDelta = motifDelta
                }

                lane = wrapped(lane + laneDelta)

                if melody == nil,
                   drumStrength < 0.70,
                   rng.chance(0.11) {
                    lane = wrapped(
                        lane +
                        (rng.chance(0.5) ? 1 : -1) *
                        rng.int(in: 1...2)
                    )
                }

                noteNumber += 1

                let strength = max(
                    onset,
                    drumStrength,
                    melodyStrength
                )

                let gesture = chooseSourceGesture(
                    strength: strength,
                    drumStrength: drumStrength,
                    drumNote: drum?.note,
                    melodyStrength: melodyStrength,
                    melodicInterval: melodicInterval,
                    phraseStrength: phraseStrength,
                    lastGesture: lastGesture,
                    noteNumber: noteNumber,
                    lane: lane,
                    rng: &rng
                )

                let importance = eventImportance(
                    step: step,
                    onset: onset,
                    drumStrength: drumStrength,
                    melodyStrength: melodyStrength,
                    melodicInterval: melodicInterval,
                    stableNoise: rng.double(in: 0...0.12)
                )

                events.append(
                    FamilyEvent(
                        step: step,
                        lane: lane,
                        gesture: gesture,
                        strength: strength,
                        drumStrength: drumStrength,
                        drumNote: drum?.note,
                        melodyPitch: melody?.pitch,
                        melodyStrength: melodyStrength,
                        melodicInterval: melodicInterval,
                        importance: importance,
                        phrase: phrase
                    )
                )

                lastGesture = gesture
                lastPlaced = step
            }
        }

        return Blueprint(
            events: events,
            totalSteps: totalSteps
        )
    }

    private static func enrichRemaster(
        _ source: [FamilyEvent],
        analysis: AudioAnalysis,
        totalSteps: Int,
        seed: UInt64
    ) -> [FamilyEvent] {
        var rng = SplitMix64(seed: seed)
        var byStep = Dictionary(
            uniqueKeysWithValues: source.map { ($0.step, $0) }
        )

        // 1) Follow substantially more of the melody than lower charts do.
        var previousPitch: UInt8?
        var melodyLane = source.first?.lane ?? rng.int(in: 1...8)

        for index in analysis.melodyBeatPositions.indices {
            guard analysis.melodyPitches.indices.contains(index) else { continue }

            let step = Int((analysis.melodyBeatPositions[index] * 4.0).rounded())
            guard step >= 0, step < totalSteps else { continue }

            let pitch = analysis.melodyPitches[index]
            let strength = analysis.melodyStrengths.indices.contains(index)
                ? analysis.melodyStrengths[index]
                : 0.60

            var interval = 0
            if let previousPitch {
                interval = Int(pitch) - Int(previousPitch)
            }

            let fallback = interval == 0
                ? (rng.chance(0.5) ? 1 : -1)
                : (interval > 0 ? 1 : -1)

            melodyLane = wrapped(
                melodyLane + melodyLaneDelta(
                    interval: interval,
                    fallback: fallback,
                    rng: &rng
                )
            )

            let existing = byStep[step]
            let baseLane = existing?.lane ?? melodyLane
            let drumStrength = existing?.drumStrength ?? 0
            let drumNote = existing?.drumNote

            let gesture: Gesture
            if strength >= 0.90, step % 16 == 0, rng.chance(0.30) {
                gesture = .centerHold(rng.chance(0.45) ? "4:2" : "4:1")
            } else if strength >= 0.74, rng.chance(0.34) {
                gesture = .double(wrapped(baseLane + (rng.chance(0.5) ? 4 : 3)))
            } else if abs(interval) >= 7, rng.chance(0.46) {
                gesture = .slide(
                    destination: wrapped(
                        baseLane +
                        (interval >= 0 ? 1 : -1) *
                        min(4, max(2, abs(interval) / 2))
                    ),
                    duration: strength >= 0.84 ? "8:1" : "4:1"
                )
            } else {
                gesture = existing?.gesture ?? .tap
            }

            byStep[step] = FamilyEvent(
                step: step,
                lane: baseLane,
                gesture: gesture,
                strength: max(existing?.strength ?? 0, strength),
                drumStrength: drumStrength,
                drumNote: drumNote,
                melodyPitch: pitch,
                melodyStrength: max(existing?.melodyStrength ?? 0, strength),
                melodicInterval: interval,
                importance: max(existing?.importance ?? 0, 0.46 + strength * 0.42),
                phrase: existing?.phrase ?? step / 64
            )

            previousPitch = pitch
        }

        // 2) Boss-chart ring runs: eight 16th notes travelling around the
        // cabinet. These are intentionally low-importance so MASTER can
        // simplify them away while Re:MASTER keeps the complete run.
        let phraseLength = 64
        let phraseCount = max(1, Int(ceil(Double(totalSteps) / Double(phraseLength))))

        for phrase in 1..<phraseCount {
            guard phrase % 2 == 1 else { continue }

            let start = phrase * phraseLength
            let end = min(totalSteps, start + phraseLength)
            let candidates = byStep.values.filter {
                $0.step >= start &&
                $0.step < end &&
                $0.melodyStrength >= 0.62
            }

            guard let anchor = candidates.max(by: {
                ($0.melodyStrength + $0.strength) <
                ($1.melodyStrength + $1.strength)
            }) else {
                continue
            }

            let runStart = min(max(start, anchor.step), max(start, end - 9))
            let direction = anchor.melodicInterval < 0 ? -1 : 1
            let firstLane = anchor.lane

            for offset in 0..<8 {
                let step = runStart + offset
                guard step < end, step < totalSteps else { break }

                let lane = wrapped(firstLane + direction * offset)
                let old = byStep[step]

                byStep[step] = FamilyEvent(
                    step: step,
                    lane: lane,
                    gesture: .tap,
                    strength: max(old?.strength ?? 0, 0.68),
                    drumStrength: old?.drumStrength ?? 0,
                    drumNote: old?.drumNote,
                    melodyPitch: old?.melodyPitch,
                    melodyStrength: max(old?.melodyStrength ?? 0, 0.64),
                    melodicInterval: old?.melodicInterval ?? direction * 2,
                    importance: min(old?.importance ?? 0.23, 0.26),
                    phrase: phrase
                )
            }

            // Opposite-pair ring burst: all eight lanes appear across four
            // 16th steps, but only two notes are ever simultaneous. This keeps
            // the spectacle of a full-circle boss pattern while remaining
            // physically playable with two hands.
            let burstStep = runStart + 8
            if burstStep + 3 < end, burstStep + 3 < totalSteps, phrase % 4 == 3 {
                let pairs = [
                    [1, 5],
                    [2, 6],
                    [3, 7],
                    [4, 8]
                ]

                for (offset, pair) in pairs.enumerated() {
                    let step = burstStep + offset
                    let old = byStep[step]

                    byStep[step] = FamilyEvent(
                        step: step,
                        lane: pair[0],
                        gesture: .ring(pair),
                        strength: max(old?.strength ?? 0, 0.90),
                        drumStrength: max(old?.drumStrength ?? 0, 0.72),
                        drumNote: old?.drumNote,
                        melodyPitch: old?.melodyPitch,
                        melodyStrength: max(old?.melodyStrength ?? 0, 0.72),
                        melodicInterval: old?.melodicInterval ?? 0,
                        importance: 0.25,
                        phrase: phrase
                    )
                }
            }
        }

        // 3) Add center TOUCH HOLD punctuation near a few strong phrase
        // boundaries. This is the real simai C-sensor hold, not a lane hold.
        for step in stride(from: 96, to: totalSteps, by: 128) {
            guard step < totalSteps else { break }

            let nearby = byStep.values
                .filter { abs($0.step - step) <= 4 }
                .max(by: {
                    ($0.melodyStrength + $0.drumStrength) <
                    ($1.melodyStrength + $1.drumStrength)
                })

            guard let anchor = nearby else { continue }

            byStep[anchor.step] = FamilyEvent(
                step: anchor.step,
                lane: anchor.lane,
                gesture: .centerHold(
                    anchor.melodyStrength >= 0.82 ? "4:2" : "4:1"
                ),
                strength: max(anchor.strength, 0.82),
                drumStrength: anchor.drumStrength,
                drumNote: anchor.drumNote,
                melodyPitch: anchor.melodyPitch,
                melodyStrength: max(anchor.melodyStrength, 0.72),
                melodicInterval: anchor.melodicInterval,
                importance: max(anchor.importance, 0.34),
                phrase: anchor.phrase
            )
        }

        return byStep.values.sorted { $0.step < $1.step }
    }

    private static func enforceRemasterPlayability(
        _ input: [FamilyEvent],
        analysis: AudioAnalysis
    ) -> [FamilyEvent] {
        var events = input.sorted { $0.step < $1.step }

        // At very high BPM, repeating the exact same sensor every 16th can
        // become a one-hand jack rather than a musical pattern. Redirect only
        // low-priority repeats by one lane; melody-heavy anchors stay intact.
        if analysis.bpm > 220 {
            var previousLane: Int?
            var previousStep = -999

            for index in events.indices {
                guard
                    events[index].step - previousStep == 1,
                    events[index].lane == previousLane,
                    events[index].melodyStrength < 0.70
                else {
                    previousLane = events[index].lane
                    previousStep = events[index].step
                    continue
                }

                let old = events[index]
                events[index] = FamilyEvent(
                    step: old.step,
                    lane: wrapped(old.lane + (index.isMultiple(of: 2) ? 1 : -1)),
                    gesture: old.gesture,
                    strength: old.strength,
                    drumStrength: old.drumStrength,
                    drumNote: old.drumNote,
                    melodyPitch: old.melodyPitch,
                    melodyStrength: old.melodyStrength,
                    melodicInterval: old.melodicInterval,
                    importance: old.importance,
                    phrase: old.phrase
                )

                previousLane = events[index].lane
                previousStep = events[index].step
            }
        }

        // Prevent back-to-back two-hand chords every 16th. A short pair burst
        // is fine, but sustained double-jacking is not useful practice.
        var lastTwoHandStep = -999

        for index in events.indices {
            let twoHand: Bool
            switch events[index].gesture {
            case .double:
                twoHand = true
            case .ring(let lanes):
                twoHand = lanes.count >= 2
            default:
                twoHand = false
            }

            guard twoHand else { continue }

            if events[index].step - lastTwoHandStep < 2 {
                let old = events[index]
                events[index] = FamilyEvent(
                    step: old.step,
                    lane: old.lane,
                    gesture: .tap,
                    strength: old.strength,
                    drumStrength: old.drumStrength,
                    drumNote: old.drumNote,
                    melodyPitch: old.melodyPitch,
                    melodyStrength: old.melodyStrength,
                    melodicInterval: old.melodicInterval,
                    importance: old.importance,
                    phrase: old.phrase
                )
            } else {
                lastTwoHandStep = events[index].step
            }
        }

        // A center touch-hold occupies one hand. During its active window,
        // the free hand may tap or trace a slide, but it should not be asked
        // to perform an outer two-note chord or another hold.
        var centerHoldUntilStep = -1

        for index in events.indices {
            let event = events[index]

            if case .centerHold(let duration) = event.gesture {
                if event.step < centerHoldUntilStep {
                    events[index] = FamilyEvent(
                        step: event.step,
                        lane: event.lane,
                        gesture: .tap,
                        strength: event.strength,
                        drumStrength: event.drumStrength,
                        drumNote: event.drumNote,
                        melodyPitch: event.melodyPitch,
                        melodyStrength: event.melodyStrength,
                        melodicInterval: event.melodicInterval,
                        importance: event.importance,
                        phrase: event.phrase
                    )
                } else {
                    centerHoldUntilStep =
                        event.step + holdSteps(duration)
                }
                continue
            }

            guard event.step < centerHoldUntilStep else {
                continue
            }

            let needsBothFreeHands: Bool
            switch event.gesture {
            case .double, .ring, .hold:
                needsBothFreeHands = true
            default:
                needsBothFreeHands = false
            }

            if needsBothFreeHands {
                events[index] = FamilyEvent(
                    step: event.step,
                    lane: event.lane,
                    gesture: .tap,
                    strength: event.strength,
                    drumStrength: event.drumStrength,
                    drumNote: event.drumNote,
                    melodyPitch: event.melodyPitch,
                    melodyStrength: event.melodyStrength,
                    melodicInterval: event.melodicInterval,
                    importance: event.importance,
                    phrase: event.phrase
                )
            }
        }

        // Cap sustained density while preserving strong melody/drum anchors.
        // Boss sections may still briefly spike above this, but the whole chart
        // stays in a human two-hand range rather than becoming an autoplay map.
        let duration = max(1, analysis.duration)
        let maxAverageHitsPerSecond = min(
            10.5,
            max(8.0, analysis.bpm / 24.0)
        )

        func hitCount(_ event: FamilyEvent) -> Int {
            switch event.gesture {
            case .double:
                return 2
            case .ring(let lanes):
                return min(2, max(1, lanes.count))
            default:
                return 1
            }
        }

        var totalHits = events.reduce(0) {
            $0 + hitCount($1)
        }
        let allowedHits = Int(duration * maxAverageHitsPerSecond)

        if totalHits > allowedHits {
            let removable = events.indices
                .filter {
                    events[$0].melodyStrength < 0.52 &&
                    events[$0].drumStrength < 0.58 &&
                    events[$0].importance < 0.48
                }
                .sorted {
                    events[$0].importance < events[$1].importance
                }

            var removed = Set<Int>()

            for index in removable {
                guard totalHits > allowedHits else { break }
                removed.insert(index)
                totalHits -= hitCount(events[index])
            }

            events = events.enumerated()
                .filter { !removed.contains($0.offset) }
                .map(\.element)
        }

        return events
    }

    private static func simplify(
        _ parentEvents: [FamilyEvent],
        for difficulty: ChartDifficulty
    ) -> [FamilyEvent] {
        let threshold: Double
        switch difficulty {
        case .remaster: threshold = 0.00
        case .master: threshold = 0.27
        case .expert: threshold = 0.43
        case .advanced: threshold = 0.57
        case .basic: threshold = 0.69
        case .easy: threshold = 0.80
        }

        var output: [FamilyEvent] = []
        var lastStep = -999

        for source in parentEvents {
            guard source.importance >= threshold else { continue }
            guard source.step - lastStep >= difficulty.minimumGapSteps else {
                continue
            }

            let simplified = FamilyEvent(
                step: source.step,
                lane: source.lane,
                gesture: simplifiedGesture(
                    source.gesture,
                    source: source,
                    difficulty: difficulty
                ),
                strength: source.strength,
                drumStrength: source.drumStrength,
                drumNote: source.drumNote,
                melodyPitch: source.melodyPitch,
                melodyStrength: source.melodyStrength,
                melodicInterval: source.melodicInterval,
                importance: source.importance,
                phrase: source.phrase
            )

            output.append(simplified)
            lastStep = source.step
        }

        return output
    }

    private static func simplifiedGesture(
        _ gesture: Gesture,
        source: FamilyEvent,
        difficulty: ChartDifficulty
    ) -> Gesture {
        switch difficulty {
        case .remaster:
            return gesture

        case .master:
            switch gesture {
            case .slide(let destination, let duration):
                return source.importance >= 0.55
                    ? .slide(destination: destination, duration: duration)
                    : .tap
            case .double(let other):
                return source.drumStrength >= 0.62
                    ? .double(other)
                    : .tap
            case .breakTap:
                return source.importance >= 0.64 ? .breakTap : .tap
            case .hold(let duration):
                return .hold(duration)
            case .centerHold(let duration):
                return source.importance >= 0.52 ? .hold(duration) : .tap
            case .ring(let lanes):
                if source.importance >= 0.52, lanes.count >= 2 {
                    return .double(lanes[1])
                }
                return .tap
            case .tap:
                return .tap
            }

        case .expert:
            switch gesture {
            case .slide:
                return .tap
            case .double(let other):
                return source.drumStrength >= 0.78
                    ? .double(other)
                    : .tap
            case .hold(let duration):
                return source.importance >= 0.62
                    ? .hold(duration)
                    : .tap
            case .breakTap:
                return source.drumStrength >= 0.82
                    ? .breakTap
                    : .tap
            case .centerHold, .ring:
                return .tap
            case .tap:
                return .tap
            }

        case .advanced:
            if case .hold(let duration) = gesture,
               source.importance >= 0.72 {
                return .hold(duration)
            }
            return .tap

        case .basic, .easy:
            return .tap
        }
    }

    private static func render(
        events: [FamilyEvent],
        analysis: AudioAnalysis,
        totalSteps: Int
    ) -> String {
        var eventByStep: [Int: FamilyEvent] = [:]
        for event in events {
            eventByStep[event.step] = event
        }

        var tempoByStep: [Int: Double] = [:]
        if analysis.exactScoreTiming {
            for point in analysis.tempoMap.dropFirst() {
                let step = Int((point.beat * 4.0).rounded())
                if step >= 0 && step <= totalSteps {
                    tempoByStep[step] = point.bpm
                }
            }
        }

        var body =
            "(\(String(format: "%.3f", max(1, analysis.bpm)))){16},\n"

        for step in 0...totalSteps {
            if let changedBPM = tempoByStep[step] {
                body += "(\(String(format: "%.3f", changedBPM)))"
            }

            if let event = eventByStep[step] {
                body += token(for: event)
            }

            body += ","

            if (step + 1) % 16 == 0 {
                body += "\n"
            }
        }

        body += "\nE"
        return body
    }

    private static func token(for event: FamilyEvent) -> String {
        switch event.gesture {
        case .tap:
            return "\(event.lane)"

        case .hold(let duration):
            return "\(event.lane)h[\(duration)]"

        case .double(let other):
            return "\(event.lane)/\(other)"

        case .breakTap:
            return "\(event.lane)b"

        case .slide(let destination, let duration):
            return "\(event.lane)-\(destination)[\(duration)]"

        case .centerHold(let duration):
            return "Ch[\(duration)]"

        case .ring(let lanes):
            return lanes.map(String.init).joined(separator: "/")
        }
    }

    private static func chooseSourceGesture(
        strength: Double,
        drumStrength: Double,
        drumNote: UInt8?,
        melodyStrength: Double,
        melodicInterval: Int,
        phraseStrength: Double,
        lastGesture: Gesture,
        noteNumber: Int,
        lane: Int,
        rng: inout SplitMix64
    ) -> Gesture {
        let roll = rng.double(in: 0...1)
        let absInterval = abs(melodicInterval)
        var result: Gesture = .tap

        if let drumNote {
            if isCrash(drumNote),
               drumStrength >= 0.68,
               roll < 0.42 {
                result = .breakTap
            } else if isSnare(drumNote),
                      drumStrength >= 0.62,
                      roll < 0.34 {
                result = .double(
                    wrapped(lane + (rng.chance(0.5) ? 4 : 3))
                )
            } else if isTom(drumNote),
                      roll < 0.28 {
                let destination = wrapped(
                    lane +
                    (rng.chance(0.5) ? 1 : -1) *
                    rng.int(in: 2...4)
                )
                result = .slide(
                    destination: destination,
                    duration: strength > 0.85 ? "8:1" : "4:1"
                )
            }
        }

        if result == .tap,
           melodyStrength >= 0.62,
           absInterval >= 5,
           roll < 0.50 {
            let distance = min(5, max(2, absInterval / 2))
            let direction = melodicInterval >= 0 ? 1 : -1
            result = .slide(
                destination: wrapped(lane + direction * distance),
                duration: strength > 0.82 ? "8:1" : "4:1"
            )
        }

        if result == .tap,
           strength >= 0.76,
           roll < 0.24 {
            result = .hold(strength > 0.88 ? "4:1" : "8:1")
        }

        if result == .tap,
           drumStrength >= 0.72,
           phraseStrength >= 0.42,
           roll < 0.31 {
            result = .breakTap
        }

        if result == lastGesture,
           result != .tap,
           rng.chance(0.68) {
            result = .tap
        }

        if noteNumber > 8,
           strength >= 0.9,
           noteNumber % rng.int(in: 11...19) == 0 {
            result = .breakTap
        }

        return result
    }

    private static func eventImportance(
        step: Int,
        onset: Double,
        drumStrength: Double,
        melodyStrength: Double,
        melodicInterval: Int,
        stableNoise: Double
    ) -> Double {
        let sixteenth = step % 4
        let beatInBar = step % 16

        let beatWeight: Double
        if beatInBar == 0 {
            beatWeight = 0.31
        } else if sixteenth == 0 {
            beatWeight = 0.22
        } else if sixteenth == 2 {
            beatWeight = 0.10
        } else {
            beatWeight = 0.02
        }

        let intervalWeight =
            min(0.13, Double(abs(melodicInterval)) / 12.0 * 0.13)

        return min(
            1,
            beatWeight +
            onset * 0.13 +
            drumStrength * 0.28 +
            melodyStrength * 0.38 +
            intervalWeight +
            stableNoise
        )
    }

    private static func melodyLaneDelta(
        interval: Int,
        fallback: Int,
        rng: inout SplitMix64
    ) -> Int {
        guard interval != 0 else {
            return rng.chance(0.42) ? 0 : fallback
        }

        let direction = interval > 0 ? 1 : -1
        let distance: Int

        switch abs(interval) {
        case 1...2: distance = 1
        case 3...5: distance = 2
        case 6...8: distance = 3
        default: distance = 4
        }

        return direction * distance
    }

    private static func motifFor(
        motion: PhraseMotion,
        rng: inout SplitMix64
    ) -> [Int] {
        switch motion {
        case .orbitCW:
            return [1, 1, 2, 1, -1, 1]
        case .orbitCCW:
            return [-1, -1, -2, -1, 1, -1]
        case .mirror:
            return [2, -2, 3, -3, 1, -1]
        case .bounce:
            return [3, -2, 2, -3, 1, 2]
        case .diagonal:
            return [4, -1, 3, -4, 2, -2]
        case .answer:
            return [1, 2, 1, -3, -1, -2, -1, 3]
        case .spiral:
            return [1, 2, 2, 3, -1, -2, -3]
        case .scattered:
            return [
                nonzeroRandom(-4...4, rng: &rng),
                nonzeroRandom(-3...3, rng: &rng),
                nonzeroRandom(-4...4, rng: &rng),
                nonzeroRandom(-2...2, rng: &rng)
            ]
        }
    }

    private static func nonzeroRandom(
        _ range: ClosedRange<Int>,
        rng: inout SplitMix64
    ) -> Int {
        let value = rng.int(in: range)
        return value == 0 ? (rng.chance(0.5) ? 1 : -1) : value
    }

    private static func averageCombinedStrength(
        start: Int,
        end: Int,
        onsetByStep: [Int: Double],
        drumByStep: [Int: StepDrum],
        melodyByStep: [Int: StepMelody]
    ) -> Double {
        guard end > start else { return 0 }

        var total = 0.0
        var count = 0

        for step in start..<end {
            let onset = onsetByStep[step] ?? 0
            let drum = drumByStep[step]?.strength ?? 0
            let melody = melodyByStep[step]?.strength ?? 0

            if onset > 0 || drum > 0 || melody > 0 {
                total += max(onset, drum, melody)
                count += 1
            }
        }

        return count == 0 ? 0 : total / Double(count)
    }

    private static func holdSteps(_ duration: String) -> Int {
        switch duration {
        case "4:2":
            return 8
        case "4:1":
            return 4
        case "8:1":
            return 2
        default:
            return 4
        }
    }

    private static func isSnare(_ note: UInt8) -> Bool {
        note == 38 || note == 40
    }

    private static func isCrash(_ note: UInt8) -> Bool {
        [49, 51, 52, 55, 57, 59].contains(note)
    }

    private static func isTom(_ note: UInt8) -> Bool {
        [41, 43, 45, 47, 48, 50].contains(note)
    }

    private static func normalize(_ values: [Double]) -> [Double] {
        guard let maxValue = values.max(),
              maxValue > 0 else {
            return values.map { _ in 0 }
        }

        return values.map {
            min(1, max(0, $0 / maxValue))
        }
    }

    private static func wrapped(_ lane: Int) -> Int {
        let zero = ((lane - 1) % 8 + 8) % 8
        return zero + 1
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+%\\")
        return value.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? value
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

    mutating func double(
        in range: ClosedRange<Double>
    ) -> Double {
        let unit =
            Double(next() >> 11) /
            Double(1 << 53)

        return range.lowerBound +
            unit *
            (range.upperBound - range.lowerBound)
    }

    mutating func int(
        in range: ClosedRange<Int>
    ) -> Int {
        guard range.lowerBound < range.upperBound else {
            return range.lowerBound
        }

        let span =
            UInt64(range.upperBound - range.lowerBound + 1)

        return range.lowerBound +
            Int(next() % span)
    }

    mutating func int(
        in range: Range<Int>
    ) -> Int {
        guard range.lowerBound < range.upperBound else {
            return range.lowerBound
        }

        let span =
            UInt64(range.upperBound - range.lowerBound)

        return range.lowerBound +
            Int(next() % span)
    }

    mutating func chance(
        _ probability: Double
    ) -> Bool {
        double(in: 0...1) <
            min(1, max(0, probability))
    }
}

private extension Array {
    mutating func rotateLeft(
        by amount: Int
    ) {
        guard !isEmpty else { return }

        let shift =
            ((amount % count) + count) % count

        guard shift != 0 else { return }

        self =
            Array(self[shift...]) +
            Array(self[..<shift])
    }
}
