import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showUnlock = false

    var body: some View {
        @Bindable var settings = settings
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
                            let locked = theme.requiresPurchase && !store.hasFullJourney
                            Button {
                                if locked { showUnlock = true } else { settings.boardThemeID = theme.id }
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
                                    HStack(spacing: 4) {
                                        Text(theme.name)
                                            .font(Theme.caption(13))
                                            .foregroundStyle(settings.boardThemeID == theme.id ? Theme.gold : Theme.ivory)
                                        if locked {
                                            Image(systemName: "lock")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Theme.ivoryDim)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("theme-\(theme.id)")
                            .accessibilityLabel("\(theme.name), \(theme.tagline)\(locked ? ", locked" : "")")
                        }
                    }
                }
                Text(settings.boardTheme.tagline)
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ivoryDim)
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
        .sheet(isPresented: $showUnlock) {
            UnlockView()
                .presentationDetents([.large])
                .presentationBackground(Theme.ember)
        }
    }
}
