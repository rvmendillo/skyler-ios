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
                    GameAudio.shared.play(.uiSelect)
                    selectedHero = nil
                }
                .id(hero.id)
            } else {
                HeroSelectView { hero in
                    GameAudio.shared.play(.uiSelect)
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
                colors: [
                    Color(red: 0.015, green: 0.05, blue: 0.10),
                    Color(red: 0.08, green: 0.18, blue: 0.28),
                    Color(red: 0.12, green: 0.16, blue: 0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            FrozenSkyOverlay()
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AETHER RIFT")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .tracking(3.5)
                        Text("CINEMATIC FANTASY ARENA")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(2.1)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("OFFLINE 5v5")
                            .font(.caption2.bold())
                        Text("LV 1–15 • 3 LANES • PET COMPANIONS")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
                .padding(.horizontal, 58)
                .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(HeroClass.allCases) { hero in
                            Button {
                                onSelect(hero)
                            } label: {
                                VStack(spacing: 6) {
                                    CinematicHeroPortrait(hero: hero)
                                        .frame(width: 142, height: 118)

                                    HStack(spacing: 5) {
                                        Image(systemName: hero.icon)
                                            .font(.system(size: 10, weight: .bold))
                                        Text(hero.rawValue.uppercased())
                                            .font(.system(size: 12, weight: .black, design: .rounded))
                                    }

                                    Text(hero.tagline)
                                        .font(.system(size: 8.5, weight: .medium))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.white.opacity(0.66))
                                        .frame(width: 136, height: 25)

                                    Text(hero.skills.map(\.name).joined(separator: " • "))
                                        .font(.system(size: 7, weight: .semibold))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.white.opacity(0.48))
                                        .frame(width: 138, height: 26)
                                }
                                .padding(8)
                                .frame(width: 160, height: 206)
                                .contentShape(Rectangle())
                                .background(
                                    .ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.white.opacity(0.30), CinematicFX.swiftUIColor(for: hero).opacity(0.48), .white.opacity(0.08)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 58)
                    .padding(.vertical, 2)
                }

                HStack(spacing: 18) {
                    Label("Transparent tactical minimap", systemImage: "map.fill")
                    Label("Turtle + Lord objectives", systemImage: "crown.fill")
                    Label("Original hero + pet designs", systemImage: "pawprint.fill")
                }
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
                .padding(.bottom, 6)
            }
        }
        .ignoresSafeArea()
    }
}

private struct FrozenSkyOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate

                for index in 0..<36 {
                    let seed = Double(index * 37 + 11)
                    let speed = 10.0 + Double(index % 7) * 3.2
                    let rawY = (seed * 19 + time * speed).truncatingRemainder(dividingBy: max(1, size.height + 40))
                    let y = size.height + 20 - rawY
                    let sway = sin(time * (0.45 + Double(index % 5) * 0.08) + seed) * 18
                    let x = (seed * 31).truncatingRemainder(dividingBy: max(1, size.width)) + sway
                    let radius = 0.9 + Double(index % 5) * 0.48
                    let rect = CGRect(x: x, y: y, width: radius * 2, height: radius * 2)
                    canvas.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.32 + Double(index % 3) * 0.10)))
                }

                let auroraRect = CGRect(x: size.width * 0.08, y: size.height * 0.03, width: size.width * 0.84, height: size.height * 0.26)
                canvas.fill(
                    Path(roundedRect: auroraRect, cornerRadius: auroraRect.height / 2),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.cyan.opacity(0.00),
                            Color.cyan.opacity(0.08),
                            Color.indigo.opacity(0.09),
                            Color.clear
                        ]),
                        startPoint: auroraRect.origin,
                        endPoint: CGPoint(x: auroraRect.maxX, y: auroraRect.maxY)
                    )
                )
            }
        }
        .opacity(0.92)
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
    let heroClass: HeroClass

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.shouldCullNonVisibleNodes = true
        view.presentScene(scene)

        GameAudio.shared.startBattleAmbience()
        DispatchQueue.main.async {
            CinematicFX.install(in: scene, selectedHero: heroClass)
        }
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
        CinematicFX.install(in: scene, selectedHero: heroClass)
    }

    static func dismantleUIView(_ uiView: SKView, coordinator: ()) {
        uiView.presentScene(nil)
        GameAudio.shared.stopBattleAmbience()
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
            GameSKView(scene: holder.scene, heroClass: heroClass)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Spacer()

                    Text(heroClass.rawValue.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))

                    Button {
                        GameAudio.shared.play(.purchase)
                        holder.scene.buyRecommendedItem()
                    } label: {
                        Label("BUY", systemImage: "cart.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        GameAudio.shared.play(.uiSelect)
                        holder.scene.restartMatch()
                        CinematicFX.install(in: holder.scene, selectedHero: heroClass)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.bold())
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: onExit) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline.bold())
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 250)
                .padding(.trailing, 62)
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
                                isUltimate: index == 3,
                                accent: CinematicFX.swiftUIColor(for: heroClass)
                            ) {
                                GameAudio.shared.play(index == 0 ? .skill1 : index == 1 ? .skill2 : index == 2 ? .skill3 : .ultimate)
                                holder.scene.castSkill(index)
                            }
                        }

                        Button {
                            GameAudio.shared.play(.attack)
                            holder.scene.basicAttack()
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "burst.fill")
                                    .font(.title3.bold())
                                Text("ATTACK")
                                    .font(.system(size: 7.5, weight: .black))
                            }
                            .frame(width: 72, height: 72)
                            .background(
                                RadialGradient(
                                    colors: [CinematicFX.swiftUIColor(for: heroClass).opacity(0.52), .black.opacity(0.62)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 42
                                ),
                                in: Circle()
                            )
                            .overlay(Circle().stroke(.white.opacity(0.58), lineWidth: 2))
                            .shadow(color: CinematicFX.swiftUIColor(for: heroClass).opacity(0.55), radius: 8)
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
    let accent: Color
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
            .background(
                RadialGradient(
                    colors: [accent.opacity(isUltimate ? 0.48 : 0.28), .black.opacity(0.66)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 36
                ),
                in: Circle()
            )
            .overlay(Circle().stroke(.white.opacity(isUltimate ? 0.74 : 0.34), lineWidth: isUltimate ? 2 : 1))
            .shadow(color: accent.opacity(isUltimate ? 0.60 : 0.25), radius: isUltimate ? 8 : 3)
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
                .fill(.ultraThinMaterial)
                .frame(width: radius * 2, height: radius * 2)
                .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 2))
                .shadow(color: .cyan.opacity(0.12), radius: 12)

            Circle()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.52), .cyan.opacity(0.16)], center: .center, startRadius: 0, endRadius: 30)
                )
                .frame(width: 50, height: 50)
                .offset(knob)
                .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                .shadow(radius: 4)
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
