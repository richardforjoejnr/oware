import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings")
                .font(Theme.title(30))
                .foregroundStyle(Theme.ivory)

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
            }

            Toggle("Sound", isOn: $settings.soundEnabled)
                .accessibilityIdentifier("setting-sound")
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
                .accessibilityIdentifier("setting-haptics")
            Toggle("Show seed counts", isOn: $settings.showSeedCounts)
                .accessibilityIdentifier("setting-counts")

            Spacer()
            Text("Lelu Oware · Abapa rules")
                .font(Theme.caption())
                .foregroundStyle(Theme.ivoryDim)
        }
        .font(Theme.body())
        .foregroundStyle(Theme.ivory)
        .tint(Theme.gold)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
