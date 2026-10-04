import LudoEngine
import SwiftUI

/// Settings, opened under the menu's tiles like Start game and Friends: rules for new games (a preset,
/// or your own switches), sound and haptics, in carved cards.
struct SettingsPanels: View {
    @Environment(AppSettings.self) private var settings
    @State private var showTipJar = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 14) {
            WoodCard(title: "Rules for new games") {
                WoodSegmented(options: RulesPreset.allCases, selection: $settings.preset, label: { $0.shortTitle },
                              id: { "rules-\($0.rawValue)" })
                Text(summary)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Palette.ivory.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.preset == .custom {
                WoodCard(title: "Kicks") {
                    VStack(spacing: 0) {
                        WoodRow { WoodToggle(title: "Back kick", isOn: $settings.custom.backKick).accessibilityIdentifier("rule-back-kick") }
                        WoodRow { WoodToggle(title: "Forward side kick", isOn: $settings.custom.forwardSideKick).accessibilityIdentifier("rule-forward-side-kick") }
                        WoodRow { WoodToggle(title: "Back side kick", isOn: $settings.custom.backSideKick).accessibilityIdentifier("rule-back-side-kick") }
                        WoodRow { WoodToggle(title: "Home kick", isOn: $settings.custom.homeKick).accessibilityIdentifier("rule-home-kick") }
                        WoodRow(divider: false) { WoodToggle(title: "A kick or a token home earns a roll", isOn: $settings.custom.kickOrHomeEarnsRoll) }
                    }
                }
                WoodCard(title: "Turns and squares") {
                    VStack(spacing: 0) {
                        WoodRow { WoodToggle(title: "Three sixes lose the turn", isOn: $settings.custom.threeSixesForfeit) }
                        WoodRow {
                            HStack {
                                Text("Two of your tokens together")
                                    .font(.system(.body, design: .serif).weight(.medium))
                                    .foregroundStyle(Palette.ivory)
                                Spacer(minLength: 8)
                                stackingMenu
                            }
                        }
                        WoodRow { WoodToggle(title: "Start squares are safe", isOn: $settings.custom.startSquaresSafe) }
                        WoodRow { WoodToggle(title: "Star squares are safe", isOn: $settings.custom.starSquaresSafe) }
                        WoodRow(divider: false) {
                            WoodToggle(title: "A 1 also brings a token out", isOn: Binding(
                                get: { settings.custom.entryRolls.contains(1) },
                                set: { settings.custom.entryRolls = $0 ? [1, 6] : [6] }))
                        }
                    }
                }
            }

            WoodCard(title: "Sound and touch") {
                VStack(alignment: .leading, spacing: 0) {
                    WoodRow {
                        VStack(alignment: .leading, spacing: 4) {
                            WoodToggle(title: "Sound", isOn: $settings.soundOn).accessibilityIdentifier("setting-sound")
                            Text("Sounds follow your device's Silent mode.")
                                .font(.system(.footnote, design: .serif))
                                .foregroundStyle(Palette.ivory.opacity(0.8))
                        }
                    }
                    WoodRow {
                        WoodToggle(title: "Haptics", isOn: $settings.hapticsOn).accessibilityIdentifier("setting-haptics")
                    }
                    WoodRow(divider: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Throw dice on board").font(.system(.body, design: .serif).weight(.medium)).foregroundStyle(Palette.ivory)
                            // On or Off. With the device's Reduce Motion on, nothing flies: On is greyed out and a note
                            // says how to see the dice thrown (owner, 2026-10-04).
                            WoodSegmented(options: [true, false],
                                          selection: Binding(get: { settings.throwDiceOnBoard && !reduceMotion },
                                                             set: { settings.throwDiceOnBoard = $0 }),
                                          label: { $0 ? "On" : "Off" }, id: { "throw-dice-\($0 ? "on" : "off")" },
                                          disabled: reduceMotion ? [true] : [])
                            Text(reduceMotion
                                 ? "Reduce Motion is on for your device, so the die just appears on the board. To see the dice thrown, turn off Reduce Motion in your device's Settings ▸ Accessibility ▸ Motion."
                                 : "On: your die is thrown onto the board (tap the board to skip). Off: it just appears there.")
                                .font(.system(.footnote, design: .serif).weight(reduceMotion ? .semibold : .regular))
                                .foregroundStyle(reduceMotion ? Palette.brassLight : Palette.ivory.opacity(0.8))
                                .accessibilityIdentifier("dice-motion-note")
                        }
                    }
                }
            }

            WoodCard(title: "About") {
                VStack(alignment: .leading, spacing: 0) {
                    WoodRow { linkRow("Privacy policy", systemImage: "hand.raised", url: Links.privacy, id: "link-privacy") }
                    WoodRow { linkRow("Help and support", systemImage: "questionmark.circle", url: Links.support, id: "link-support") }
                    WoodRow(divider: false) {
                        Button { showTipJar = true } label: {
                            HStack {
                                Label("Support me", systemImage: "heart")
                                    .font(.system(.body, design: .serif).weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(Palette.ivory)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("btn-tip-jar")
                    }
                }
            }
        }
        .sheet(isPresented: $showTipJar) { LudoTipJar() }
    }

    /// A web page from the settings: opens in the browser.
    private func linkRow(_ title: String, systemImage: String, url: URL, id: String) -> some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(.body, design: .serif).weight(.medium))
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Palette.ivory)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
    }

    /// "Wall: nobody passes ▾": the three ways two of your tokens on one square can behave.
    private var stackingMenu: some View {
        @Bindable var settings = settings
        return Menu {
            Picker("Two of your tokens together", selection: $settings.custom.stacking) {
                ForEach([RuleSet.Stacking.wall, .safe, .notAllowed], id: \.self) { Text(stackingTitle($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(stackingTitle(settings.custom.stacking))
                    .font(.system(.subheadline, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Image(systemName: "triangle.fill").font(.system(size: 9)).rotationEffect(.degrees(180))
            }
            .foregroundStyle(Palette.ivory)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(CarvedBlock(kind: .recessed, corner: 8))
        }
        .accessibilityIdentifier("picker-stacking")
    }

    private var summary: String {
        switch settings.preset {
        case .ghanaClassic: "Forward, back, side and home kicks. A 6 or a kick rolls again; three sixes lose the turn; two together make a wall."
        case .classic: "Plain Ludo: kick by landing on a token, a 6 rolls again, two together make a wall."
        case .custom: "Your own switches, starting from Ghana Classic."
        }
    }

    private func stackingTitle(_ s: RuleSet.Stacking) -> String {
        switch s {
        case .wall: "Wall: nobody passes"
        case .safe: "Safe: can't be kicked"
        case .notAllowed: "Not allowed"
        }
    }
}
