import SwiftUI
import AVFoundation
import Combine

private enum MaimaiPreviewKind {
    case tap
    case breakTap
    case hold
    case slide(destination: Int)
    case touch
    case touchHold
}

private struct MaimaiPreviewEvent: Identifiable {
    let id = UUID()
    let time: Double
    let lanes: [Int]
    let kind: MaimaiPreviewKind
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

            if !token.isEmpty {
                if let event = event(
                    from: token,
                    time: time
                ) {
                    output.append(event)
                }
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
        from token: String,
        time: Double
    ) -> MaimaiPreviewEvent? {
        let cleaned = token.trimmingCharacters(in: .whitespaces)

        if cleaned.hasPrefix("C") {
            return MaimaiPreviewEvent(
                time: time,
                lanes: [],
                kind: cleaned.contains("h[") ? .touchHold : .touch
            )
        }

        if token.contains("/") {
            let lanes = token
                .split(separator: "/")
                .compactMap { lane(from: String($0)) }

            guard !lanes.isEmpty else { return nil }

            return MaimaiPreviewEvent(
                time: time,
                lanes: lanes,
                kind: .tap
            )
        }

        if token.contains("-"),
           let start = lane(from: token),
           let dash = token.firstIndex(of: "-") {
            let suffix = token[token.index(after: dash)...]
            if let destination = lane(from: String(suffix)) {
                return MaimaiPreviewEvent(
                    time: time,
                    lanes: [start],
                    kind: .slide(destination: destination)
                )
            }
        }

        guard let lane = lane(from: token) else {
            return nil
        }

        if token.contains("h[") {
            return MaimaiPreviewEvent(
                time: time,
                lanes: [lane],
                kind: .hold
            )
        }

        if token.contains("b") {
            return MaimaiPreviewEvent(
                time: time,
                lanes: [lane],
                kind: .breakTap
            )
        }

        return MaimaiPreviewEvent(
            time: time,
            lanes: [lane],
            kind: .tap
        )
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

    @State private var isPlaying = false
    @State private var elapsed = 0.0
    @State private var lastTick = Date()
    @State private var player: AVAudioPlayer?
    @State private var noteSpeed = 1.25
    @State private var trackVolume = 1.0

    private let timer = Timer.publish(
        every: 1.0 / 60.0,
        on: .main,
        in: .common
    ).autoconnect()

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
                .font(.system(
                    size: 10,
                    weight: .black,
                    design: .rounded
                ))
                .foregroundStyle(
                    ArcadePalette.difficulty(difficulty)
                )

                Spacer()

                Text("8 LANE")
                    .font(.system(
                        size: 9,
                        weight: .black,
                        design: .rounded
                    ))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .foregroundStyle(.white)
                    .background(
                        ArcadePalette.ink,
                        in: Capsule()
                    )
            }

