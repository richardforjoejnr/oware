import LudoEngine
import SwiftUI

/// The die: shows the last roll in the colour of whoever rolled; tap to roll on your turn.
struct DiceView: View {
    @Environment(LudoSession.self) private var session
    @State private var tumble = false

    var body: some View {
        let value = session.lastRoll?.value
        Button {
            tumble.toggle()
            Task { await session.roll() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Palette.cream)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(session.lastRoll.map { Palette.color($0.color) } ?? Palette.line, lineWidth: 3))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                if let value { Pips(value: value) } else { Text("Roll").font(.headline).foregroundStyle(Palette.line) }
            }
            .frame(width: 72, height: 72)
            .rotationEffect(.degrees(tumble ? 360 : 0))
            .animation(.spring(duration: 0.45), value: tumble)
        }
        .buttonStyle(.plain)
        .disabled(!session.canRoll)
        .opacity(session.canRoll || session.isComputerPlaying || value != nil ? 1 : 0.5)
        .accessibilityLabel(value.map { "Die showing \($0)" } ?? "Die")
        .accessibilityHint(session.canRoll ? "Double tap to roll" : "")
        .accessibilityIdentifier("btn-roll")
    }
}

/// Pips for 1…6. (The owner's art proposes the black star for the 6; until that is confirmed the 6
/// keeps its pips.)
struct Pips: View {
    let value: Int

    var body: some View {
        let spots: [Int: [(CGFloat, CGFloat)]] = [
            1: [(0, 0)], 2: [(-1, -1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)],
            4: [(-1, -1), (1, -1), (-1, 1), (1, 1)], 5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
            6: [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)],
        ]
        ZStack {
            ForEach(Array((spots[value] ?? []).enumerated()), id: \.offset) { _, s in
                Circle().fill(.black).frame(width: 11, height: 11).offset(x: s.0 * 18, y: s.1 * 18)
            }
        }
    }
}
