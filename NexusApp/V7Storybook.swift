import SwiftUI
import AVFoundation

@MainActor
final class NexusStoryMusic: ObservableObject {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?
    private var generatedURL: URL?

    func toggle() {
        isPlaying ? stop() : play()
    }

    func play() {
        do {
            let url = try generatedURL ?? makeLoop()
            generatedURL = url
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.16
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func makeLoop() throws -> URL {
        let rate = 22_050
        let duration = 8.0
        let count = Int(Double(rate) * duration)
        let progression: [[Double]] = [
            [261.63, 329.63, 392.00],
            [220.00, 261.63, 329.63],
            [174.61, 220.00, 261.63],
            [196.00, 246.94, 293.66]
        ]
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let beat = Int(t / 2.0) % progression.count
            let chord = progression[beat]
            let local = t.truncatingRemainder(dividingBy: 2.0)
            let envelope = min(1.0, local * 3.0) * min(1.0, (2.0 - local) * 2.2)
            let bell = chord.enumerated().reduce(0.0) { partial, pair in
                let (idx, frequency) = pair
                let phase = 2.0 * Double.pi * frequency * t
                let harmonic = sin(phase) + 0.22 * sin(phase * 2.0 + Double(idx))
                return partial + harmonic
            } / Double(chord.count)
            let sparkle = 0.12 * sin(2.0 * Double.pi * chord[2] * 2.0 * t) * pow(max(0, sin(Double.pi * t)), 2)
            let value = max(-1.0, min(1.0, (bell * 0.42 + sparkle) * envelope))
            appendLE(Int16(value * Double(Int16.max)), to: &pcm)
        }

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        appendLE(UInt32(36 + pcm.count), to: &wav)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        appendLE(UInt32(16), to: &wav)
        appendLE(UInt16(1), to: &wav)
        appendLE(UInt16(1), to: &wav)
        appendLE(UInt32(rate), to: &wav)
        appendLE(UInt32(rate * 2), to: &wav)
        appendLE(UInt16(2), to: &wav)
        appendLE(UInt16(16), to: &wav)
        wav.append("data".data(using: .ascii)!)
        appendLE(UInt32(pcm.count), to: &wav)
        wav.append(pcm)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-storybook-loop.wav")
        try wav.write(to: url, options: .atomic)
        return url
    }

    private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}

struct NexusBuddyCharacter: View {
    enum Mood { case curious, happy, thoughtful }
    let variant: Int
    let mood: Mood
    let phase: Double

    var body: some View {
        let bodyColor: Color = variant % 2 == 0 ? .cyan : .yellow
        let accent: Color = variant % 2 == 0 ? .indigo : .orange
        ZStack {
            Capsule()
                .fill(bodyColor.gradient)
                .frame(width: 76, height: 92)
                .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 3))
                .shadow(radius: 7, y: 5)
            HStack(spacing: 17) {
                Circle().fill(.white).frame(width: 17, height: 21).overlay(Circle().fill(accent).frame(width: 7, height: 9).offset(y: 2))
                Circle().fill(.white).frame(width: 17, height: 21).overlay(Circle().fill(accent).frame(width: 7, height: 9).offset(y: 2))
            }.offset(y: -15)
            mouth.offset(y: 14)
            Circle().fill(.pink.opacity(0.45)).frame(width: 14, height: 8).offset(x: -25, y: 7)
            Circle().fill(.pink.opacity(0.45)).frame(width: 14, height: 8).offset(x: 25, y: 7)
            Capsule().fill(bodyColor).frame(width: 12, height: 42).rotationEffect(.degrees(-34 + sin(phase) * 9)).offset(x: -42, y: 12)
            Capsule().fill(bodyColor).frame(width: 12, height: 42).rotationEffect(.degrees(34 - sin(phase) * 9)).offset(x: 42, y: 12)
            if variant % 2 == 1 {
                Image(systemName: "sparkle").font(.title2.bold()).foregroundStyle(.white).offset(y: -47)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.caption.bold()).foregroundStyle(.white).offset(y: -48)
            }
        }
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .happy:
            Capsule().fill(.white.opacity(0.92)).frame(width: 26, height: 11)
        case .curious:
            Circle().stroke(.white, lineWidth: 3).frame(width: 13, height: 13)
        case .thoughtful:
            Capsule().fill(.white.opacity(0.92)).frame(width: 20, height: 5).rotationEffect(.degrees(-7))
        }
    }
}

struct NexusAnimatedStoryScene: View {
    let page: NexusStoryPage

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(.white.opacity(0.10)).frame(width: geo.size.width * 0.72).offset(x: geo.size.width * 0.34 + sin(t * 0.18) * 15, y: -geo.size.height * 0.28)
                    ForEach(0..<6, id: \.self) { i in
                        Image(systemName: i % 2 == 0 ? "sparkles" : "star.fill")
                            .foregroundStyle(.white.opacity(0.45 + Double(i % 3) * 0.12))
                            .font(.system(size: CGFloat(12 + i * 3)))
                            .offset(x: CGFloat(sin(t * (0.22 + Double(i) * 0.03) + Double(i)) * Double(geo.size.width * 0.42)),
                                    y: CGFloat(cos(t * 0.16 + Double(i) * 1.7) * Double(geo.size.height * 0.30)))
                    }
                    RoundedRectangle(cornerRadius: 60)
                        .fill(.white.opacity(0.12))
                        .frame(width: geo.size.width * 1.2, height: 125)
                        .offset(y: geo.size.height * 0.42)

