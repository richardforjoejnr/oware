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
    /// SwiftUI's purchase action: Apple's confirmation sheet appears over this window.
    @Environment(\.purchase) private var purchase
    let title: String
    let message: String
    let labels: [String]
    let details: [String]
    let appName: String?
    let reviewURL: URL?
    let style: TipJarStyle
    @Environment(\.openURL) private var openURL

    /// - Parameters:
    ///   - labels: one per product, in the jar's order (e.g. "Small", "Medium", "Generous").
    ///   - details: an optional short line under each label.
    ///   - appName: with `reviewURL`, the sheet also offers the free way to help: rating the app.
    ///   - reviewURL: the App Store's write-a-review page, `https://apps.apple.com/app/id<ID>?action=write-review`.
    ///     A link rather than `requestReview`, which the system may silently skip when tapped.
    public init(title: String = "Support the maker",
                message: String = "This game is free and always will be. If it has given you a good hour, a tip helps keep it going.",
                labels: [String] = ["Small tip", "Medium tip", "Generous tip"],
                details: [String] = [],
                appName: String? = nil,
                reviewURL: URL? = nil,
                style: TipJarStyle) {
        self.title = title
        self.message = message
        self.labels = labels
        self.details = details
        self.appName = appName
        self.reviewURL = reviewURL
        self.style = style
    }

    private var thanks: String {
        if jar.justTipped { return "Medaase — thank you!" }
        return jar.tipCount == 1 ? "You have supported this once. Medaase." : "You have supported this \(jar.tipCount) times. Medaase."
    }

    public var body: some View {
        ScrollView {
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
                Text(thanks)
                    .font(style.bodyFont.weight(.semibold))
                    .foregroundStyle(style.accent)
                    .accessibilityIdentifier("tip-jar-thanks")
            }

            switch jar.loadState {
            case .loaded:
                VStack(spacing: 10) {
                    ForEach(Array(jar.tips.enumerated()), id: \.element.id) { index, product in
                        Button {
                            Task { await jar.tip(product) { try await purchase($0) } }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(index < labels.count ? labels[index] : product.displayName)
                                    if index < details.count {
                                        Text(details[index])
                                            .font(.footnote)
                                            .foregroundStyle(style.secondaryText)
                                    }
                                }
                                Spacer()
                                if jar.purchasingID == product.id {
                                    ProgressView().tint(style.accent)
                                } else {
                                    Text(product.displayPrice)
                                        .monospacedDigit()
                                }
                            }
                            .font(style.bodyFont)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .modifier(TipButtonStyle(accent: style.accent, text: style.text))
                        .disabled(jar.purchasingID != nil)
                        .accessibilityIdentifier("tip-\(index)")
                    }
                }
                if let message = jar.purchaseMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tip-jar-purchase-status")
                }
            case .failed:
                // Never an empty sheet: say plainly what happened and offer another try.
                VStack(alignment: .leading, spacing: 10) {
                    Text(jar.loadMessage ?? TipJar.unavailableMessage)
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("tip-jar-status")
                    Button {
                        Task { await jar.retry() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(style.bodyFont)
                            .frame(maxWidth: .infinity)
                    }
                    .modifier(TipButtonStyle(accent: style.accent, text: style.text))
                    .accessibilityIdentifier("tip-jar-retry")
                }
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView().tint(style.accent)
                    Text("Loading the tips…")
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                        .accessibilityIdentifier("tip-jar-status")
                }
                .frame(minHeight: 44)
            }

            if let appName, let reviewURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Not today? A rating helps just as much: it is how other players find \(appName).")
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Rate \(appName)") { openURL(reviewURL) }
                        .font(style.bodyFont)
                        .tint(style.accent)
                        .accessibilityIdentifier("tip-jar-rate")
                }
            }

            Text("Tips are handled by Apple and unlock nothing. Every level, chapter and look is free for everyone.")
                .font(.footnote)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
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
