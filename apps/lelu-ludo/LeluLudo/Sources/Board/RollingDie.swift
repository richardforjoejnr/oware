import SwiftUI

/// The roll seen on the board: a die thrown from the tray's cup tumbles across the board and comes to
/// rest showing the roll, then lifts away; the result stays on the die in the tray. Only for show (the
/// roll is already made); left out under Reduce Motion and in tests.
struct RollingDie: View {
    let value: Int
    /// Where it lands, 0…1 across and down the board (varies roll to roll).
    let landing: CGPoint

    struct Pose {
        var x: CGFloat = 1.05, y: CGFloat = 1.15   // from the cup, below the board's right corner
        var spin: Double = 0
        var scale: CGFloat = 0.7
        var opacity: Double = 1
    }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            KeyframeAnimator(initialValue: Pose(), repeating: false) { pose in
                // While it spins it shows a new face each quarter turn, then settles on the roll.
                let face = pose.spin >= 720 ? value : (Int(pose.spin / 90) + value) % 6 + 1
                Image(Art.die(face))
                    .resizable().scaledToFit()
                    .frame(width: side * 0.13)
                    .rotationEffect(.degrees(pose.spin))
                    .shadow(color: .black.opacity(0.45), radius: 6, x: 3, y: 6)
                    .scaleEffect(pose.scale)
                    .opacity(pose.opacity)
                    .position(x: pose.x * side, y: pose.y * side)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(landing.x * 0.9 + 0.1, duration: 0.45)
                    SpringKeyframe(landing.x, duration: 0.25)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(landing.y - 0.05, duration: 0.3)
                    CubicKeyframe(landing.y + 0.03, duration: 0.15)   // a bounce
                    SpringKeyframe(landing.y, duration: 0.25)
                }
                KeyframeTrack(\.spin) {
                    CubicKeyframe(600, duration: 0.5)
                    SpringKeyframe(720, duration: 0.2)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.25, duration: 0.2)   // in the air
                    CubicKeyframe(1, duration: 0.3)
                    LinearKeyframe(1, duration: 0.75)
                    CubicKeyframe(0.6, duration: 0.25)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 1.25)
                    LinearKeyframe(0, duration: 0.25)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Whether rolls are shown on the board: not under Reduce Motion, and not in tests.
    static func shown(reduceMotion: Bool) -> Bool { !reduceMotion && !LaunchOptions.testMode }

    /// How long the die is in the air before the tray shows the result.
    static let flight: Duration = .milliseconds(700)

    /// A landing spot for a roll: somewhere on the middle of the board, different each time.
    static func landing(for roll: Int) -> CGPoint {
        var rng = SplitMix(seed: UInt64(roll) &* 0x9E37_79B9)
        return CGPoint(x: 0.3 + 0.4 * rng.unit(), y: 0.3 + 0.4 * rng.unit())
    }
}

/// A tiny seeded generator, so a roll's landing spot is the same however often the view redraws.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return CGFloat((z ^ (z >> 31)) >> 11) / CGFloat(1 << 53)
    }
}
