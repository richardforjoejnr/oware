import SwiftUI

/// How long the opening plays: the whole carved-map moment on the first launch of the day, a short
/// one after that, so returning players reach the board well inside three seconds.
enum SplashSchedule {
    static let full: Duration = .milliseconds(2800)
    static let short: Duration = .milliseconds(1000)
    static let key = "splashFullShownOn"

    /// The length for this launch; records today when it is the full one.
    static func durationForThisLaunch(defaults: UserDefaults = .standard, now: Date = .now, calendar: Calendar = .current) -> Duration {
        if let last = defaults.object(forKey: key) as? Date, calendar.isDate(last, inSameDayAs: now) { return short }
        defaults.set(now, forKey: key)
        return full
    }
}

/// The opening: the carved Ghana map, the title, a quiet loading line, then the menu; a tap skips
/// it. Reduce Motion keeps the length but drops the title's slide-in.
struct SplashView: View {
    var duration: Duration = SplashSchedule.full
    let finished: () -> Void
    @State private var progress: CGFloat = 0
    @State private var titleShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var done = false

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            GeometryReader { geo in
                Image("splashMap")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay(
                        LinearGradient(stops: [
                            .init(color: Theme.night.opacity(0.35), location: 0),
                            .init(color: .clear, location: 0.25),
                            .init(color: .clear, location: 0.6),
                            .init(color: Theme.night.opacity(0.92), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Spacer()
                Text("Lelu Oware")
                    .font(Theme.title(46))
                    .foregroundStyle(Theme.bone)
                    .shadow(color: Theme.night.opacity(0.9), radius: 14, y: 4)
                    .opacity(titleShown ? 1 : 0)
                    .offset(y: titleShown || reduceMotion ? 0 : 8)
                    .accessibilityIdentifier("splash-title")
                Text("Ghana's game")
                    .font(Theme.caption(15))
                    .tracking(1.4)
                    .foregroundStyle(Theme.ivoryDim)
                    .opacity(titleShown ? 1 : 0)
                // A thin brass line filling left to right: the whole "loading indicator".
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.bone.opacity(0.12))
                        Capsule().fill(Theme.brass).frame(width: geo.size.width * progress)
                    }
                }
                .frame(width: 120, height: 2)
                .padding(.top, 14)
                .accessibilityHidden(true)
            }
            .padding(.bottom, 64)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to skip")
        .task {
            let total = duration
            withAnimation(.easeOut(duration: 0.5)) { titleShown = true }
            withAnimation(.linear(duration: Double(total.components.seconds) + Double(total.components.attoseconds) / 1e18)) { progress = 1 }
            try? await Task.sleep(for: total)
            finish()
        }
    }

    private func finish() {
        guard !done else { return }
        done = true
        finished()
    }
}
