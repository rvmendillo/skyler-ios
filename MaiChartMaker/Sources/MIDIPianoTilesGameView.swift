import SwiftUI

struct MIDIPianoTilesGameView: View {
    let notes: [PianoGameNote]
    let onPlayNote: (UInt8, UInt8) -> Void
    let onStopNote: (UInt8) -> Void
    let onStopAll: () -> Void

    @State private var isPlaying = false
    @State private var elapsed = 0.0
    @State private var lastTick = Date()
    @State private var hitIDs: Set<UUID> = []
    @State private var missedIDs: Set<UUID> = []
    @State private var score = 0
    @State private var combo = 0
    @State private var bestCombo = 0
    @State private var laneFlash: Int?

    private let timer = Timer.publish(
        every: 1.0 / 60.0,
        on: .main,
        in: .common
    ).autoconnect()

    private let leadTime = 2.65
    private let hitWindow = 0.22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("PIANO TILES MIDI TEST", systemImage: "rectangle.split.3x1.fill")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(ArcadePalette.purple)

                Spacer()

                Text("4 BLACK KEYS")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.86), in: Capsule())
            }

            HStack(spacing: 8) {
                stat("SCORE", "\(score)")
                stat("COMBO", "\(combo)")
                stat("BEST", "\(bestCombo)")
            }

            GeometryReader { proxy in
                let laneGap: CGFloat = 4
                let laneWidth = (proxy.size.width - laneGap * 3) / 4
                let hitY = proxy.size.height - 76
                let travel = max(80, hitY - 18)
                let pixelsPerSecond = travel / leadTime

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.035),
                                    ArcadePalette.purple.opacity(0.055)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    ForEach(0..<4, id: \.self) { lane in
                        Rectangle()
                            .fill(Color.black.opacity(0.045))
                            .frame(width: 1)
                            .offset(
                                x: CGFloat(lane) * (laneWidth + laneGap) - laneGap / 2,
                                y: 0
                            )
                    }

                    ForEach(visibleNotes(hitY: hitY, pixelsPerSecond: pixelsPerSecond)) { note in
                        let y = hitY - CGFloat(note.time - elapsed) * pixelsPerSecond
                        let height = max(
                            30,
                            min(
                                76,
                                CGFloat(max(0.08, note.duration)) * pixelsPerSecond * 0.58
                            )
                        )

                        FallingMIDITile(note: note)
                            .frame(width: laneWidth - 8, height: height)
                            .offset(
                                x: CGFloat(note.lane) * (laneWidth + laneGap) + 4,
                                y: y - height
                            )
                    }

                    Rectangle()
                        .fill(ArcadePalette.pink.opacity(0.55))
                        .frame(height: 2)
                        .offset(y: hitY)

                    HStack(spacing: laneGap) {
                        ForEach(0..<4, id: \.self) { lane in
                            Button {
                                hit(lane: lane)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: laneFlash == lane
                                                    ? [ArcadePalette.purple, ArcadePalette.pink]
                                                    : [Color.black.opacity(0.96), ArcadePalette.ink],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )

                                    VStack(spacing: 2) {
                                        Text("\(lane + 1)")
                                            .font(.system(size: 15, weight: .black, design: .rounded))
                                        Text("TAP")
                                            .font(.system(size: 8, weight: .black, design: .rounded))
                                            .opacity(0.68)
                                    }
                                    .foregroundStyle(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: laneWidth, height: 62)
                        }
                    }
                    .offset(y: hitY + 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ArcadePalette.purple.opacity(0.13), lineWidth: 1)
                )
            }
            .frame(height: 410)

            HStack(spacing: 9) {
                Button {
                    if isPlaying {
                        pause()
                    } else {
                        startOrResume()
                    }
                } label: {
                    Label(
                        isPlaying ? "Pause" : (elapsed > 0 ? "Resume" : "Start"),
                        systemImage: isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    reset()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            Text(
                notes.isEmpty
                ? "Import MIDI or MusicXML to load falling notes."
                : "Tiles use the MIDI's exact note timing. Tap one of the four black keys when a falling tile reaches the pink line."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .onReceive(timer) { now in
            guard isPlaying else {
                lastTick = now
                return
            }

            let delta = now.timeIntervalSince(lastTick)
            lastTick = now
            elapsed += min(0.05, max(0, delta))
            markMisses()

            if let end = notes.last?.time, elapsed > end + 1.0 {
                pause()
            }
        }
        .onDisappear {
            pause()
            onStopAll()
        }
    }

    private func visibleNotes(
        hitY: CGFloat,
        pixelsPerSecond: CGFloat
    ) -> [PianoGameNote] {
        notes.filter { note in
            guard !hitIDs.contains(note.id), !missedIDs.contains(note.id) else {
                return false
            }
            let y = hitY - CGFloat(note.time - elapsed) * pixelsPerSecond
            return y > -100 && y < hitY + 86
        }
    }

    private func hit(lane: Int) {
        let candidates = notes
            .filter {
                $0.lane == lane &&
                !hitIDs.contains($0.id) &&
                !missedIDs.contains($0.id) &&
                abs($0.time - elapsed) <= hitWindow
            }
            .sorted { abs($0.time - elapsed) < abs($1.time - elapsed) }

        guard let note = candidates.first else {
            combo = 0
            flash(lane)
            return
        }

        hitIDs.insert(note.id)
        combo += 1
        bestCombo = max(bestCombo, combo)

        let error = abs(note.time - elapsed)
        if error <= 0.075 {
            score += 1000
        } else if error <= 0.14 {
            score += 700
        } else {
            score += 400
        }

        onPlayNote(note.midiNote, note.velocity)
        DispatchQueue.main.asyncAfter(deadline: .now() + min(0.8, max(0.12, note.duration))) {
            onStopNote(note.midiNote)
        }

        flash(lane)
    }

    private func markMisses() {
        var didMiss = false

        for note in notes where
            !hitIDs.contains(note.id) &&
            !missedIDs.contains(note.id) &&
            note.time < elapsed - hitWindow {
            missedIDs.insert(note.id)
            didMiss = true
        }

        if didMiss {
            combo = 0
        }
    }

    private func flash(_ lane: Int) {
        laneFlash = lane
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            if laneFlash == lane {
                laneFlash = nil
            }
        }
    }

    private func startOrResume() {
        guard !notes.isEmpty else { return }
        if let end = notes.last?.time, elapsed > end + 0.8 {
            reset()
        }
        lastTick = Date()
        isPlaying = true
    }

    private func pause() {
        isPlaying = false
        onStopAll()
    }

    private func reset() {
        isPlaying = false
        elapsed = 0
        hitIDs.removeAll()
        missedIDs.removeAll()
        score = 0
        combo = 0
        bestCombo = 0
        laneFlash = nil
        lastTick = Date()
        onStopAll()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .black))
            Text(label)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct FallingMIDITile: View {
    let note: PianoGameNote

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.96), ArcadePalette.ink],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)

            VStack(spacing: 1) {
                Text(noteName(note.midiNote))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                Text("\(note.midiNote)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .opacity(0.68)
            }
            .foregroundStyle(.white)
        }
    }

    private func noteName(_ midi: UInt8) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let value = Int(midi)
        let octave = value / 12 - 1
        return "\(names[value % 12])\(octave)"
    }
}
