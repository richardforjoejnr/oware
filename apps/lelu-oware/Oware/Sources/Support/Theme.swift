import SwiftUI

/// Palette and type for the quiet, low-key look (see GAME_PLAN §3.2b). Kente meanings are
/// reserved for accents: gold for value, red for danger, green for growth.
enum Theme {
    static let night = Color(red: 0.06, green: 0.04, blue: 0.03)
    static let ember = Color(red: 0.16, green: 0.09, blue: 0.05)
    static let wood = Color(red: 0.23, green: 0.14, blue: 0.09)
    static let woodDark = Color(red: 0.12, green: 0.07, blue: 0.04)
    static let ivory = Color(red: 0.92, green: 0.85, blue: 0.72)
    static let ivoryDim = Color(red: 0.92, green: 0.85, blue: 0.72).opacity(0.55)
    static let gold = Color(red: 0.85, green: 0.65, blue: 0.13)
    static let goldLight = Color(red: 0.96, green: 0.82, blue: 0.42)
    static let amber = Color(red: 0.70, green: 0.48, blue: 0.10)
    static let emberLight = Color(red: 0.24, green: 0.15, blue: 0.09)
    static let kenteRed = Color(red: 0.70, green: 0.15, blue: 0.12)
    static let kenteGreen = Color(red: 0.12, green: 0.44, blue: 0.29)
    static let kenteGreenDeep = Color(red: 0.07, green: 0.30, blue: 0.19)

    static func title(_ size: CGFloat = 44) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static func body(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .regular, design: .serif) }
    static func caption(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

/// A quiet, text-first button in the house style.
struct QuietButton: View {
    let title: String
    var subtitle: String? = nil
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.body(22))
                    .foregroundStyle(prominent ? Theme.gold : Theme.ivory)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.ivoryDim)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


extension View {
    /// Floating control chrome: Liquid Glass on iOS 26 and later, a thin material before that.
    @ViewBuilder
    func hudChrome<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
