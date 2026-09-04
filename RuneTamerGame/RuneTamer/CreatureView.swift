import SwiftUI

struct CreatureView: View {
    let creature: Creature
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .fill(creature.species.element.tint.opacity(0.18))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(creature.species.element.tint.opacity(0.7), lineWidth: max(2, size * 0.035)))

            creatureBody
        }
        .shadow(color: creature.species.element.tint.opacity(0.38), radius: 12)
        .accessibilityLabel(creature.species.name)
    }

    @ViewBuilder
    private var creatureBody: some View {
        let s = size
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [creature.species.element.tint, creature.species.element.tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.52, height: s * 0.43)
                .offset(y: s * 0.08)
            Circle()
                .fill(creature.species.element.tint)
                .frame(width: s * 0.43, height: s * 0.38)
                .offset(y: -s * 0.12)
            Circle().fill(.white).frame(width: s * 0.10, height: s * 0.10).offset(x: -s * 0.09, y: -s * 0.12)
            Circle().fill(.white).frame(width: s * 0.10, height: s * 0.10).offset(x: s * 0.09, y: -s * 0.12)
            Circle().fill(.black).frame(width: s * 0.045, height: s * 0.045).offset(x: -s * 0.09, y: -s * 0.12)
            Circle().fill(.black).frame(width: s * 0.045, height: s * 0.045).offset(x: s * 0.09, y: -s * 0.12)
            Image(systemName: creature.species.element.icon)
                .font(.system(size: s * 0.20, weight: .black))
                .foregroundStyle(.white.opacity(0.92))
                .offset(y: s * 0.13)
        }
    }
}
