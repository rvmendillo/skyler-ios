import SwiftUI
import AVFoundation
import Combine

enum MaimaiPlayMode: String, CaseIterable, Identifiable {
    case auto = "AUTO"
    case manual = "PLAY"

    var id: String { rawValue }
}

private enum MaimaiPreviewKind: Equatable {
    case tap
    case breakTap
    case hold
    case slide(destination: Int)
    case touch
    case touchHold
}

private struct MaimaiPreviewEvent: Identifiable {
    let id: Int
    let time: Double
    let lanes: [Int]
    let touchRegions: [String]
    let kind: MaimaiPreviewKind
    let holdDuration: Double

    var expectedKeys: Set<String> {
        var result = Set(lanes.map { "L\($0)" })
        result.formUnion(touchRegions.map { "T:\($0)" })
        return result
    }
}

private enum SimaiPreviewParser {
    static func parse(
        _ text: String,
        baseBPM: Double,
        firstBeat: Double
    ) -> [MaimaiPreviewEvent] {
        let parts = text.components(separatedBy: ",")
        var bpm = max(1, baseBPM)
        var time = max(0, firstBeat)
        var output: [MaimaiPreviewEvent] = []
        var processedHeader = false
        var nextID = 0

        for rawPart in parts {
            var token = rawPart
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespaces)

            if !processedHeader, token.contains("{16}") {
                if let value = firstTempo(in: token) {
                    bpm = value
                }
                processedHeader = true
                continue
            }

            if let value = firstTempo(in: token) {
                bpm = value
                token = removingTempoPrefix(from: token)
            }

            token = token
                .replacingOccurrences(of: "{16}", with: "")
                .trimmingCharacters(in: .whitespaces)

            if token == "E" { break }

            if !token.isEmpty,
               let parsed = event(
                    id: nextID,
                    from: token,
                    time: time,
                    bpm: bpm
               ) {
                output.append(parsed)
                nextID += 1
            }

            time += 60.0 / max(1, bpm) / 4.0
        }

        return output
    }

    private static func firstTempo(in token: String) -> Double? {
        guard
            let open = token.firstIndex(of: "("),
            let close = token[open...].firstIndex(of: ")"),
            open < close
        else {
            return nil
        }

        let value = token[token.index(after: open)..<close]
        return Double(value)
    }

    private static func removingTempoPrefix(
        from token: String
    ) -> String {
        guard
            let open = token.firstIndex(of: "("),
            let close = token[open...].firstIndex(of: ")")
        else {
            return token
        }

        var result = token
        result.removeSubrange(open...close)
        return result
    }

    private static func event(
        id: Int,
        from token: String,
        time: Double,
        bpm: Double
    ) -> MaimaiPreviewEvent? {
        let cleaned = token.trimmingCharacters(in: .whitespaces)

        if cleaned.contains("/") {
            let pieces = cleaned.split(separator: "/").map(String.init)
            let lanes = pieces.compactMap(lane(from:))
            let touches = pieces.compactMap(touchRegion(from:))

            guard !lanes.isEmpty || !touches.isEmpty else { return nil }

            return MaimaiPreviewEvent(
                id: id,
                time: time,
                lanes: lanes,
                touchRegions: touches,
                kind: .tap,
                holdDuration: 0
            )
        }

        if let region = touchRegion(from: cleaned) {
            let isHold = region == "C" && cleaned.contains("h[")
            return MaimaiPreviewEvent(
                id: id,
                time: time,
                lanes: [],
                touchRegions: [region],
                kind: isHold ? .touchHold : .touch,
                holdDuration: isHold
                    ? durationSeconds(from: cleaned, bpm: bpm)
                    : 0
            )
        }

        if cleaned.contains("-"),
           let start = lane(from: cleaned),
           let dash = cleaned.firstIndex(of: "-") {
            let suffix = cleaned[cleaned.index(after: dash)...]
            if let destination = lane(from: String(suffix)) {
                return MaimaiPreviewEvent(
                    id: id,
                    time: time,
                    lanes: [start],
                    touchRegions: [],
                    kind: .slide(destination: destination),
                    holdDuration: durationSeconds(from: cleaned, bpm: bpm)
                )
            }
        }

        guard let lane = lane(from: cleaned) else {
            return nil
        }

        if cleaned.contains("h[") {
            return MaimaiPreviewEvent(
                id: id,
                time: time,
                lanes: [lane],
                touchRegions: [],
                kind: .hold,
                holdDuration: durationSeconds(from: cleaned, bpm: bpm)
            )
        }

        if cleaned.contains("b") {
            return MaimaiPreviewEvent(
                id: id,
                time: time,
                lanes: [lane],
                touchRegions: [],
                kind: .breakTap,
                holdDuration: 0
            )
        }

        return MaimaiPreviewEvent(
            id: id,
            time: time,
            lanes: [lane],
            touchRegions: [],
            kind: .tap,
            holdDuration: 0
        )
    }

    private static func touchRegion(from token: String) -> String? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = cleaned.first else { return nil }
        let area = String(first).uppercased()
        guard ["A", "B", "C", "D", "E"].contains(area) else {
            return nil
        }

        if area == "C" { return "C" }

        for character in cleaned.dropFirst() {
            if let lane = character.wholeNumberValue,
               (1...8).contains(lane) {
                return "\(area)\(lane)"
            }
        }

        return nil
    }

    private static func durationSeconds(
        from token: String,
        bpm: Double
    ) -> Double {
        guard
            let open = token.firstIndex(of: "["),
            let close = token[open...].firstIndex(of: "]"),
            open < close
        else {
            return 60.0 / max(1, bpm)
        }

        let body = token[token.index(after: open)..<close]
        let parts = body.split(separator: ":")

        guard
            parts.count == 2,
            let division = Double(parts[0]),
            let count = Double(parts[1]),
            division > 0
        else {
            return 60.0 / max(1, bpm)
        }

        return (60.0 / max(1, bpm)) * (4.0 / division) * count
    }

    private static func lane(from token: String) -> Int? {
        for char in token {
            if let value = char.wholeNumberValue,
               (1...8).contains(value) {
                return value
            }
        }
        return nil
    }
}

