import SwiftUI

/// How the dice are thrown (Settings ▸ Sound and touch): the full throw, a quick one, or off (the die
/// just fades in on the board showing the roll, with no movement).
enum DiceAnimation: String, CaseIterable, Sendable {
    case full, quick, off
    var title: String {
        switch self {
        case .full: "Full"
        case .quick: "Quick"
        case .off: "Off"
        }
    }
}

/// When things happen in a throw, in seconds from the tap. Plain data, so it is tested without a screen.
/// The full throw is for your own rolls; computers' rolls always use the quick one, so their turns
/// don't drag (a four-player game has about 150 rolls).
struct ThrowTiming: Equatable {
    /// 1 for the full throw; the quick one runs the same moves faster.
    let speed: Double

    static let full = ThrowTiming(speed: 1)
    static let quick = ThrowTiming(speed: 0.5)
    /// Throw off: no flight; the die fades in where it lands and fades away.
    static let still = ThrowTiming(speed: 0)
    static func of(_ style: DiceAnimation) -> ThrowTiming {
        switch style {
        case .full: .full
        case .quick: .quick
        case .off: .still
        }
    }
    var isStill: Bool { speed == 0 }

    /// The cup's shake, the flight in an arc, two bounces: then the die rests showing the roll.
    var landsAfter: Double { 1.05 * speed }
    /// It rests, glowing, before going back to the tray.
    var rest: Double { isStill ? 0.9 : 0.45 * speed }
    var returnTrip: Double { isStill ? 0.3 : 0.35 * speed }
    var total: Double { landsAfter + rest + returnTrip }
    var landing: Duration { .milliseconds(Int(landsAfter * 1000)) }
    /// The whole throw, back in the cup, and a breath: what a move waits for.
    var whole: Duration { .milliseconds(Int(total * 1000) + 100) }
}

/// Which throws have landed, shared by the board (the flying die), the tray's die and the status: the
/// tray shows the roll and the status says it once the die has landed, or once the player tapped to skip.
@MainActor
@Observable
final class DieFlight {
    /// The count (`LudoSession.rolls`) of the last roll whose die has landed or been skipped.
    private(set) var landed = 0
    /// The last roll the player tapped through: its die is taken off the board at once.
    private(set) var skipped = 0
    /// The last roll whose die is back by the cup: until then the tray's die is hidden, as it is the
    /// one being thrown (one die on screen, never two).
    private(set) var back = 0
    func land(_ roll: Int) { landed = max(landed, roll) }
    func returned(_ roll: Int) { back = max(back, roll); land(roll) }
    func skip(_ roll: Int) { skipped = max(skipped, roll); returned(roll) }
    /// A game screen opening (a new game, Continue, a lesson): every roll so far is done with. The
    /// session counts rolls for as long as the app runs, while each game screen starts its own
    /// DieFlight, so without this an earlier roll looked like a die still out, and the cup stayed
    /// disabled for good (owner's bug, 2026-10-05).
    func settle(at rolls: Int) { returned(rolls); skipped = max(skipped, rolls) }

    /// Whether the tray's die is out being thrown.
    func thrown(_ roll: Int) -> Bool { roll > back }
    func inFlight(_ roll: Int) -> Bool { roll > landed }
}

/// The roll seen on the board, after the owner's storyboard: thrown out of the tray's cup, it flies onto
/// the board in an arc, tumbling, bounces twice and comes to rest showing the roll on its top face, in a glow; then it goes back to the tray. Only for show: the roll is already made. Tap to skip. Left
/// out under Reduce Motion and in tests.
struct RollingDie: View {
    let value: Int
    /// Where it lands, 0…1 across and down the board (varies roll to roll).
    let landing: CGPoint
    var timing: ThrowTiming = .full
    /// Called when it lands, or when the player taps to skip.
    var landed: () -> Void = {}
    /// Called when it is back in the cup.
    var returned: () -> Void = {}

    /// Starts the throw once on screen. (`KeyframeAnimator(repeating: false)` only holds the first
    /// frame; a trigger is what plays it once.)
    @State private var thrown = false

    /// The cup's mouth, in board units: below the board, at its right (the tray's cup).
    static let cup = CGPoint(x: 0.9, y: 1.12)

    struct Pose {
        var x: CGFloat = 0.9, y: CGFloat = 1.12   // the cup (RollingDie.cup)
        var spin: Double = 0
        var scale: CGFloat = 0.45
        /// Height above the board, 0…1: the shadow falls further away and softer the higher it is.
        var lift: CGFloat = 0
        var glow: Double = 0
        var opacity: Double = 1
    }

