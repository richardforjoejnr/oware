import StoreKit
import SwiftUI

/// Colours and type the host app passes in so the jar matches its look.
public struct TipJarStyle: Sendable {
    public var accent: Color
    public var text: Color
    public var secondaryText: Color
    public var background: Color
    public var titleFont: Font
    public var bodyFont: Font

    public init(accent: Color, text: Color, secondaryText: Color, background: Color,
                titleFont: Font = .title2.weight(.semibold), bodyFont: Font = .body) {
        self.accent = accent
        self.text = text
        self.secondaryText = secondaryText
        self.background = background
        self.titleFont = titleFont
        self.bodyFont = bodyFont
    }
}

/// A sheet with the tips. Nothing is locked; this is a thank-you, and it says so.
public struct TipJarView: View {
    @Environment(TipJar.self) private var jar
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let labels: [String]
    let style: TipJarStyle

    /// - Parameters:
    ///   - labels: one per product, in the jar's order (e.g. "Small", "Medium", "Generous").
    public init(title: String = "Support the maker",
                message: String = "This game is free and always will be. If it has given you a good hour, a tip helps keep it going.",
                labels: [String] = ["Small tip", "Medium tip", "Generous tip"],
                style: TipJarStyle) {
        self.title = title
        self.message = message
        self.labels = labels
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(style.titleFont)
                .foregroundStyle(style.text)
                .accessibilityIdentifier("tip-jar-title")
            Text(message)
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if jar.justTipped || jar.hasTipped {
                Text(jar.justTipped ? "Medaase — thank you!" : "You have tipped before. Medaase.")
                    .font(style.bodyFont.weight(.semibold))
                    .foregroundStyle(style.accent)
                    .accessibilityIdentifier("tip-jar-thanks")
            }

            if jar.tips.isEmpty {
                HStack(spacing: 10) {
                    if jar.isLoading { ProgressView().tint(style.accent) }
                    Text(jar.lastError ?? "Loading…")
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                        .accessibilityIdentifier("tip-jar-status")
                }
                .frame(minHeight: 44)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(jar.tips.enumerated()), id: \.element.id) { index, product in
                        Button {
                            Task { await jar.tip(product) }
                        } label: {
                            HStack {
                                Text(index < labels.count ? labels[index] : product.displayName)
                                Spacer()
                                Text(product.displayPrice)
                                    .monospacedDigit()
                            }
                            .font(style.bodyFont)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .modifier(TipButtonStyle(accent: style.accent, text: style.text))
                        .accessibilityIdentifier("tip-\(index)")
                    }
                }
                if let error = jar.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(style.secondaryText)
                }
            }

            Text("Tips are handled by Apple and unlock nothing. Every level, chapter and look is free for everyone.")
                .font(.footnote)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.background.ignoresSafeArea())
        .task { await jar.load() }
    }
}

/// System button styles: Liquid Glass on iOS 26, bordered before that.
private struct TipButtonStyle: ViewModifier {
    let accent: Color
    let text: Color
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content.buttonStyle(.glass).tint(accent).foregroundStyle(text).controlSize(.large)
        } else {
            content.buttonStyle(.bordered).tint(accent).foregroundStyle(text).controlSize(.large)
        }
    }
}