                    NexusBuddyCharacter(variant: page.accentIndex, mood: .happy, phase: t * 2.1)
                        .offset(x: -geo.size.width * 0.23, y: geo.size.height * 0.17 + CGFloat(sin(t * 2.1) * 7))
                        .rotationEffect(.degrees(sin(t * 1.4) * 2.5))
                    NexusBuddyCharacter(variant: page.accentIndex + 1, mood: .curious, phase: t * 1.8 + 2)
                        .scaleEffect(0.82)
                        .offset(x: geo.size.width * 0.25, y: geo.size.height * 0.23 + CGFloat(cos(t * 1.8) * 6))
                        .rotationEffect(.degrees(-sin(t * 1.1) * 3))

                    VStack {
                        HStack {
                            Label(page.subtitle, systemImage: page.symbol).font(.caption.bold()).foregroundStyle(.white.opacity(0.88))
                            Spacer()
                            Text("NEXUS STORY").font(.caption2.black()).tracking(1.4).foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                    }.padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28))
            }
        }
    }

    private var palette: [Color] {
        let options: [[Color]] = [[.blue,.purple],[.mint,.blue],[.orange,.pink],[.indigo,.cyan],[.green,.teal],[.purple,.pink]]
        return options[abs(page.accentIndex) % options.count]
    }
}

struct StorybookV7View: View {
    @EnvironmentObject var model: NexusModel
    @StateObject private var narrator = NexusStoryNarrator()
    @StateObject private var music = NexusStoryMusic()
    @State private var mode: JourneyStoryMode = .journey
    @State private var index = 0
    @State private var rewrites: [String:String] = [:]
    @State private var rewriting = false
    @State private var autoNarrate = false

    var body: some View {
        let pages = model.storyPages(mode: mode)
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(JourneyStoryMode.allCases) { item in
                        Button {
                            mode = item
                            index = 0
                            narrator.stop()
                        } label: {
                            Label(item.rawValue, systemImage: item.symbol).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(mode == item ? Color.cyan.opacity(0.22) : Color.secondary.opacity(0.10), in: Capsule())
                    }
                }.padding(.horizontal)
            }.padding(.vertical, 8)

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                    ScrollView {
                        VStack(spacing: 12) {
                            NexusAnimatedStoryScene(page: page).frame(height: 285)
                            VStack(alignment: .leading, spacing: 10) {
                                Text(page.title).font(.system(size: 28, weight: .black, design: .rounded))
                                Text(rewrites[page.id] ?? page.body).font(.system(size: 17, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                                HStack {
                                    Label("Evidence-backed", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                                    Spacer()
                                    Text("\(page.evidence.count) traces").foregroundStyle(.secondary)
                                }.font(.caption.bold())
                                DisclosureGroup("Show source evidence") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(page.evidence, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                                    }.padding(.top, 5)
                                }.font(.caption.bold()).tint(.cyan)
                            }.padding(.horizontal, 4)
                        }.padding(.horizontal).padding(.bottom, 80)
                    }.tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .onChange(of: index) { _, newValue in
                narrator.stop()
                if autoNarrate, pages.indices.contains(newValue) {
                    let p = pages[newValue]
                    narrator.speak(rewrites[p.id] ?? p.body)
                }
            }

            if pages.indices.contains(index) {
                let page = pages[index]
                HStack(spacing: 9) {
                    Button {
                        narrator.isSpeaking ? narrator.stop() : narrator.speak(rewrites[page.id] ?? page.body)
                    } label: { Label(narrator.isSpeaking ? "Stop" : "Narrate", systemImage: narrator.isSpeaking ? "stop.fill" : "speaker.wave.2.fill") }
                        .buttonStyle(.borderedProminent)
                    Button { music.toggle() } label: { Label(music.isPlaying ? "Music on" : "Music", systemImage: music.isPlaying ? "music.note.list" : "music.note") }.buttonStyle(.bordered)
                    Button { autoNarrate.toggle() } label: { Image(systemName: autoNarrate ? "autostartstop" : "text.badge.checkmark") }.buttonStyle(.bordered)
                    if NexusIntelligenceEngine.appleIntelligenceAvailable {
                        Button { magic(page) } label: { rewriting ? AnyView(ProgressView().controlSize(.small)) : AnyView(Image(systemName: "apple.intelligence")) }.buttonStyle(.bordered).disabled(rewriting)
                    }
                }
                .padding(.horizontal).padding(.vertical, 9)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("Living Storybook")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { narrator.stop(); music.stop() }
    }

    private func magic(_ page: NexusStoryPage) {
        rewriting = true
        Task {
            let context = ([page.body] + page.evidence).joined(separator: "\n")
            let result = await NexusIntelligenceEngine.respond(
                question: "Rewrite this personal story page as a warm, playful animated-story narration for an adult reader. Preserve every factual claim and do not invent people, motives, dialogue or events.",
                context: context
            )
            if let result, !result.isEmpty { rewrites[page.id] = result }
            rewriting = false
        }
    }
}
