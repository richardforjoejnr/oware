import LudoEngine
import SwiftUI

/// The dice cup and the die (the owner's art): tap the cup to shake it and roll. The die shows the
/// last roll on its top face (gold pips), on a bar in the colour of whoever rolled; before the first roll it shows the flag.
struct DiceView: View {
    @Environment(LudoSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @Environment(DieFlight.self) private var flight
    @State private var shakes = 0
    /// The roll shown here: it changes once the die thrown on the board has landed.
    @State private var shown: Int?

    var body: some View {
        let value = shown
        Button {
            shakes += 1
            Task { await session.roll() }
        } label: {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(spacing: 4) {
                    Image(value.map(Art.die) ?? Art.dieFlag)
                        .resizable().scaledToFit()
                        .frame(width: 70, height: 70)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                        .id(value.map { "\($0)-\(shakes)" } ?? "flag")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    Capsule().fill(session.lastRoll.map { Palette.color($0.color) } ?? .clear)
                        .overlay(Capsule().stroke(Palette.brass, lineWidth: session.lastRoll?.color == .black ? 1 : 0))
                        .frame(width: 40, height: 5)
                }
                VStack(spacing: 2) {
                Image(Art.diceCup)
                    .resizable().scaledToFit()
                    .frame(height: 92)
                    .rotationEffect(.degrees(shakes % 2 == 0 ? 0 : 0.001))
                    .keyframeAnimator(initialValue: 0.0, trigger: settings.diceThrow(reduceMotion: reduceMotion) == .off ? 0 : shakes) { cup, angle in
                        cup.rotationEffect(.degrees(angle), anchor: .bottom)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(-12, duration: 0.08)
                            CubicKeyframe(12, duration: 0.12)
                            CubicKeyframe(-8, duration: 0.1)
                            CubicKeyframe(0, duration: 0.1)
                        }
                    }
                    // Glows when it is your roll.
                    .shadow(color: session.canRoll ? Palette.brass.opacity(0.9) : .clear, radius: 10)
                    Text(session.canRoll ? "Tap to roll" : " ")
                        .font(.system(.caption2, design: .serif).weight(.semibold))
                        .foregroundStyle(Palette.ivory)
                }
            }
            .frame(minHeight: 100)
            .animation(.spring(duration: 0.35), value: value)
        }
        .buttonStyle(.plain)
        .onAppear { shown = session.lastRoll?.value }
        // With the throw shown on the board, the result comes here when that die lands (or is skipped).
        .onChange(of: session.rolls) { if !RollingDie.shown { shown = session.lastRoll?.value } }
        .onChange(of: flight.landed) { shown = session.lastRoll?.value }
        .onChange(of: session.lastRoll == nil) { _, none in if none { shown = nil } }
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
