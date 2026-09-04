import SwiftUI
import SpriteKit
import UIKit

struct ContentView: View {
    @State private var selectedHero: HeroClass?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let hero = selectedHero {
                MatchView(heroClass: hero) {
                    selectedHero = nil
                }
                .id(hero.id)
            } else {
                HeroSelectView { hero in
                    selectedHero = hero
                }
            }
        }
        .ignoresSafeArea()
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
                                .contentShape(Rectangle())
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
        .ignoresSafeArea()
    }
}

private final class SceneHolder: ObservableObject {
    let scene: GameScene

    init(heroClass: HeroClass) {
        let scene = GameScene(size: CGSize(width: 932, height: 430), heroClass: heroClass)
        scene.scaleMode = .resizeFill
        self.scene = scene
    }
}

private struct GameSKView: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.shouldCullNonVisibleNodes = true
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
    }

    static func dismantleUIView(_ uiView: SKView, coordinator: ()) {
        uiView.presentScene(nil)
    }
}

private struct MatchView: View {
    let heroClass: HeroClass
    let onExit: () -> Void
    @StateObject private var holder: SceneHolder

    init(heroClass: HeroClass, onExit: @escaping () -> Void) {
        self.heroClass = heroClass
        self.onExit = onExit
        _holder = StateObject(wrappedValue: SceneHolder(heroClass: heroClass))
    }

    var body: some View {
        ZStack {
            GameSKView(scene: holder.scene)
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
                        holder.scene.restartMatch()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.bold())
                            .padding(8)
                            .background(.black.opacity(0.52), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 62)
                .padding(.top, 10)

                Spacer()

                HStack(alignment: .bottom, spacing: 12) {
                    Joystick { vector in
                        holder.scene.setMovement(vector)
                    }

                    Spacer(minLength: 20)

                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(Array(heroClass.skills.enumerated()), id: \.offset) { index, skill in
                            SkillButton(
                                title: skill.name,
                                index: index + 1,
                                isUltimate: index == 3
                            ) {
                                holder.scene.castSkill(index)
                            }
                        }

                        Button {
                            holder.scene.basicAttack()
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
                .padding(.horizontal, 64)
                .padding(.bottom, 13)
            }
        }
        .ignoresSafeArea()
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
