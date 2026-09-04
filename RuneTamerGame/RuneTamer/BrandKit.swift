import SwiftUI

struct RuneTamerBrandMark: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 7 : 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.30, green: 0.86, blue: 0.92), Color(red: 0.50, green: 0.34, blue: 0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(45))
                    .frame(width: compact ? 23 : 34, height: compact ? 23 : 34)
                    .shadow(color: .cyan.opacity(0.35), radius: 9)

                Image(systemName: "sparkles")
                    .font(compact ? .caption.bold() : .headline.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: compact ? -1 : 0) {
                Text("RUNE TAMER")
                    .font(compact ? .caption.bold() : .title3.bold())
                    .tracking(compact ? 1.2 : 2.1)
                    .foregroundStyle(.white)

                Text("AETHERWILD")
                    .font(.system(size: compact ? 7 : 9, weight: .semibold, design: .rounded))
                    .tracking(2.6)
                    .foregroundStyle(Color.cyan.opacity(0.9))
            }
        }
    }
}

struct RuneTamerSplash: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.08, blue: 0.13),
                    Color(red: 0.08, green: 0.12, blue: 0.24),
                    Color(red: 0.10, green: 0.08, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.cyan.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 30)

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .indigo, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(45))
                        .shadow(color: .cyan.opacity(0.5), radius: 30)

                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("RUNE TAMER")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(.white)

                    Text("AETHERWILD")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(.cyan)

                    Text("BOND WITH THE WILD. AWAKEN THE RUNES.")
                        .font(.caption2.bold())
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.top, 4)
                }
            }
        }
    }
}
