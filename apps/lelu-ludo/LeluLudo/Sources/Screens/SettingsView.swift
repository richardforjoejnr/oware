import LudoEngine
import SwiftUI

/// Rules for new games (a preset, or your own switches), sound and haptics.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Rules", selection: $settings.preset) {
                        ForEach(RulesPreset.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("picker-rules")
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Rules for new games")
                }

                if settings.preset == .custom {
                    Section("Kicks") {
                        Toggle("Back kick", isOn: $settings.custom.backKick).accessibilityIdentifier("rule-back-kick")
                        Toggle("Forward side kick", isOn: $settings.custom.forwardSideKick).accessibilityIdentifier("rule-forward-side-kick")
                        Toggle("Back side kick", isOn: $settings.custom.backSideKick).accessibilityIdentifier("rule-back-side-kick")
                        Toggle("Home kick", isOn: $settings.custom.homeKick).accessibilityIdentifier("rule-home-kick")
                        Toggle("A kick or a token home earns a roll", isOn: $settings.custom.kickOrHomeEarnsRoll)
                    }
                    Section("Turns and squares") {
                        Toggle("Three sixes lose the turn", isOn: $settings.custom.threeSixesForfeit)
                        Picker("Two of your tokens together", selection: $settings.custom.stacking) {
                            Text("Wall: nobody passes").tag(RuleSet.Stacking.wall)
                            Text("Safe: can't be kicked").tag(RuleSet.Stacking.safe)
                            Text("Not allowed").tag(RuleSet.Stacking.notAllowed)
                        }
                        Toggle("Start squares are safe", isOn: $settings.custom.startSquaresSafe)
                        Toggle("Star squares are safe", isOn: $settings.custom.starSquaresSafe)
                        Toggle("A 1 also brings a token out", isOn: Binding(
                            get: { settings.custom.entryRolls.contains(1) },
                            set: { settings.custom.entryRolls = $0 ? [1, 6] : [6] }))
                    }
                }

                Section("Sound and touch") {
                    Toggle("Sound", isOn: $settings.soundOn).accessibilityIdentifier("setting-sound")
                    Text("Sounds follow your phone's Silent switch.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Haptics", isOn: $settings.hapticsOn).accessibilityIdentifier("setting-haptics")
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() }.accessibilityIdentifier("btn-done") }
        }
    }

    private var summary: String {
        switch settings.preset {
        case .ghanaClassic: "Forward, back, side and home kicks. A 6 or a kick rolls again; three sixes lose the turn; two together make a wall."
        case .classic: "Plain Ludo: kick by landing on a token, a 6 rolls again, two together make a wall."
        case .custom: "Your own switches, starting from Ghana Classic."
        }
    }
}
