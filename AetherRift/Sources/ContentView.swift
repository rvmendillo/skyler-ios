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
                    // iPhone 16 Plus landscape logical viewport is treated as a 932×430 play window.
                    // The actual battlefield is much larger and is explored with a follow camera.
                    let scene = GameScene(size: CGSize(width: 932, height: 430), heroClass: hero)
                    scene.scaleMode = .aspectFill
                    activeClass = hero
                    activeScene = scene
                }
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
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

            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("AETHER RIFT")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .tracking(3)
                    Text("3-Lane 5v5 Arena • Choose a battle class")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(HeroClass.allCases) { hero in
                            Button {
                                onSelect(hero)
                            } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: hero.icon)
                                        .font(.system(size: 23, weight: .bold))
                                        .frame(width: 48, height: 48)
                                        .background(.white.opacity(0.10), in: Circle())

                                    Text(hero.rawValue)
                                        .font(.subheadline.bold())

                                    Text(hero.tagline)
                                        .font(.system(size: 9))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 116, height: 28)

                                    Text(hero.skills.map(\.name).joined(separator: " • "))
                                        .font(.system(size: 7.5, weight: .medium))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.white.opacity(0.68))
                                        .frame(width: 120, height: 30)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                                .frame(width: 138, height: 172)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 28)
                }

                Text("Original MOBA map and heroes • optimized for iPhone 16 Plus landscape")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        }
    }
}

private struct MatchView: View {
    let heroClass: HeroClass
    let scene: GameScene
    let onExit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene: scene, preferredFramesPerSecond: 60)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button(action: onExit) {
                            Label("Heroes", systemImage: "chevron.left")
                                .font(.caption.bold())
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.52), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(heroClass.rawValue.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.48), in: Capsule())

                        Spacer()

                        Button {
                            scene.restartMatch()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.bold())
                                .padding(8)
                                .background(.black.opacity(0.52), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, max(18, geometry.safeAreaInsets.leading + 8))
                    .padding(.trailing, max(18, geometry.safeAreaInsets.trailing + 8))
                    .padding(.top, max(5, geometry.safeAreaInsets.top + 2))

                    Spacer()

                    HStack(alignment: .bottom, spacing: 12) {
                        Joystick { vector in
                            scene.setMovement(vector)
                        }

                        Spacer(minLength: 24)

                        HStack(alignment: .bottom, spacing: 7) {
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
                                VStack(spacing: 2) {
                                    Image(systemName: "burst.fill")
                                        .font(.title3.bold())
                                    Text("ATTACK")
                                        .font(.system(size: 7.5, weight: .black))
                                }
                                .frame(width: 72, height: 72)
                                .background(.white.opacity(0.20), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.48), lineWidth: 2))
                                .shadow(radius: 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, max(20, geometry.safeAreaInsets.leading + 10))
                    .padding(.trailing, max(20, geometry.safeAreaInsets.trailing + 10))
                    .padding(.bottom, max(10, geometry.safeAreaInsets.bottom + 6))
                }
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
            VStack(spacing: 2) {
                Text("S\(index)")
                    .font(.system(size: 9, weight: .black))
                Text(title)
                    .font(.system(size: 6.5, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: isUltimate ? 64 : 54, height: isUltimate ? 64 : 54)
            .background(.black.opacity(0.56), in: Circle())
            .overlay(Circle().stroke(.white.opacity(isUltimate ? 0.68 : 0.30), lineWidth: isUltimate ? 2 : 1))
            .shadow(radius: isUltimate ? 5 : 2)
        }
        .buttonStyle(.plain)
    }
}

private struct Joystick: View {
    let onChange: (CGVector) -> Void
    @State private var knob = CGSize.zero

    private let radius: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.36))
                .frame(width: radius * 2, height: radius * 2)
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 2))

            Circle()
                .fill(.white.opacity(0.30))
                .frame(width: 50, height: 50)
                .offset(knob)
                .shadow(radius: 3)
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