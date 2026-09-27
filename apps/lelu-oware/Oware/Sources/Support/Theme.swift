import SwiftUI
import UIKit

/// Palette and type for the quiet, low-key look (see GAME_PLAN §3.2b). Kente meanings are
/// reserved for accents: gold for value, red for danger, green for growth.
enum Theme {
    static let night = Color(red: 0.06, green: 0.04, blue: 0.03)
    static let ember = Color(red: 0.16, green: 0.09, blue: 0.05)
    static let wood = Color(red: 0.23, green: 0.14, blue: 0.09)
    static let woodDark = Color(red: 0.12, green: 0.07, blue: 0.04)
    static let ivory = Color(red: 0.92, green: 0.85, blue: 0.72)
    /// Secondary text. 0.78 keeps at least 4.5:1 contrast on the dark screens and the wood tiles.
    static let ivoryDim = Color(red: 0.92, green: 0.85, blue: 0.72).opacity(0.78)
    /// Secondary text over photos and wood grain, where the lightest grain sets the contrast.
    static let onPhoto = Color(red: 0.92, green: 0.85, blue: 0.72).opacity(0.92)
    static let gold = Color(red: 0.85, green: 0.65, blue: 0.13)
    static let goldLight = Color(red: 0.96, green: 0.82, blue: 0.42)
    static let amber = Color(red: 0.70, green: 0.48, blue: 0.10)
    static let emberLight = Color(red: 0.24, green: 0.15, blue: 0.09)
    static let kenteRed = Color(red: 0.70, green: 0.15, blue: 0.12)
    static let kenteGreen = Color(red: 0.12, green: 0.44, blue: 0.29)
    static let kenteGreenDeep = Color(red: 0.07, green: 0.30, blue: 0.19)
    // Owner's brief (docs/DESIGN_PRINCIPLES.md): wood browns, bone text, brass and olive accents.
    static let bark = Color(red: 0x4A / 255, green: 0x2C / 255, blue: 0x2A / 255)
    static let barkLight = Color(red: 0x5A / 255, green: 0x3E / 255, blue: 0x36 / 255)
    static let bone = Color(red: 0xED / 255, green: 0xE3 / 255, blue: 0xD2 / 255)
    static let brass = Color(red: 0xC4 / 255, green: 0x96 / 255, blue: 0x27 / 255)
    static let olive = Color(red: 0x70 / 255, green: 0x82 / 255, blue: 0x38 / 255)

    // MARK: Type
    //
    // Every font keeps its design size at the default text size and grows with the reader's
    // Dynamic Type setting (Settings ▸ Display & Brightness ▸ Text Size, or Larger Text). The
    // text style says how fast it grows: titles slower than body text. Screens can cap growth
    // with `.dynamicTypeSize(...)`, which these fonts respect.

    static func title(_ size: CGFloat = 44) -> ThemeFont { ThemeFont(size: size, weight: .medium, design: .serif, style: .largeTitle) }
    static func body(_ size: CGFloat = 17) -> ThemeFont { ThemeFont(size: size, weight: .regular, design: .serif, style: .body) }
    static func caption(_ size: CGFloat = 13) -> ThemeFont { ThemeFont(size: size, weight: .regular, design: .serif, style: .footnote) }
    /// The serif (New York) at a weight, growing like `style`.
    static func serifText(_ size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> ThemeFont {
        ThemeFont(size: size, weight: weight, design: .serif, style: style)
    }
    /// The system sans (SF) at a weight, growing like `style`.
    static func sans(_ size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> ThemeFont {
        ThemeFont(size: size, weight: weight, design: .default, style: style)
    }
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
        // Tinted dark so text on the glass keeps its contrast over the light parts of the board.
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(Theme.night.opacity(0.6)), in: shape)
        } else {
            self.background(Theme.night.opacity(0.55), in: shape)
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

/// A house font that scales with Dynamic Type. Use it with `.font(_:)` like a `Font`.
struct ThemeFont {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let style: Font.TextStyle

    func weight(_ weight: Font.Weight) -> ThemeFont { ThemeFont(size: size, weight: weight, design: design, style: style) }

    /// The font at the design size, for places outside a view (it does not scale).
    var fixed: Font { .system(size: size, weight: weight, design: design) }

    func font(for typeSize: DynamicTypeSize) -> Font {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let scaled = UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size, compatibleWith: traits)
        return .system(size: scaled, weight: weight, design: design)
    }
}

private struct ScaledThemeFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let spec: ThemeFont
    func body(content: Content) -> some View { content.font(spec.font(for: typeSize)) }
}

extension View {
    func font(_ spec: ThemeFont) -> some View { modifier(ScaledThemeFont(spec: spec)) }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