struct MaimaiPlaytestView: View {
    let noteText: String
    let bpm: Double
    let firstBeat: Double
    let audioURL: URL?
    let difficulty: ChartDifficulty

    @State private var mode: MaimaiPlayMode = .auto
    @State private var isPlaying = false
    @State private var elapsed = 0.0
    @State private var lastTick = Date()
    @State private var player: AVAudioPlayer?
    @State private var noteSpeed = 1.25
    @State private var trackVolume = 1.0

    @State private var judgedIDs: Set<Int> = []
    @State private var missedIDs: Set<Int> = []
    @State private var partHits: [Int: Set<String>] = [:]
    @State private var partErrors: [Int: Double] = [:]
    @State private var activeHoldSensors: [Int: String] = [:]
    @State private var activeSlideIDs: Set<Int> = []
    @State private var activeSensors: Set<String> = []
    @State private var score = 0
    @State private var combo = 0
    @State private var bestCombo = 0
    @State private var lastJudgment = "READY"

    private let timer = Timer.publish(
        every: 1.0 / 60.0,
        on: .main,
        in: .common
    ).autoconnect()

    private let perfectWindow = 0.065
    private let greatWindow = 0.130
    private let goodWindow = 0.200

    private var events: [MaimaiPreviewEvent] {
        SimaiPreviewParser.parse(
            noteText,
            baseBPM: bpm,
            firstBeat: firstBeat
        )
    }

    private var approachTime: Double {
        1.35 / noteSpeed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    "BUILT-IN MAIMAI PLAYTEST",
                    systemImage: "circle.grid.cross.fill"
                )
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(ArcadePalette.difficulty(difficulty))

                Spacer()

