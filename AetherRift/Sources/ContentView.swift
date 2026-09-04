import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var activeClass: HeroClass?
    @State private var activeScene: GameScene?

    var body: some View {
        Group {
            if let hero = activeClass, let scene = activeScene {
                MatchView(heroClass: hero, scene: scene) {
                    activeScene = nil
                    activeClass = nil
                }
            } else {
                HeroSelectView { hero in
                    let scene = GameScene(size: CGSize(width: 1280, height: 720), heroClass: hero)
                    scene.scaleMode = .aspectFill
                    activeClass = hero
                    activeScene = scene
                }
            }
        }
        .background(Color.black)
    }
}

private struct HeroSelectView: View {
    let onSelect: (HeroClass) -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.05, blue: 0.10), Color(red: 0.08, green: 0.13, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("AETHER RIFT")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(3)
                    Text("Choose a battle class")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    ForEach(HeroClass.allCases) { hero in
                        Button {
                            onSelect(hero)
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: hero.icon)
                                    .font(.system(size: 28, weight: .bold))
                                    .frame(width: 58, height: 58)
                                    .background(.white.opacity(0.10), in: Circle())

                                Text(hero.rawValue)
                                    .font(.headline)

                                Text(hero.tagline)
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 125, height: 34)

                                Text(hero.skills.map(\.name).joined(separator: " • "))
                                    .font(.system(size: 9, weight: .medium))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.65))
                                    .frame(width: 130, height: 40)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 8)
                            .frame(maxHeight: 210)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Original MOBA prototype • procedural visuals • offline 1v1 battle simulation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

private struct MatchView: View {
    let heroClass: HeroClass
    let scene: GameScene
    let onExit: () -> Void

    var body: some View {
        ZStack {
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onExit) {
                        Label("Heroes", systemImage: "chevron.left")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.48), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(heroClass.rawValue.uppercased())
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.48), in: Capsule())

                    Spacer()

                    Button {
                        scene.restartMatch()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .padding(9)
                            .background(.black.opacity(0.48), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer()

                HStack(alignment: .bottom) {
                    Joystick { vector in
                        scene.setMovement(vector)
                    }

                    Spacer()

                    HStack(alignment: .bottom, spacing: 9) {
                        ForEach(Array(heroClass.skills.enumerated()), id: \.offset) { index, skill in
                            SkillButton(
                                title: skill.name,
                                index: index + 1,
                                isUltimate: index == 3
                            ) {
                                scene.castSkill(index)
                            }
                        }

                        Button {
                            scene.basicAttack()
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "burst.fill")
                                    .font(.title2.bold())
                                Text("ATTACK")
                                    .font(.system(size: 8, weight: .black))
                            }
                            .frame(width: 76, height: 76)
                            .background(.white.opacity(0.20), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }
}

private struct SkillButton: View {
    let title: String
    let index: Int
    let isUltimate: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("S\(index)")
                    .font(.caption2.black())
                Text(title)
                    .font(.system(size: 7, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: isUltimate ? 68 : 58, height: isUltimate ? 68 : 58)
            .background(.black.opacity(0.52), in: Circle())
            .overlay(Circle().stroke(.white.opacity(isUltimate ? 0.62 : 0.28), lineWidth: isUltimate ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct Joystick: View {
    let onChange: (CGVector) -> Void
    @State private var knob = CGSize.zero

    private let radius: CGFloat = 58

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.32))
                .frame(width: radius * 2, height: radius * 2)
                .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 2))

            Circle()
                .fill(.white.opacity(0.28))
                .frame(width: 52, height: 52)
                .offset(knob)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let length = max(1, sqrt(dx * dx + dy * dy))
                    let scale = min(1, radius / length)
                    knob = CGSize(width: dx * scale, height: dy * scale)
                    onChange(CGVector(dx: knob.width / radius, dy: -knob.height / radius))
                }
                .onEnded { _ in
                    knob = .zero
                    onChange(.zero)
                }
        )
    }
}
