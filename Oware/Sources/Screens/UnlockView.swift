import SwiftUI

/// The one calm purchase screen. No timers, no pressure.
struct UnlockView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("The full Journey")
                .font(Theme.title(32))
                .foregroundStyle(Theme.ivory)
                .accessibilityIdentifier("unlock-title")
            Text("Lake Bosomtwe, Techiman, Cape Coast, Makola, Ho and Tamale: six more places, eighteen more players, up to the champion. Plus every board and seed set as they arrive.")
                .font(Theme.body(17))
                .foregroundStyle(Theme.ivory.opacity(0.88))
                .lineSpacing(4)
            Text("Everything else in Lelu Oware stays free.")
                .font(Theme.caption())
                .foregroundStyle(Theme.ivoryDim)

            Spacer(minLength: 8)

            if store.hasFullJourney {
                Text("Medaase — the Journey is yours.")
                    .font(Theme.body(20))
                    .foregroundStyle(Theme.gold)
                    .accessibilityIdentifier("unlock-owned")
                QuietButton(title: "Continue", prominent: true) { dismiss() }
                    .accessibilityIdentifier("btn-unlock-done")
            } else {
                QuietButton(title: busy ? "…" : "Unlock for \(store.priceText)", prominent: true) {
                    busy = true
                    Task {
                        await store.purchase()
                        busy = false
                        if store.hasFullJourney { dismiss() }
                    }
                }
                .disabled(busy || store.product == nil)
                .accessibilityIdentifier("btn-purchase")
                QuietButton(title: "Restore purchase") {
                    busy = true
                    Task {
                        await store.restore()
                        busy = false
                    }
                }
                .disabled(busy)
                .accessibilityIdentifier("btn-restore")
                QuietButton(title: "Not now") { dismiss() }
                    .accessibilityIdentifier("btn-unlock-later")
            }
            if let error = store.lastError {
                Text(error)
                    .font(Theme.caption())
                    .foregroundStyle(Theme.kenteRed)
                    .accessibilityIdentifier("unlock-error")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
