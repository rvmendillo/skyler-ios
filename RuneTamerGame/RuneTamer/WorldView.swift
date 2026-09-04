import SwiftUI

struct WorldView: View {
    @EnvironmentObject var game: GameState
    @StateObject private var world = RuneWorld3DController()

    var body: some View {
        ZStack {
            RuneWorld3DView(controller: world)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.28), .clear, .clear, .black.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topHUD
                Spacer()
                bottomHUD
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .onAppear { world.connect(game: game) }
        .sheet(item: $game.encounter) { _ in
            BattleView()
                .environmentObject(game)
                .interactiveDismissDisabled()
        }
    }

    private var topHUD: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                RuneTamerBrandMark(compact: true)

                HStack(spacing: 9) {
                    CreatureView(creature: game.activeCreature, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Aether Tamer · Lv.\(game.playerLevel)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        ProgressView(value: Double(game.playerHP), total: 100)
                            .tint(.green)
                            .frame(width: 142)
                        Text("HP \(game.playerHP)/100  ·  EXP \(game.exp)/\(game.playerLevel * 100)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(9)
                .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.12)))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 9) {
                HStack(spacing: 8) {
                    Label("\(game.coins)", systemImage: "hexagon.fill")
                    Label("\(game.potions)", systemImage: "cross.vial.fill")
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.black.opacity(0.34), in: Capsule())

                Text(world.locationName)
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.28), in: Capsule())

                Text("DRAG WORLD TO ORBIT · PINCH TO ZOOM")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var bottomHUD: some View {
        HStack(alignment: .bottom) {
            AnalogJoystick { strafe, forward in
                world.setMove(strafe: strafe, forward: forward)
            } onEnded: {
                world.stopMoving()
            }

            Spacer()

            HStack(alignment: .bottom, spacing: 11) {
                VStack(spacing: 10) {
                    RoundActionButton(icon: "pawprint.fill", label: "CREATURES", size: 48) {
                        game.screen = .collection
                    }
                    RoundActionButton(icon: "scroll.fill", label: "QUESTS", size: 48) {
                        game.screen = .quests
                    }
                }

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        RoundActionButton(icon: "figure.run", label: "DASH", size: 54) {
                            world.dash()
                        }
                        RoundActionButton(icon: "arrow.up.circle.fill", label: "JUMP", size: 54) {
                            world.jump()
                        }
                    }

                    Button {
                        world.primaryAction()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan.opacity(0.95), Color.indigo.opacity(0.95)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 78, height: 78)
                                .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 2))
                                .shadow(color: .cyan.opacity(0.32), radius: 12)

                            Image(systemName: "sparkles")
                                .font(.system(size: 29, weight: .black))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Text("RUNE STRIKE")
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                            .offset(y: 15)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
}

private struct AnalogJoystick: View {
    let onChanged: (Float, Float) -> Void
    let onEnded: () -> Void
    @State private var knobOffset: CGSize = .zero

    private let radius: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.27))
                .frame(width: radius * 2.2, height: radius * 2.2)
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1.5))

            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 58, height: 58)
                .overlay(Circle().stroke(.white.opacity(0.34), lineWidth: 1.5))
                .offset(knobOffset)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let length = max(0.001, hypot(dx, dy))
                    let scale = min(1, radius / length)
                    let clampedX = dx * scale
                    let clampedY = dy * scale
                    knobOffset = CGSize(width: clampedX, height: clampedY)
                    onChanged(Float(clampedX / radius), Float(-clampedY / radius))
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                        knobOffset = .zero
                    }
                    onEnded()
                }
        )
        .accessibilityLabel("Movement joystick")
    }
}

private struct RoundActionButton: View {
    let icon: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.34))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1.5))
                    .background(.ultraThinMaterial.opacity(0.35), in: Circle())

                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Text(label)
                .font(.system(size: 7, weight: .black))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.86))
                .offset(y: 12)
        }
    }
}
