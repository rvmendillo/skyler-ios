import SwiftUI

struct CollectionView: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(game.collection) { creature in
                        Button {
                            game.setActive(creature)
                        } label: {
                            VStack(spacing: 8) {
                                CreatureView(creature: creature, size: 86)
                                Text(creature.displayName).font(.headline).foregroundStyle(.white)
                                HStack {
                                    Label("Lv.\(creature.level)", systemImage: creature.species.element.icon)
                                    Spacer()
                                    Text("PWR \(creature.power)")
                                }
                                .font(.caption).foregroundStyle(.white.opacity(0.75))
                                Text(creature.species.description)
                                    .font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(creature.species.element.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(creature.id == game.activeCreature.id ? .white : creature.species.element.tint.opacity(0.45), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("Creature Codex")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { game.screen = .world }
                }
            }
        }
    }
}
