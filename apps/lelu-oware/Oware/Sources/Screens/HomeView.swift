import SwiftUI
import OwareEngine
import OwareAI

/// Home: dark wood, the title, one dominant Continue (or Play), then a 2×2 grid of flat wooden
/// tiles. Red · gold · green appear only as tiny inlays. Everything here vanishes once you play.
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
        ZStack {
            GeometryReader { geo in
                Image("ground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            RadialGradient(colors: [.clear, Theme.night.opacity(0.7)], center: .center, startRadius: 120, endRadius: 620)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 72)
                    titleBlock
                        .padding(.bottom, 36)
                    primary
                        .padding(.bottom, 14)
                    grid
                    if showMore {
                        moreList
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Text("Oware · Abapa rules · a game of Ghana")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.ivoryDim)
                        .padding(.top, 30)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showMore)
        .animation(.easeInOut(duration: 0.2), value: showLevels)
    }

    private var titleBlock: some View {
        VStack(spacing: 10) {
            Text("Lelu Oware")
                .font(Theme.title(48))
                .foregroundStyle(Theme.bone)
                .shadow(color: Theme.night.opacity(0.8), radius: 12, y: 3)
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
        .multilineTextAlignment(.center)
    }

    // MARK: - Primary

    @ViewBuilder
    private var primary: some View {
        if session.hasResumableGame {
            WoodPlank(title: "Continue", subtitle: session.mode.title, glyph: "play", height: 64) { startGame() }
                .accessibilityIdentifier("btn-continue")
        } else {
            VStack(spacing: 8) {
                WoodPlank(title: "Play", subtitle: "against \(difficulty.displayName)", glyph: "play", height: 64) { startNewGame() }
                    .accessibilityIdentifier("btn-play-ai")
                levelChooser
            }
        }
    }

    private var levelChooser: some View {
        VStack(spacing: 6) {
            Button {
                showLevels.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("Change level")
                    Image(systemName: showLevels ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ivoryDim)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn-level")
            .accessibilityLabel("Opponent level, \(difficulty.displayName)")
            if showLevels {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(Difficulty.allCases, id: \.rawValue) { level in
                            Button {
                                preferredDifficulty = level.rawValue
                                showLevels = false
                            } label: {
                                Text(level.displayName)
                                    .font(.subheadline.weight(level == difficulty ? .semibold : .regular))
                                    .foregroundStyle(level == difficulty ? Theme.brass : Theme.ivoryDim)
                                    .frame(minHeight: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("level-\(level.displayName.lowercased())")
                            .accessibilityAddTraits(level == difficulty ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityIdentifier("level-picker")
                .transition(.opacity)
            }
        }
    }

    private func startNewGame() {
        session.newGame(.versusAI(difficulty: difficulty, personality: .balanced, humanPlays: .south), rules: settings.rules)
        startGame()
    }

    // MARK: - Grid

    private var grid: some View {
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return LazyVGrid(columns: columns, spacing: 14) {
            if session.hasResumableGame {
                WoodTile(title: "New game", subtitle: "against \(difficulty.displayName)", glyph: "plus") { startNewGame() }
                    .accessibilityIdentifier("btn-play-ai")
            } else {
                WoodTile(title: "Riddles", subtitle: library.dailySolved ? "today's solved" : "one a day", glyph: "knot") { openPuzzles() }
                    .accessibilityIdentifier("btn-puzzles")
            }
            WoodTile(title: "Journey", subtitle: progress.totalStars == 0 ? "across Ghana" : "\(progress.totalStars) stars", glyph: "map") { openJourney() }
                .accessibilityIdentifier("btn-journey")
            if tutorialSeen {
                WoodTile(title: "Learn", subtitle: "the five-minute lesson", glyph: "book") {
                    session.startTutorial(step: 0)
                    startGame()
                }
                .accessibilityIdentifier("btn-learn")
            } else {
                WoodTile(title: "New here?", subtitle: "learn in five minutes", glyph: "book") {
                    tutorialSeen = true
                    session.startTutorial(step: 0)
                    startGame()
                }
                .accessibilityIdentifier("btn-learn")
            }
            WoodTile(title: showMore ? "Less" : "More", subtitle: showMore ? "" : "two players, riddles, rules", glyph: "more") { showMore.toggle() }
                .accessibilityIdentifier("btn-more")
                .accessibilityLabel(showMore ? "Fewer options" : "More options")
        }
    }

    private var moreList: some View {
        VStack(spacing: 8) {
            WoodPlank(title: "Pass & Play", subtitle: "two players, one board", glyph: "people", height: 56) {
                session.newGame(.passAndPlay, rules: settings.rules)
                startGame()
            }
            .accessibilityIdentifier("btn-pass-play")
            if session.hasResumableGame {
                WoodPlank(title: "Riddles", subtitle: library.dailySolved ? "today's solved · \(library.solvedIDs.count) of \(library.puzzles.count)" : "a new one every day", glyph: "knot", height: 56) { openPuzzles() }
                    .accessibilityIdentifier("btn-puzzles")
            }
            WoodPlank(title: "Rules & heritage", subtitle: "how it is played, where it comes from", glyph: "info", height: 56) { openHeritage() }
                .accessibilityIdentifier("btn-heritage")
            WoodPlank(title: "Settings", subtitle: "sound, speed, board", glyph: "gear", height: 56) { openSettings() }
                .accessibilityIdentifier("btn-settings")
        }
    }
}

// MARK: - Wooden controls

/// Matte wood surface with a dark inset edge: the material, not a glossy button.
private struct WoodSurface: View {
    var cornerRadius: CGFloat = 16
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            GeometryReader { geo in
                Image("wood")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            LinearGradient(colors: [Theme.night.opacity(0.10), Theme.night.opacity(0.34)], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.night.opacity(0.7), lineWidth: 1))
        .overlay(shape.inset(by: 1).strokeBorder(Theme.bone.opacity(0.08), lineWidth: 1))
        .shadow(color: Theme.night.opacity(0.55), radius: 6, y: 3)
    }
}

/// Three tiny inlaid dots — red, gold, green — the only colour on the menu.
private struct Inlay: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.kenteRed)
            Circle().fill(Theme.gold)
            Circle().fill(Theme.kenteGreen)
        }
        .frame(width: 22, height: 4)
        .opacity(0.85)
        .accessibilityHidden(true)
    }
}

/// A wide wooden control: glyph, title, subtitle, inlay at the end.
struct WoodPlank: View {
    let title: String
    var subtitle: String? = nil
    let glyph: String
    var height: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image("wood-\(glyph)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: height >= 64 ? 22 : 18, weight: .semibold))
                    .foregroundStyle(Theme.bone)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.ivoryDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Inlay()
            }
            .padding(.horizontal, 18)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(WoodSurface())
            .contentShape(Rectangle())
        }
        .buttonStyle(PressLift())
    }
}

/// A square-ish wooden tile for the 2×2 grid.
struct WoodTile: View {
    let title: String
    var subtitle: String = ""
    let glyph: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image("wood-\(glyph)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    Spacer()
                    Inlay()
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.bone)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.ivoryDim)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(WoodSurface())
            .contentShape(Rectangle())
        }
        .buttonStyle(PressLift())
    }
}

/// A pressed wooden control sinks by 2 % and darkens a touch, like wood under a finger.
private struct PressLift: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A short rule in red, gold and green either side of a caption.
struct KenteRule: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Theme.kenteRed, Theme.gold, Theme.kenteGreen], startPoint: .leading, endPoint: .trailing))
            .frame(height: 2)
            .frame(maxWidth: 70)
            .opacity(0.85)
    }
}
