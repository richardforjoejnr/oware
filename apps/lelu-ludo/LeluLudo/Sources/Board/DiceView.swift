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
        // Spoken as a number: the star on the 6 is Lelu's branding, not a different result.
        .accessibilityLabel(value.map { "Die showing \(Pips.spoken($0))" } ?? "Die")
        .accessibilityHint(session.canRoll ? "Double tap to roll" : "")
        .accessibilityIdentifier("btn-roll")
    }
}

/// Pips for 1…5; the 6 is the Ghana black star (owner, 2026-10-03). It is simply a 6: it brings a
/// token out, moves six and rolls again.
struct Pips: View {
    let value: Int

    static func spoken(_ value: Int) -> String {
        ["one", "two", "three", "four", "five", "six"][max(1, min(6, value)) - 1]
    }

    var body: some View {
        if value == 6 {
            Image(systemName: "star.fill")
                .font(.system(size: 36))
                .foregroundStyle(.black)
                .accessibilityHidden(true)
        } else {
            let spots: [Int: [(CGFloat, CGFloat)]] = [
                1: [(0, 0)], 2: [(-1, -1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)],
                4: [(-1, -1), (1, -1), (-1, 1), (1, 1)], 5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
            ]
            ZStack {
                ForEach(Array((spots[value] ?? []).enumerated()), id: \.offset) { _, s in
                    Circle().fill(.black).frame(width: 11, height: 11).offset(x: s.0 * 18, y: s.1 * 18)
                }
            }
        }
    }
}