                Text(mode == .manual ? "MULTI-TOUCH" : "AUTO")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(.white)
                    .background(ArcadePalette.ink, in: Capsule())
            }

            Picker("Play Mode", selection: $mode) {
                ForEach(MaimaiPlayMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _ in
                restart()
            }

            if mode == .manual {
                HStack(spacing: 7) {
                    stat("SCORE", "\(score)")
                    stat("COMBO", "\(combo)")
                    stat("BEST", "\(bestCombo)")
                    stat("JUDGE", lastJudgment)
                }
            }

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let hitRadius = side * 0.42
                let spawnRadius = side * 0.10

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    ArcadePalette.cyan.opacity(0.07),
                                    ArcadePalette.purple.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: side * 0.92, height: side * 0.92)

                    Circle()
                        .stroke(
                            ArcadePalette.difficulty(difficulty).opacity(0.38),
                            lineWidth: 5
                        )
                        .frame(width: hitRadius * 2, height: hitRadius * 2)

                    touchSensorGuides(center: center, hitRadius: hitRadius)

                    ForEach(1...8, id: \.self) { lane in
                        let point = lanePoint(lane: lane, radius: hitRadius, center: center)
                        let pressed = activeSensors.contains("L\(lane)")

                        ZStack {
                            Circle()
                                .fill(pressed ? ArcadePalette.pink : ArcadePalette.ink.opacity(0.92))
                            Text("\(lane)")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(width: pressed ? 39 : 34, height: pressed ? 39 : 34)
                        .position(point)
                    }

                    ForEach(visibleEvents) { event in
                        let delta = event.time - elapsed
                        let progress = min(1, max(0, 1 - delta / approachTime))
                        let radius = spawnRadius + (hitRadius - spawnRadius) * CGFloat(progress)

                        if case .slide(let destination) = event.kind,
                           let lane = event.lanes.first {
                            let start = lanePoint(lane: lane, radius: radius, center: center)
                            let end = lanePoint(lane: destination, radius: hitRadius, center: center)

                            Path { path in
                                path.move(to: start)
                                path.addLine(to: end)
                            }
                            .stroke(
                                ArcadePalette.aqua.opacity(0.72),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [8, 5])
                            )
                        }

                        if !event.touchRegions.isEmpty {
                            ForEach(Array(event.touchRegions.enumerated()), id: \.offset) { _, region in
                                let point = touchPoint(region: region, center: center, hitRadius: hitRadius)
                                touchPreviewNote(
                                    region: region,
                                    kind: event.kind,
                                    progress: progress,
                                    holdRemaining: holdRemainingFraction(event),
                                    remainingSeconds: holdRemainingSeconds(event)
                                )
                                .scaleEffect(0.58 + 0.42 * progress)
                                .position(point)
                                .zIndex(7)
                            }
                        }

                        ForEach(Array(event.lanes.enumerated()), id: \.offset) { _, lane in
                            let point = lanePoint(lane: lane, radius: radius, center: center)
                            previewNote(event.kind)
                                .position(point)
                        }
                    }

                    VStack(spacing: 2) {
                        Text(String(format: "%.2f", elapsed))
                            .font(.system(.title3, design: .rounded, weight: .black))

                        Text(mode == .manual ? "PLAY" : "AUTO PLAYTEST")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text("\(resolvedCount) / \(events.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 100, height: 100)
                    .background(.ultraThinMaterial, in: Circle())

                    if mode == .manual {
                        MaimaiTouchInputSurface { sensor, active in
                            handleSensor(sensor, active: active)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(isPlaying)
                        .zIndex(20)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(height: 380)

            HStack(spacing: 9) {
                Button {
                    isPlaying ? pause() : play()
                } label: {
                    Label(
                        isPlaying ? "Pause" : (elapsed > 0 ? "Resume" : "Play"),
                        systemImage: isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    restart()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Image(systemName: audioURL == nil ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(audioURL == nil ? .secondary : ArcadePalette.aqua)

                Text(audioURL == nil ? "TRACK AUDIO NOT RENDERED" : "TRACK AUDIO")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)

                Slider(value: $trackVolume, in: 0...1, step: 0.05)
                    .disabled(audioURL == nil)
                    .onChange(of: trackVolume) { value in
                        player?.volume = Float(value)
                    }

                Text("\(Int(trackVolume * 100))%")
                    .font(.caption2.bold())
                    .frame(width: 34)
            }

            HStack {
                Text("NOTE SPEED")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)

                Slider(value: $noteSpeed, in: 0.75...2.0, step: 0.05)

                Text(String(format: "%.2fx", noteSpeed))
                    .font(.caption.bold())
                    .frame(width: 44)
            }

            Text(
                mode == .manual
                ? "PLAY mode uses real multi-touch input: outer ring = lanes 1–8, inner B/E sensor rings = TOUCH, center = C TOUCH HOLD. Dragging across outer lanes can complete slides."
                : (audioURL == nil
                   ? "Visual playtest uses the chart tempo until score audio is rendered."
                   : "Autoplay is synchronized to the current track audio and selected chart difficulty.")
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .onReceive(timer) { now in
            guard isPlaying else {
                lastTick = now
                return
            }

            if let player {
                elapsed = player.currentTime
                if !player.isPlaying {
                    isPlaying = false
                }
            } else {
                let delta = now.timeIntervalSince(lastTick)
                elapsed += min(0.05, max(0, delta))
            }

            lastTick = now

            if mode == .manual {
                processManualTiming()
            }

            if elapsed > chartEndTime + 1.0 {
                pause()
            }
        }
        .onChange(of: audioURL) { _ in restart() }
        .onChange(of: noteText) { _ in restart() }
        .onChange(of: firstBeat) { _ in restart() }
        .onDisappear { pause() }
    }

    private var visibleEvents: [MaimaiPreviewEvent] {
        events.filter { event in
            if mode == .manual,
               judgedIDs.contains(event.id) || missedIDs.contains(event.id) {
                return false
            }

            let delta = event.time - elapsed
            let lifetime = max(0.12, event.holdDuration)

            if event.kind == .hold || event.kind == .touchHold {
                return delta <= approachTime && elapsed <= event.time + lifetime
            }

            if case .slide = event.kind {
                return delta <= approachTime && elapsed <= event.time + lifetime + 0.15
            }

            return delta <= approachTime && delta >= -0.20
        }
    }

    private var resolvedCount: Int {
        mode == .manual
            ? judgedIDs.count + missedIDs.count
            : events.filter { $0.time <= elapsed }.count
    }

    private var chartEndTime: Double {
        events.map { $0.time + max(0, $0.holdDuration) }.max() ?? 0
    }

    @ViewBuilder
    private func touchSensorGuides(
        center: CGPoint,
        hitRadius: CGFloat
    ) -> some View {
        ForEach(1...8, id: \.self) { lane in
            let b = "B\(lane)"
            let e = "E\(lane)"

            sensorGuide(region: b)
                .position(touchPoint(region: b, center: center, hitRadius: hitRadius))

            sensorGuide(region: e)
                .position(touchPoint(region: e, center: center, hitRadius: hitRadius))
        }

        Circle()
            .stroke(activeSensors.contains("T:C") ? ArcadePalette.pink : ArcadePalette.aqua.opacity(0.18), lineWidth: 2)
            .frame(width: 82, height: 82)
            .position(center)
    }

    private func sensorGuide(region: String) -> some View {
        let active = activeSensors.contains("T:\(region)")
        return Circle()
            .fill(active ? ArcadePalette.pink.opacity(0.30) : Color.clear)
            .overlay(
                Circle().stroke(
                    active ? ArcadePalette.pink : ArcadePalette.aqua.opacity(0.13),
                    lineWidth: active ? 2 : 1
                )
            )
            .frame(width: region.hasPrefix("B") ? 22 : 27, height: region.hasPrefix("B") ? 22 : 27)
    }

    @ViewBuilder
    private func previewNote(_ kind: MaimaiPreviewKind) -> some View {
        switch kind {
        case .tap:
            Circle()
                .fill(ArcadePalette.pink)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .frame(width: 29, height: 29)

        case .breakTap:
            ZStack {
                Circle().fill(ArcadePalette.yellow)
                Image(systemName: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(ArcadePalette.ink)
            }
            .frame(width: 31, height: 31)

        case .hold:
            ZStack {
                Circle().fill(ArcadePalette.aqua)
                Text("H")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 31, height: 31)

        case .slide:
            ZStack {
                Circle().fill(ArcadePalette.pink)
                Image(systemName: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 31, height: 31)

        case .touch, .touchHold:
            EmptyView()
        }
    }

    @ViewBuilder
    private func touchPreviewNote(
        region: String,
        kind: MaimaiPreviewKind,
        progress: Double,
        holdRemaining: Double,
        remainingSeconds: Double
    ) -> some View {
        if kind == .touchHold, region == "C" {
            ZStack {
                Circle()
                    .stroke(ArcadePalette.aqua.opacity(0.22), lineWidth: 12)
                    .frame(width: 98, height: 98)

                Circle()
                    .trim(from: 0, to: max(0.015, elapsed < eventTimeForActiveCenterHold ? 1.0 : holdRemaining))
                    .stroke(
                        ArcadePalette.pink,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 82, height: 82)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ArcadePalette.aqua, ArcadePalette.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(45))

                VStack(spacing: 1) {
                    Text("HOLD")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                    if remainingSeconds > 0 {
                        Text(String(format: "%.1f", remainingSeconds))
                            .font(.system(size: 13, weight: .black, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
            }
        } else {
            ZStack {
                Circle()
                    .fill(region.hasPrefix("B") ? ArcadePalette.aqua : ArcadePalette.pink)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                VStack(spacing: 0) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(region)
                        .font(.system(size: 7, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)
            .opacity(0.62 + 0.38 * progress)
        }
    }

    private var eventTimeForActiveCenterHold: Double {
        visibleEvents.first(where: {
            $0.kind == .touchHold && $0.touchRegions.contains("C")
        })?.time ?? .infinity
    }

    private func touchPoint(
        region: String,
        center: CGPoint,
        hitRadius: CGFloat
    ) -> CGPoint {
        if region == "C" { return center }

        guard let lane = region.compactMap({ $0.wholeNumberValue }).first else {
            return center
        }

        let prefix = String(region.prefix(1))
        let radius: CGFloat
        switch prefix {
        case "A": radius = hitRadius * 0.82
        case "B": radius = hitRadius * 0.42
        case "D": radius = hitRadius * 0.54
        default: radius = hitRadius * 0.66
        }

        return lanePoint(lane: lane, radius: radius, center: center)
    }

    private func lanePoint(
        lane: Int,
        radius: CGFloat,
        center: CGPoint
    ) -> CGPoint {
        let angle = -Double.pi / 2 + Double(lane - 1) * (2 * Double.pi / 8)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func handleSensor(
        _ sensor: MaimaiInputSensor,
        active: Bool
    ) {
        let key = sensor.key

        if active {
            activeSensors.insert(key)
        } else {
            activeSensors.remove(key)
        }

        guard mode == .manual, isPlaying else { return }

        if active {
            judgeSensorStart(sensor)
        } else {
            judgeSensorEnd(sensor)
        }
    }

    private func judgeSensorStart(_ sensor: MaimaiInputSensor) {
        let key = sensor.key

        // A slide is completed by reaching its destination sensor after its
        // start has already been judged.
        if case .lane(let lane) = sensor {
            let slideCandidate = events
                .filter { event in
                    guard activeSlideIDs.contains(event.id),
                          !judgedIDs.contains(event.id),
                          !missedIDs.contains(event.id),
                          case .slide(let destination) = event.kind,
                          destination == lane else {
                        return false
                    }

                    let target = event.time + max(0.08, event.holdDuration)
                    return elapsed >= event.time + 0.04 &&
                           elapsed <= target + goodWindow
                }
                .min {
                    abs(($0.time + max(0.08, $0.holdDuration)) - elapsed) <
                    abs(($1.time + max(0.08, $1.holdDuration)) - elapsed)
                }

            if let slideCandidate {
                let target = slideCandidate.time + max(0.08, slideCandidate.holdDuration)
                let endError = abs(elapsed - target)
                let startError = partErrors[slideCandidate.id] ?? 0
                complete(
                    slideCandidate,
                    error: max(startError, endError)
                )
                activeSlideIDs.remove(slideCandidate.id)
                return
            }
        }

        let candidates = events
            .filter { event in
                !judgedIDs.contains(event.id) &&
                !missedIDs.contains(event.id) &&
                !activeSlideIDs.contains(event.id) &&
                abs(event.time - elapsed) <= goodWindow &&
                event.expectedKeys.contains(key)
            }
            .sorted {
                abs($0.time - elapsed) < abs($1.time - elapsed)
            }

        guard let event = candidates.first else {
            lastJudgment = "MISS"
            combo = 0
            return
        }

        let error = abs(event.time - elapsed)
        partErrors[event.id] = max(partErrors[event.id] ?? 0, error)
        var hits = partHits[event.id] ?? []
        hits.insert(key)
        partHits[event.id] = hits

        switch event.kind {
        case .hold, .touchHold:
            activeHoldSensors[event.id] = key
            lastJudgment = timingName(error)

        case .slide:
            activeSlideIDs.insert(event.id)
            lastJudgment = "SLIDE"

        case .tap, .breakTap, .touch:
            if event.expectedKeys.isSubset(of: hits) {
                complete(event, error: partErrors[event.id] ?? error)
            }
        }
    }

    private func judgeSensorEnd(_ sensor: MaimaiInputSensor) {
        let key = sensor.key
        let holding = activeHoldSensors.filter { $0.value == key }

        for (id, _) in holding {
            guard let event = events.first(where: { $0.id == id }) else {
                activeHoldSensors.removeValue(forKey: id)
                continue
            }

            let heldUntil = event.time + max(0.08, event.holdDuration)
            let required = event.time + max(0.08, event.holdDuration) * 0.75

            if elapsed >= required {
                let releaseError = max(0, heldUntil - elapsed)
                complete(
                    event,
                    error: max(partErrors[id] ?? 0, min(goodWindow, releaseError))
                )
            } else {
                miss(event)
            }

            activeHoldSensors.removeValue(forKey: id)
        }
    }

    private func processManualTiming() {
        var toComplete: [MaimaiPreviewEvent] = []
        var toMiss: [MaimaiPreviewEvent] = []

        for event in events {
            guard !judgedIDs.contains(event.id), !missedIDs.contains(event.id) else {
                continue
            }

            if let sensorKey = activeHoldSensors[event.id] {
                let end = event.time + max(0.08, event.holdDuration)
                if elapsed >= end {
                    if activeSensors.contains(sensorKey) {
                        toComplete.append(event)
                    } else {
                        toMiss.append(event)
                    }
                }
                continue
            }

            if activeSlideIDs.contains(event.id) {
                let end = event.time + max(0.08, event.holdDuration)
                if elapsed > end + goodWindow {
                    toMiss.append(event)
                }
                continue
            }

            if elapsed > event.time + goodWindow {
                toMiss.append(event)
            }
        }

        for event in toComplete {
            complete(event, error: partErrors[event.id] ?? 0)
            activeHoldSensors.removeValue(forKey: event.id)
        }

        for event in toMiss {
            miss(event)
            activeHoldSensors.removeValue(forKey: event.id)
            activeSlideIDs.remove(event.id)
        }
    }

    private func complete(
        _ event: MaimaiPreviewEvent,
        error: Double
    ) {
        guard !judgedIDs.contains(event.id), !missedIDs.contains(event.id) else {
            return
        }

        let grade = timingName(error)
        let base: Int
        switch grade {
        case "PERFECT": base = 1000
        case "GREAT": base = 700
        default: base = 400
        }

        let units = max(1, event.expectedKeys.count)
        let breakBonus = event.kind == .breakTap ? 500 : 0

        score += base * units + breakBonus
        combo += units
        bestCombo = max(bestCombo, combo)
        lastJudgment = grade
        judgedIDs.insert(event.id)
        partHits.removeValue(forKey: event.id)
        partErrors.removeValue(forKey: event.id)
        activeHoldSensors.removeValue(forKey: event.id)
        activeSlideIDs.remove(event.id)
    }

    private func miss(_ event: MaimaiPreviewEvent) {
        guard !judgedIDs.contains(event.id), !missedIDs.contains(event.id) else {
            return
        }

        missedIDs.insert(event.id)
        combo = 0
        lastJudgment = "MISS"
        partHits.removeValue(forKey: event.id)
        partErrors.removeValue(forKey: event.id)
    }

    private func timingName(_ error: Double) -> String {
        if error <= perfectWindow { return "PERFECT" }
        if error <= greatWindow { return "GREAT" }
        return "GOOD"
    }

    private func holdRemainingFraction(_ event: MaimaiPreviewEvent) -> Double {
        guard event.holdDuration > 0 else { return 0 }
        if elapsed <= event.time { return 1 }
        return max(0, min(1, 1 - (elapsed - event.time) / event.holdDuration))
    }

    private func holdRemainingSeconds(_ event: MaimaiPreviewEvent) -> Double {
        guard event.holdDuration > 0 else { return 0 }
        if elapsed <= event.time { return event.holdDuration }
        return max(0, event.time + event.holdDuration - elapsed)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
    }

    private func play() {
        if let audioURL {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                // Visual/manual play remains available if the session cannot
                // be changed by the sideloaded environment.
            }

            if player == nil {
                player = try? AVAudioPlayer(contentsOf: audioURL)
                player?.prepareToPlay()
            }

            player?.volume = Float(trackVolume)
            player?.currentTime = elapsed
            player?.play()
        }

        lastTick = Date()
        isPlaying = true
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        activeSensors.removeAll()
    }

    private func restart() {
        player?.stop()
        player = nil
        elapsed = 0
        lastTick = Date()
        isPlaying = false
        activeSensors.removeAll()
        activeHoldSensors.removeAll()
        activeSlideIDs.removeAll()
        judgedIDs.removeAll()
        missedIDs.removeAll()
        partHits.removeAll()
        partErrors.removeAll()
        score = 0
        combo = 0
        bestCombo = 0
        lastJudgment = "READY"
    }
}
