import SwiftUI

struct QuestView: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        NavigationStack {
            List {
                Section("Adventurer Board") {
                    ForEach(game.quests) { quest in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: quest.isClaimed ? "checkmark.seal.fill" : "scroll.fill")
                                Text(quest.title).font(.headline)
                                Spacer()
                                Text("+\(quest.reward)").foregroundStyle(.yellow)
                            }
                            Text(quest.detail).font(.subheadline).foregroundStyle(.secondary)
                            ProgressView(value: Double(quest.progress), total: Double(quest.target))
                            HStack {
                                Text("\(quest.progress)/\(quest.target)").font(.caption)
                                Spacer()
                                if quest.progress >= quest.target && !quest.isClaimed {
                                    Button("Claim") { game.claim(quest) }.buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("Runehaven") {
                    Label("Guild contracts and boss raids are the next expansion point.", systemImage: "person.3.fill")
                    Label("All current creatures and art are original procedural/vector designs.", systemImage: "checkmark.shield.fill")
                }
            }
            .navigationTitle("Quests")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Back") { game.screen = .world } } }
        }
    }
}