    /// The face up: a new one each quarter turn while it tumbles, the roll once it has settled.
    static func face(spin: Double, value: Int, settled: Double = 1080) -> Int {
        spin >= settled - 0.5 ? value : (Int(spin / 90) + value) % 6 + 1
    }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let k = timing.speed
            KeyframeAnimator(initialValue: Pose(), trigger: thrown) { pose in
                ZStack {
                    // The glow it lands in.
                    Circle()
                        .fill(RadialGradient(colors: [Palette.brassLight.opacity(0.75), .clear],
                                             center: .center, startRadius: 0, endRadius: side * 0.13))
                        .frame(width: side * 0.26, height: side * 0.26)
                        .opacity(pose.glow)
                    Image(Art.die(Self.face(spin: pose.spin, value: value)))
                        .resizable().scaledToFit()
                        .frame(width: side * 0.13)
                        .rotationEffect(.degrees(pose.spin))
                        .shadow(color: .black.opacity(0.5 - 0.25 * pose.lift), radius: 3 + 10 * pose.lift,
                                x: 3 + 14 * pose.lift, y: 5 + 22 * pose.lift)
                        .scaleEffect(pose.scale)
                }
                .opacity(pose.opacity)
                .position(x: pose.x * side, y: pose.y * side)
            } keyframes: { _ in
                // Out of the cup, up, and down onto the board; two bounces, smaller each time; rest; back.
                KeyframeTrack(\.x) {
                    CubicKeyframe(landing.x + 0.05, duration: 0.75 * k)
                    CubicKeyframe(landing.x + 0.015, duration: 0.18 * k)
                    CubicKeyframe(landing.x, duration: 0.12 * k)
                    LinearKeyframe(landing.x, duration: timing.rest)
                    CubicKeyframe(Self.cup.x, duration: timing.returnTrip)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(landing.y - 0.32, duration: 0.4 * k)     // the top of the arc
                    CubicKeyframe(landing.y, duration: 0.35 * k)            // down onto the board
                    CubicKeyframe(landing.y - 0.07, duration: 0.09 * k)     // first bounce
                    CubicKeyframe(landing.y, duration: 0.09 * k)
                    CubicKeyframe(landing.y - 0.02, duration: 0.06 * k)     // second, smaller
                    CubicKeyframe(landing.y, duration: 0.06 * k)
                    LinearKeyframe(landing.y, duration: timing.rest)
                    CubicKeyframe(Self.cup.y, duration: timing.returnTrip)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(1, duration: 0.4 * k)
                    CubicKeyframe(0, duration: 0.35 * k)
                    CubicKeyframe(0.25, duration: 0.09 * k)
                    CubicKeyframe(0, duration: 0.09 * k)
                    CubicKeyframe(0.08, duration: 0.06 * k)
                    CubicKeyframe(0, duration: 0.06 * k)
                    LinearKeyframe(0, duration: timing.rest)
                    CubicKeyframe(0.4, duration: timing.returnTrip)
                }
                KeyframeTrack(\.spin) {
                    CubicKeyframe(900, duration: 0.85 * k)                  // tumbling, slowing as it lands
                    SpringKeyframe(1080, duration: 0.2 * k)                 // settles square, the roll up
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.35, duration: 0.4 * k)                  // nearer the eye at the top
                    CubicKeyframe(1, duration: 0.35 * k)
                    CubicKeyframe(1.06, duration: 0.09 * k)
                    CubicKeyframe(1, duration: 0.21 * k)
                    LinearKeyframe(1, duration: timing.rest)
                    CubicKeyframe(0.45, duration: timing.returnTrip)
                }
                KeyframeTrack(\.glow) {
                    LinearKeyframe(0, duration: timing.landsAfter)
                    SpringKeyframe(1, duration: 0.2 * k)
                    LinearKeyframe(1, duration: max(0, timing.rest - 0.2 * k))
                    LinearKeyframe(0, duration: timing.returnTrip * 0.6)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: timing.landsAfter + timing.rest + timing.returnTrip * 0.6)
                    LinearKeyframe(0, duration: timing.returnTrip * 0.4)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: landed)   // tap to skip: the result at once
        .task {
            thrown = true
            try? await Task.sleep(for: timing.landing)
            landed()
            try? await Task.sleep(for: .milliseconds(Int((timing.total - timing.landsAfter) * 1000)))
            returned()
        }
        .accessibilityHidden(true)
    }

    /// Whether rolls are shown on the board at all (as a throw, or still when the throw is off): not in tests.
    static var shown: Bool { !LaunchOptions.testMode }

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
