import SwiftUI

struct BattleView: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .indigo.opacity(0.7), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if let foe = game.encounter {
                VStack(spacing: 18) {
                    HStack {
                        Button("Run") { game.encounter = nil }
                            .buttonStyle(.bordered)
                        Spacer()
                        Label("Wild Encounter", systemImage: "sparkles").font(.headline)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 8) {
                        Text("Lv. \(foe.level) \(foe.species.name)").font(.title2.bold())
                        ProgressView(value: Double(foe.currentHP), total: Double(foe.maxHP)).tint(.red)
                        Text("\(foe.currentHP) / \(foe.maxHP) HP").font(.caption)
                    }.padding(.horizontal, 28)

                    CreatureView(creature: foe, size: 156)
                        .padding(.vertical, 6)

                    Text(game.battleMessage)
                        .font(.callout.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 42)
                        .padding(.horizontal)

                    HStack {
                        VStack {
                            Text(game.activeCreature.displayName).bold()
                            Text("Lv. \(game.activeCreature.level)").font(.caption)
                        }
                        Spacer()
                        CreatureView(creature: game.activeCreature, size: 70)
                    }
                    .padding(.horizontal, 24)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(game.skills) { skill in
                            Button {
                                game.useSkill(skill)
                            } label: {
                                HStack {
                                    Image(systemName: skill.icon)
                                    Text(skill.name).font(.subheadline.bold())
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button { game.tryCapture() } label: {
                            Label("Bond Rune", systemImage: "circle.hexagongrid.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.pink)

                        Button { game.heal() } label: {
                            Label("Potion \(game.potions)", systemImage: "cross.case.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    Spacer(minLength: 4)
                }
                .padding(.top, 18)
            }
        }
    }
}
