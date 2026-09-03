import SwiftUI

enum ArcadePalette {
    static let ink = Color(red: 0.075, green: 0.09, blue: 0.16)
    static let panel = Color.white.opacity(0.94)
    static let cyan = Color(red: 0.19, green: 0.78, blue: 0.95)
    static let aqua = Color(red: 0.18, green: 0.91, blue: 0.78)
    static let pink = Color(red: 1.0, green: 0.43, blue: 0.72)
    static let purple = Color(red: 0.55, green: 0.37, blue: 0.94)
    static let yellow = Color(red: 1.0, green: 0.78, blue: 0.22)
    static let red = Color(red: 1.0, green: 0.34, blue: 0.37)
    static let lime = Color(red: 0.46, green: 0.83, blue: 0.30)

    static func difficulty(_ difficulty: ChartDifficulty) -> Color {
        switch difficulty {
        case .easy: return cyan
        case .basic: return lime
        case .advanced: return yellow
        case .expert: return red
        case .master: return purple
        case .remaster: return pink
        }
    }
}

struct ArcadeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.99, blue: 1.0),
                    Color(red: 1.0, green: 0.95, blue: 0.99),
                    Color(red: 0.95, green: 0.94, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                Circle()
                    .stroke(ArcadePalette.cyan.opacity(0.18), lineWidth: 22)
                    .frame(width: proxy.size.width * 0.95)
                    .offset(x: proxy.size.width * 0.35, y: -90)

                Circle()
                    .stroke(ArcadePalette.pink.opacity(0.15), lineWidth: 14)
                    .frame(width: proxy.size.width * 0.72)
                    .offset(x: -proxy.size.width * 0.28, y: proxy.size.height * 0.45)

                ForEach(0..<12, id: \.self) { index in
                    Circle()
                        .fill(index.isMultiple(of: 2) ? ArcadePalette.aqua.opacity(0.15) : ArcadePalette.purple.opacity(0.12))
                        .frame(width: CGFloat(8 + (index % 4) * 7))
                        .position(
                            x: CGFloat((index * 67) % max(1, Int(proxy.size.width))),
                            y: CGFloat((index * 113) % max(1, Int(proxy.size.height)))
                        )
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ArcadeCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(ArcadePalette.panel)
                    .shadow(color: ArcadePalette.purple.opacity(0.10), radius: 14, y: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
            )
    }
}

struct ArcadePrimaryButtonStyle: ButtonStyle {
    let colors: [Color]

    init(colors: [Color] = [ArcadePalette.purple, ArcadePalette.pink]) {
        self.colors = colors
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct DifficultyBadge: View {
    let difficulty: ChartDifficulty
    let selected: Bool

    var body: some View {
        Text(difficulty.name)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(selected ? .white : ArcadePalette.difficulty(difficulty))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(selected ? ArcadePalette.difficulty(difficulty) : Color.white.opacity(0.8))
            )
            .overlay(
                Capsule()
                    .stroke(ArcadePalette.difficulty(difficulty).opacity(0.55), lineWidth: 1.5)
            )
    }
}

struct RingLogo: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [ArcadePalette.cyan, ArcadePalette.aqua, ArcadePalette.pink, ArcadePalette.purple, ArcadePalette.cyan],
                        center: .center
                    ),
                    lineWidth: 5
                )
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .padding(8)
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [ArcadePalette.purple, ArcadePalette.pink], startPoint: .top, endPoint: .bottom)
                )
        }
        .frame(width: 64, height: 64)
        .padding(6)
        .background(.white.opacity(0.85), in: Circle())
        .shadow(color: ArcadePalette.cyan.opacity(0.25), radius: 12)
    }
}