            GeometryReader { proxy in
                let side = min(
                    proxy.size.width,
                    proxy.size.height
                )
                let center = CGPoint(
                    x: proxy.size.width / 2,
                    y: proxy.size.height / 2
                )
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
                        .frame(
                            width: side * 0.92,
                            height: side * 0.92
                        )

                    Circle()
                        .stroke(
                            ArcadePalette.difficulty(difficulty)
                                .opacity(0.38),
                            lineWidth: 5
                        )
                        .frame(
                            width: hitRadius * 2,
                            height: hitRadius * 2
                        )

                    ForEach(1...8, id: \.self) { lane in
                        let point = lanePoint(
                            lane: lane,
                            radius: hitRadius,
                            center: center
                        )

                        ZStack {
                            Circle()
                                .fill(
                                    ArcadePalette.ink.opacity(0.92)
                                )
                            Text("\(lane)")
                                .font(.system(
                                    size: 11,
                                    weight: .black,
                                    design: .rounded
                                ))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)
                        .position(point)
                    }

                    ForEach(visibleEvents) { event in
                        let delta = event.time - elapsed
                        let progress = min(
                            1,
                            max(
                                0,
                                1 - delta / approachTime
                            )
                        )
                        let radius =
                            spawnRadius +
                            (hitRadius - spawnRadius) *
                            CGFloat(progress)

                        if case .slide(let destination) = event.kind,
                           let lane = event.lanes.first {
                            let start = lanePoint(
                                lane: lane,
                                radius: radius,
                                center: center
                            )
                            let end = lanePoint(
                                lane: destination,
                                radius: hitRadius,
                                center: center
                            )

                            Path { path in
                                path.move(to: start)
                                path.addLine(to: end)
                            }
                            .stroke(
                                ArcadePalette.aqua.opacity(0.70),
                                style: StrokeStyle(
                                    lineWidth: 5,
                                    lineCap: .round,
                                    dash: [8, 5]
                                )
                            )
                        }

                        if event.lanes.isEmpty {
                            centerPreviewNote(event.kind, progress: progress)
                                .position(center)
                        } else {
                            ForEach(
                                Array(event.lanes.enumerated()),
                                id: \.offset
                            ) { _, lane in
                                let point = lanePoint(
                                    lane: lane,
                                    radius: radius,
                                    center: center
                                )

                                previewNote(event.kind)
                                    .position(point)
                            }
                        }
                    }

                    VStack(spacing: 2) {
                        Text(
                            String(
                                format: "%.2f",
                                elapsed
                            )
                        )
                        .font(.system(
                            .title3,
                            design: .rounded,
                            weight: .black
                        ))

                        Text("AUTO PLAYTEST")
                            .font(.system(
                                size: 8,
                                weight: .black,
                                design: .rounded
                            ))
                            .foregroundStyle(.secondary)

                        Text(
                            "\(events.filter { $0.time <= elapsed }.count) / \(events.count)"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .frame(width: 105, height: 105)
                    .background(
                        .ultraThinMaterial,
                        in: Circle()
                    )
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
            }
            .frame(height: 360)

            HStack(spacing: 9) {
                Button {
                    isPlaying ? pause() : play()
                } label: {
                    Label(
                        isPlaying
                            ? "Pause"
                            : (elapsed > 0 ? "Resume" : "Play"),
                        systemImage:
                            isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    restart()
                } label: {
                    Label(
                        "Restart",
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Image(systemName: audioURL == nil ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(audioURL == nil ? .secondary : ArcadePalette.aqua)

                Text(audioURL == nil ? "TRACK AUDIO NOT RENDERED" : "TRACK AUDIO")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)

                Slider(
                    value: $trackVolume,
                    in: 0...1,
                    step: 0.05
                )
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
                    .font(.system(
                        size: 9,
                        weight: .black,
                        design: .rounded
                    ))
                    .foregroundStyle(.secondary)

                Slider(
                    value: $noteSpeed,
                    in: 0.75...2.0,
                    step: 0.05
                )

                Text(
                    String(
                        format: "%.2fx",
                        noteSpeed
                    )
                )
                .font(.caption.bold())
                .frame(width: 44)
            }

            Text(
                audioURL == nil
                ? "Visual playtest uses the chart tempo until score audio is rendered."
                : "Playtest is synchronized to the current track audio and the selected chart difficulty."
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

            if let last = events.last,
               elapsed > last.time + 1.0 {
                pause()
            }
        }
        .onChange(of: audioURL) { _ in
            player?.stop()
            player = nil
            isPlaying = false
            elapsed = 0
        }
        .onChange(of: noteText) { _ in
            restart()
        }
        .onDisappear {
            pause()
        }
    }

    private var visibleEvents: [MaimaiPreviewEvent] {
        events.filter {
            let delta = $0.time - elapsed
            return delta <= approachTime &&
                   delta >= -0.12
        }
    }

    @ViewBuilder
    private func previewNote(
        _ kind: MaimaiPreviewKind
    ) -> some View {
        switch kind {
        case .tap:
            Circle()
                .fill(
                    ArcadePalette.difficulty(difficulty)
                )
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: 3)
                )
                .frame(width: 28, height: 28)

        case .breakTap:
            ZStack {
                Circle()
                    .fill(ArcadePalette.yellow)
                Image(systemName: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(ArcadePalette.ink)
            }
            .frame(width: 31, height: 31)

        case .hold:
            ZStack {
                Circle()
                    .fill(ArcadePalette.aqua)
                Text("H")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 31, height: 31)

        case .slide:
            ZStack {
                Circle()
                    .fill(ArcadePalette.pink)
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
    private func centerPreviewNote(
        _ kind: MaimaiPreviewKind,
        progress: Double
    ) -> some View {
        switch kind {
        case .touchHold:
            ZStack {
                Circle()
                    .stroke(
                        ArcadePalette.aqua.opacity(0.28),
                        lineWidth: 12
                    )
                    .frame(width: 92, height: 92)

                Circle()
                    .trim(from: 0, to: max(0.08, progress))
                    .stroke(
                        ArcadePalette.pink,
                        style: StrokeStyle(
                            lineWidth: 7,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 78, height: 78)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                ArcadePalette.aqua,
                                ArcadePalette.purple
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .rotationEffect(.degrees(45))

                Text("HOLD")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

        case .touch:
            ZStack {
                Circle()
                    .fill(ArcadePalette.aqua.opacity(0.92))
                    .frame(width: 58, height: 58)
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(.white)
            }

        default:
            EmptyView()
        }
    }

    private func lanePoint(
        lane: Int,
        radius: CGFloat,
        center: CGPoint
    ) -> CGPoint {
        let angle =
            -Double.pi / 2 +
            Double(lane - 1) *
            (2 * Double.pi / 8)

        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func play() {
        if let audioURL {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                // AVAudioPlayer can still attempt playback; the visual
                // playtest remains usable if the session cannot be changed.
            }

            if player == nil {
                player = try? AVAudioPlayer(
                    contentsOf: audioURL
                )
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
    }

    private func restart() {
        player?.stop()
        player = nil
        elapsed = 0
        lastTick = Date()
        isPlaying = false
    }
}
