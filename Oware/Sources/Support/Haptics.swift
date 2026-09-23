import UIKit

/// Thin wrapper over UIKit feedback generators. Prepared once, cheap to call per seed.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()

    var enabled = true

    private init() {
        light.prepare()
        medium.prepare()
    }

    func seedDrop() { guard enabled else { return }; light.impactOccurred(intensity: 0.6) }
    func pickUp() { guard enabled else { return }; rigid.impactOccurred(intensity: 0.5) }
    func capture() { guard enabled else { return }; medium.impactOccurred(intensity: 1.0) }
    func gameOver(won: Bool?) {
        guard enabled else { return }
        switch won {
        case true: notify.notificationOccurred(.success)
        case false: notify.notificationOccurred(.warning)
        default: notify.notificationOccurred(.success)
        }
    }
}
