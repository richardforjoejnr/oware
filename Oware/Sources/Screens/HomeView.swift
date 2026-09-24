import SwiftUI
import OwareEngine
import OwareAI

/// Home: a carved bowl in warm light, the title, then a short column of pill buttons framed by
/// Kente bands. Play is the one green button; Journey and the lesson sit under it; everything
/// else lives behind "More".
struct HomeView: View {
    @Environment(GameSession.self) private var session
    @Environment(PuzzleLibrary.self) private var library
    @Environment(JourneyProgress.self) private var progress
    @Environment(AppSettings.self) private var settings
    let startGame: () -> Void
    let openPuzzles: () -> Void
    let openHeritage: () -> Void
    let openJourney: () -> Void
    let openSettings: () -> Void

    @AppStorage("preferredDifficulty") private var preferredDifficulty: Int = Difficulty.learner.rawValue
    @AppStorage("tutorialSeen") private var tutorialSeen = false
    @State private var showMore = false
    @State private var showLevels = false

    private var difficulty: Difficulty { Difficulty(rawValue: preferredDifficulty) ?? .learner }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 700
            ZStack(alignment: .top) {
                Theme.night.ignoresSafeArea()
                hero(height: min(geo.size.height * (compact ? 0.40 : 0.46), 520))
                    .ignoresSafeArea(edges: .top)
                KenteEdges()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: min(geo.size.height * (compact ? 0.24 : 0.30), 360))
                        titleBlock
                            .padding(.bottom, compact ? 18 : 26)
                        menu
                        Text("Oware · Abapa rules · a game of Ghana")
                            .font(Theme.caption())
                            .foregroundStyle(Theme.ivoryDim)
                            .padding(.top, 22)
                            .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 36)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showMore)
        .animation(.easeInOut(duration: 0.2), value: showLevels)
    }

    /// The bowl in warm light, fading into the dark so the title and menu sit on it.
    private func hero(height: CGFloat) -> some View {
        Image("bowl")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay(
                LinearGradient(stops: [
                    .init(color: Theme.night.opacity(0.25), location: 0),
                    .init(color: Theme.night.opacity(0.0), location: 0.3),
                    .init(color: Theme.night.opacity(0.55), location: 0.68),
                    .init(color: Theme.night, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("Lelu Oware")
                .font(Theme.title(46))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Theme.night.opacity(0.9), radius: 14, y: 4)
                .accessibilityIdentifier("home-title")
            HStack(spacing: 10) {
                KenteRule()
                Text("Akwaaba · welcome")
                    .font(Theme.caption(14))
                    .tracking(1.6)
                    .foregroundStyle(Theme.ivoryDim)
                    .fixedSize()
                KenteRule()
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var menu: some View {
        VStack(spacing: 10) {
            primaryAction

            MenuPill(title: "Journey", subtitle: progress.totalStars == 0 ? "across Ghana" : "\(progress.totalStars) stars",
                     icon: .symbol("map")) { openJourney() }
                .accessibilityIdentifier("btn-journey")

            if !tutorialSeen {
                MenuPill(title: "New here?", subtitle: "learn in five minutes", icon: .symbol("book")) {
                    tutorialSeen = true
                    session.startTutorial(step: 0)
                    startGame()
                }
                .accessibilityIdentifier("btn-learn")
            }

            MenuPill(title: showMore ? "Less" : "More", icon: .symbol(showMore ? "chevron.up" : "ellipsis"), quiet: true) {
                showMore.toggle()
            }
            .accessibilityIdentifier("btn-more")
            .accessibilityLabel(showMore ? "Fewer options" : "More options")

            if showMore {
                moreItems
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Primary

    @ViewBuilder
    private var primaryAction: some View {
        if session.hasResumableGame {
            MenuPill(title: "Continue", subtitle: session.mode.title, icon: .symbol("play.fill"), prominent: true) {
                startGame()
            }
            .accessibilityIdentifier("btn-continue")

            MenuPill(title: "New game", subtitle: "against \(difficulty.displayName)", icon: .symbol("plus")) {
                startNewGame()
            }
            .accessibilityIdentifier("btn-play-ai")
        } else {
            MenuPill(title: "Play", subtitle: nil, icon: .symbol("play.fill"), prominent: true) {
                startNewGame()
            }
            .accessibilityIdentifier("btn-play-ai")

            Button {
                showLevels.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("against \(difficulty.displayName)")
                    Image(systemName: showLevels ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
                .font(Theme.caption(14))
                .foregroundStyle(Theme.ivoryDim)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-level")
            .accessibilityLabel("Opponent level, \(difficulty.displayName)")

            if showLevels {
                levelPicker
                    .transition(.opacity)
            }
        }
    }

    private func startNewGame() {
        session.newGame(.versusAI(difficulty: difficulty, personality: .balanced, humanPlays: .south), rules: settings.rules)
        startGame()
    }

    private var levelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Difficulty.allCases, id: \.rawValue) { level in
                    Button {
                        preferredDifficulty = level.rawValue
                        showLevels = false
                    } label: {
                        Text(level.displayName)
                            .font(Theme.caption(14))
                            .foregroundStyle(level == difficulty ? Theme.gold : Theme.ivoryDim)
                            .underline(level == difficulty, color: Theme.gold)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("level-\(level.displayName.lowercased())")
                    .accessibilityAddTraits(level == difficulty ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .accessibilityIdentifier("level-picker")
    }

    // MARK: - More

    private var moreItems: some View {
        VStack(spacing: 10) {
            MenuPill(title: "Pass & Play", subtitle: "two players, one board", icon: .symbol("person.2")) {
                session.newGame(.passAndPlay, rules: settings.rules)
                startGame()
            }
            .accessibilityIdentifier("btn-pass-play")

            MenuPill(title: "Riddles", subtitle: library.dailySolved ? "today's solved · \(library.solvedIDs.count) of \(library.puzzles.count)" : "a new one every day",
                     icon: .adinkra(AnyShape(Adinkra.Nyansapo()))) {
                openPuzzles()
            }
            .accessibilityIdentifier("btn-puzzles")

            if tutorialSeen {
                MenuPill(title: "Learn", subtitle: "the five-minute lesson", icon: .symbol("book")) {
                    session.startTutorial(step: 0)
                    startGame()
                }
                .accessibilityIdentifier("btn-learn")
            }

            MenuPill(title: "Rules & heritage", icon: .symbol("building.columns")) { openHeritage() }
                .accessibilityIdentifier("btn-heritage")

            MenuPill(title: "Settings", icon: .symbol("gearshape")) { openSettings() }
                .accessibilityIdentifier("btn-settings")
        }
    }
}

// MARK: - Pieces

/// A rounded menu button in the house style: gold icon on the left, serif title, quiet subtitle.
/// `prominent` marks the main action with gold text and a gold edge (no filled state, so nothing
/// looks pre-selected on a touch screen); `quiet` is the low-key More/Less toggle.
struct MenuPill: View {
    enum Icon {
        case symbol(String)
        case adinkra(AnyShape)
    }

    let title: String
    var subtitle: String? = nil
    let icon: Icon
    var prominent = false
    var quiet = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconView
                    .frame(width: 26, height: 26)
                    .foregroundStyle(Theme.gold)
                Text(title)
                    .font(Theme.body(prominent ? 22 : 19))
                    .foregroundStyle(prominent ? Theme.goldLight : (quiet ? Theme.ivoryDim : Theme.ivory))
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.caption(13))
                        .foregroundStyle(Theme.ivoryDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(height: quiet ? 44 : (prominent ? 58 : 54))
            .frame(maxWidth: .infinity)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(prominent ? Theme.gold.opacity(0.55) : Theme.ivory.opacity(quiet ? 0.08 : 0.14), lineWidth: prominent ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.night.opacity(prominent ? 0.6 : 0.4), radius: 8, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 19, weight: .medium))
        case let .adinkra(shape):
            shape.stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .padding(2)
        }
    }

    @ViewBuilder
    private var background: some View {
        if quiet {
            Theme.ember.opacity(0.55)
        } else {
            LinearGradient(colors: [Theme.emberLight, Theme.ember], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Thin Kente bands down both edges of the screen.
struct KenteEdges: View {
    var width: CGFloat = 14
    var body: some View {
        HStack {
            band
            Spacer()
            band
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var band: some View {
        GeometryReader { geo in
            Image("kenteLine")
                .resizable(resizingMode: .tile)
                .frame(width: geo.size.height, height: width)
                .rotationEffect(.degrees(90))
                .frame(width: width, height: geo.size.height)
                .opacity(0.9)
        }
        .frame(width: width)
    }
}

/// A short gold rule used either side of a caption.
struct KenteRule: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Theme.kenteRed, Theme.gold, Theme.kenteGreen], startPoint: .leading, endPoint: .trailing))
            .frame(height: 2)
            .frame(maxWidth: 70)
            .opacity(0.85)
    }
}
