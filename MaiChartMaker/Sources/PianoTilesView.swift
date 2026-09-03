import SwiftUI

struct PianoTilesView: View {
    let octave: Int
    let onNoteOn: (UInt8) -> Void
    let onNoteOff: (UInt8) -> Void

    private let whiteKeys: [(name: String, semitone: Int)] = [
        ("C", 0), ("D", 2), ("E", 4), ("F", 5), ("G", 7), ("A", 9), ("B", 11)
    ]

    private let blackKeys: [(name: String, semitone: Int, whiteIndex: Int)] = [
        ("C♯", 1, 0),
        ("D♯", 3, 1),
        ("F♯", 6, 3),
        ("G♯", 8, 4),
        ("A♯", 10, 5)
    ]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let whiteWidth = (proxy.size.width - gap * 6) / 7
            let blackWidth = whiteWidth * 0.62

            ZStack(alignment: .topLeading) {
                HStack(spacing: gap) {
                    ForEach(Array(whiteKeys.enumerated()), id: \.offset) { _, key in
                        PianoTile(
                            label: key.name,
                            midi: midiNote(semitone: key.semitone),
                            isBlack: false,
                            onNoteOn: onNoteOn,
                            onNoteOff: onNoteOff
                        )
                        .frame(width: whiteWidth)
                    }
                }

                ForEach(Array(blackKeys.enumerated()), id: \.offset) { _, key in
                    PianoTile(
                        label: key.name,
                        midi: midiNote(semitone: key.semitone),
                        isBlack: true,
                        onNoteOn: onNoteOn,
                        onNoteOff: onNoteOff
                    )
                    .frame(width: blackWidth, height: 92)
                    .offset(
                        x: CGFloat(key.whiteIndex + 1) * (whiteWidth + gap) - blackWidth / 2 - gap / 2,
                        y: 0
                    )
                    .zIndex(2)
                }
            }
        }
        .frame(height: 148)
    }

    private func midiNote(semitone: Int) -> UInt8 {
        UInt8(clamping: (octave + 1) * 12 + semitone)
    }
}

private struct PianoTile: View {
    let label: String
    let midi: UInt8
    let isBlack: Bool
    let onNoteOn: (UInt8) -> Void
    let onNoteOff: (UInt8) -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: isBlack ? 7 : 10, style: .continuous)
                .fill(
                    isBlack
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.black.opacity(0.92), ArcadePalette.ink],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                isPressed ? ArcadePalette.cyan.opacity(0.20) : .white,
                                Color(red: 0.94, green: 0.96, blue: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .shadow(
                    color: isBlack ? .black.opacity(0.28) : ArcadePalette.purple.opacity(0.10),
                    radius: isPressed ? 1 : 4,
                    y: isPressed ? 1 : 3
                )

            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: isBlack ? 9 : 10, weight: .black, design: .rounded))
                Text("\(midi)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .opacity(0.62)
            }
            .foregroundStyle(isBlack ? .white : ArcadePalette.ink)
            .padding(.bottom, isBlack ? 8 : 10)
        }
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onNoteOn(midi)
                }
                .onEnded { _ in
                    guard isPressed else { return }
                    isPressed = false
                    onNoteOff(midi)
                }
        )
        .onDisappear {
            if isPressed {
                isPressed = false
                onNoteOff(midi)
            }
        }
    }
}
