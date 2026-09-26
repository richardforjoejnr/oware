import SwiftUI

/// The opening: the carved Ghana map, the title, a quiet loading line. About a second and a
/// half, then the menu. Skipped in test launches and cut short under Reduce Motion.
struct SplashView: View {
    let finished: () -> Void
    @State private var progress: CGFloat = 0
    @State private var titleShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let duration: Duration = .milliseconds(1500)

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
                    .offset(y: titleShown ? 0 : 8)
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
        .task {
            let total = reduceMotion ? Duration.milliseconds(500) : Self.duration
            withAnimation(.easeOut(duration: 0.5)) { titleShown = true }
            withAnimation(.linear(duration: Double(total.components.seconds) + Double(total.components.attoseconds) / 1e18)) { progress = 1 }
            try? await Task.sleep(for: total)
            finished()
        }
    }
}
