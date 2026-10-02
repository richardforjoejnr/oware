import SwiftUI
import OwareEngine
import SupportKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(TipJar.self) private var tipJar
    @State private var showTipJar = false
    @State private var channel: AppChannel = .appStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var settings = settings
        // Scrolls so nothing is cut off on smaller phones or with larger text.
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings")
                .font(Theme.title(30))
                .foregroundStyle(Theme.ivory)

            VStack(alignment: .leading, spacing: 8) {
                Text("Board")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.ivoryDim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(BoardTheme.all) { theme in
                            Button {
                                settings.boardThemeID = theme.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom], startPoint: .top, endPoint: .bottom))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color(theme.uiTint).opacity(0.25 + theme.tintStrength * 0.5))
                                                .padding(10)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(settings.boardThemeID == theme.id ? Theme.gold : Theme.ivoryDim.opacity(0.25), lineWidth: settings.boardThemeID == theme.id ? 1.5 : 1)
                                        )
                                        .frame(width: 96, height: 60)
                                    Text(theme.name)
                                        .font(Theme.caption(13))
                                        .foregroundStyle(settings.boardThemeID == theme.id ? Theme.gold : Theme.ivory)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("theme-\(theme.id)")
                            .accessibilityLabel("\(theme.name), \(theme.tagline)")
                        }
                    }
                }
                Text(settings.boardTheme.tagline)
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ivoryDim)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Rules for new games")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.ivoryDim)
                Picker("Rules", selection: $settings.variant) {
                    Text("Nam-Nam").tag(RuleSet.Variant.namNam)
                    Text("Abapa").tag(RuleSet.Variant.abapa)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setting-rules")
                Text((settings.variant == .namNam
                     ? "Nam-Nam, \"to roam\": keep sowing while your last seed lands among other seeds; capture by making four; seeds you win become your houses next round, until one player holds all twelve."
                     : "Tournament Abapa: your turn ends where your last seed lands; capture houses you bring to two or three; first to 25 wins.")
                     + " Every game follows this: play, Pass & Play, Journey, riddles and the lesson.")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ivoryDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sowing speed")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.ivoryDim)
                Picker("Sowing speed", selection: $settings.animationSpeed) {
                    ForEach(AppSettings.AnimationSpeed.allCases.filter { $0 != .instant }) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setting-speed")
                if settings.calmMotion {
                    Text("Reduce Motion is on in iOS Settings: seeds still travel, without tumble or bounce.")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.ivoryDim)
                        .accessibilityIdentifier("setting-speed-note")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Sound", isOn: $settings.soundEnabled)
                    .accessibilityIdentifier("setting-sound")
                Text("Sounds follow your phone's Silent mode.")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ivoryDim)
            }
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
                .accessibilityIdentifier("setting-haptics")
            Toggle("Show house names (A1…B6)", isOn: $settings.showHouseNames)
                .accessibilityIdentifier("setting-house-names")
            Toggle("Show seed counts", isOn: $settings.showSeedCounts)
                .accessibilityIdentifier("setting-counts")

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Share anonymous usage stats", isOn: $settings.shareUsageStats)
                    .accessibilityIdentifier("setting-usage-stats")
                Text("Which modes are played and how games end, never who you are. It helps decide what to make next.")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ivoryDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            QuietButton(title: "Leaderboards & achievements", subtitle: "Game Center") {
                GameCenter.shared.showDashboard()
            }
            .accessibilityIdentifier("btn-game-center")
            if FeatureFlags.newsletter {
                QuietButton(title: "News by email", subtitle: "new chapters and features, from the website") {
                    openURL(Links.newsletter)
                }
                .accessibilityIdentifier("btn-newsletter")
            }
            QuietButton(title: "Support me", subtitle: tipJar.hasTipped ? "medaase — thank you for your support" : "tips keep it growing and bring new features") {
                showTipJar = true
            }
            .accessibilityIdentifier("btn-tip-jar")
            Text("Lelu Oware · \(settings.rules.variant == .namNam ? "Nam-Nam" : "Abapa") rules")
                .font(Theme.caption())
                .foregroundStyle(Theme.ivoryDim)
            Text(AppVersion.label(channel: channel))
                .font(Theme.caption(12))
                .foregroundStyle(Theme.ivoryDim)
                .accessibilityIdentifier("app-version")
                .task { channel = await AppChannel.current() }
        }
        .font(Theme.body())
        .foregroundStyle(Theme.ivory)
        .tint(Theme.gold)
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showTipJar) {
            TipJarView(title: "Support me",
                       message: "I make Lelu Oware on my own. It is free, with no adverts and nothing locked. If it has given you a good game, buy me a drink or a meal. It helps me keep making it better.",
                       labels: ["A cold drink", "A plate of waakye", "A feast"],
                       details: ["a small thank-you", "lunch is on you", "for the true Oware lovers"],
                       appName: "Lelu Oware",
                       reviewURL: Links.writeReview,
                       style: TipJarStyle(accent: Theme.gold, text: Theme.ivory, secondaryText: Theme.ivoryDim, background: Theme.ember,
                                          titleFont: Theme.title(30).fixed, bodyFont: Theme.body(18).fixed))
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.ember)
                .onAppear { PlayerEvents.shared.tipJarViewed() }
        }
    }
}
