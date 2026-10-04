import LudoAI
import LudoEngine
import SwiftUI

/// The menu, after the owner's mockups: the carved LELU LUDO plaque and four tiles. With nothing open
/// the board stands in its box below them; Start game, Friends, Settings and Learn each open their own
/// carved panel there instead, on the same screen rather than in a sheet.
struct HomeView: View {
    @Environment(LudoSession.self) private var session
    @Environment(AppSettings.self) private var settings
    let startGame: () -> Void
    @State private var open: Panel?
    @State private var showTipJar = false
    @State private var computer = ComputerSeating()
    @State private var friends = FriendsSeating()
    @State private var level: LudoAIDifficulty = .novice

    enum Panel { case computer, friends, settings, learn }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(Art.menuTitle)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 420)
                    .accessibilityLabel("Lelu Ludo")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home-title")
                    .padding(.top, 8)

                // The owner's layout: the board in its box first, the tiles below it.
                Image(Art.boardBox)
                    .resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
                    .accessibilityHidden(true)

                HStack(spacing: 8) {
                    tile(Art.tileStart, label: "Start game against the computer", id: "tile-start", panel: .computer)
                    tile(Art.tileFriends, label: "Play with friends on this device", id: "tile-friends", panel: .friends)
                    tile(Art.tileSettings, label: "Settings. Rules: \(settings.preset.title)", id: "btn-settings", panel: .settings)
                    tile(Art.tileLearn, label: "Learn the game", id: "tile-learn", panel: .learn)
                }

                // Stays put while a panel is open, so nothing above the panel moves.
                if session.hasGame {
                    BrassButton(title: "Continue your game", systemImage: "play.fill") { startGame() }
                        .accessibilityIdentifier("btn-continue")
                }

                // A tile's panel appears under the tiles, in place: no slide, no scrolling. The page
                // simply grows; the panel's top shows, so it is plain there is more below.
                Group {
                    switch open {
                    case .computer: computerPanel
                    case .friends: friendsPanel
                    case .settings: SettingsPanels()
                    case .learn: learnPanel
                    case nil: EmptyView()
                    }
                }

                // The Support tile (owner's art): the tip jar.
                Button { showTipJar = true } label: {
                    Image(Art.tileSupport).resizable().scaledToFit()
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 120)
                .accessibilityLabel("Support me. A tip; it unlocks nothing")
                .accessibilityIdentifier("tile-support")

                HStack(spacing: 12) {
                    KnotGlyph(size: 16)
                    Text("\(settings.preset.title) rules")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Palette.brassLight)
                    KnotGlyph(size: 16)
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
                .woodPanel(corner: 8)
                .padding(.bottom, 24)
            }
            // One column, centred: on iPad the board box grows with it and the tiles and panels keep a
            // sensible width instead of running edge to edge.
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // the rules switch's words fit (as in GameView)
            .padding(.horizontal, 14)
        }
        .background(Table())
        .sheet(isPresented: $showTipJar) { LudoTipJar() }
    }

    /// You against 1–3 computers: your colour (the computers take the rest), how many, how strong.
    private var computerPanel: some View {
        WoodCard(title: "Play the computer") {
            label("Your colour")
            colourGrid { c in
                ColourTile(color: c, chosen: computer.you == c, badge: "You", action: { computer.you = c }) { EmptyView() }
            }
            SeatSummary(title: "Opponents:", players: computer.opponentColours.map { ($0, $0.name) })
            RandomColourButton(title: "Random colour") {
                var rng = SystemRandomNumberGenerator()
                computer.randomColour(using: &rng)
            }
            .accessibilityIdentifier("btn-random-colour")
            label("Opponents")
            WoodChips(options: [1, 2, 3], selection: $computer.opponents, label: { "\($0)" }, id: { "opponents-\($0)" })
            label("Level")
            WoodChips(options: LudoAIDifficulty.allCases, selection: $level, label: { $0.displayName },
                      id: { "level-\($0.displayName.lowercased())" })
            BrassButton(title: "Play as \(computer.you.name)", systemImage: "play.fill") {
                session.newGame(.versusComputer(you: computer.you, opponents: computer.opponents, level: level, rules: settings.rules))
                open = nil
                startGame()
            }
            .accessibilityIdentifier("btn-play-computer")
            RuledNote(text: "\(settings.preset.title) rules. Computers take the other colours.")
        }
    }

    /// 2–4 people passing one device: each taps a colour (one each: a colour can't be taken twice)
    /// and may type a name.
    private var friendsPanel: some View {
        WoodCard(title: "Play with friends") {
            Text("Tap colours to add or remove players.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Palette.ivory.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            colourGrid { c in
                ColourTile(color: c, chosen: friends.isPlaying(c), action: { friends.toggle(c) }) {
                    // Typing names is left out for now: the keyboard got stuck over the panel (owner, 2026-10-04).
                    Button { friends.toggle(c) } label: {
                        Text(friends.isPlaying(c) ? "Playing" : "Tap to add")
                            .font(.system(.subheadline, design: .serif).weight(friends.isPlaying(c) ? .bold : .regular))
                            .foregroundStyle(friends.isPlaying(c) ? Palette.brassLight : Palette.ivory.opacity(0.85))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(CarvedBlock(kind: .recessed, corner: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(friends.isPlaying(c) ? "Remove \(c.name)" : "Add \(c.name)")
                    .accessibilityIdentifier("add-\(c.name.lowercased())")
                }
            }
            SeatSummary(title: "Players: \(friends.colours.count)", players: friends.colours.map { ($0, friends.displayName($0)) })
            RandomColourButton(title: "Random colours") {
                var rng = SystemRandomNumberGenerator()
                friends.randomColours(using: &rng)
            }
            .accessibilityIdentifier("btn-random-colours")
            BrassButton(title: "Play together", systemImage: "person.2.fill") {
                guard let setup = friends.setup(rules: settings.rules) else { return }
                session.newGame(setup)
                open = nil
                startGame()
            }
            .disabled(!friends.canPlay)
            .opacity(friends.canPlay ? 1 : 0.5)
            .accessibilityIdentifier("btn-pass-play")
            Text(friends.canPlay ? "\(settings.preset.title) rules. Pass the device on each turn." : "Choose at least two colours.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Palette.ivory.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// The four colours, two by two.
    private func colourGrid<Tile: View>(@ViewBuilder _ tile: @escaping (PlayerColor) -> Tile) -> some View {
        // A plain grid, not a lazy one: every tile exists at once (VoiceOver can reach them all).
        Grid(horizontalSpacing: 14, verticalSpacing: 22) {
            GridRow { tile(.red); tile(.yellow) }
            GridRow { tile(.green); tile(.black) }
        }
        .padding(.bottom, 6)
    }

    /// Learn the game: three chapters, each a few lessons on the real board, and Start tutorial.
    private var learnPanel: some View {
        WoodCard(title: "Learn the game") {
            ForEach(Lesson.Chapter.allCases, id: \.self) { chapter in
                LessonCard(chapter: chapter) { startLessons(at: chapter.start) }
                    .accessibilityIdentifier("lesson-card-\(chapter.rawValue + 1)")
            }
            BrassButton(title: "Start tutorial", systemImage: "play.fill") { startLessons(at: 0) }
                .accessibilityIdentifier("btn-start-tutorial")
        }
    }

    private func startLessons(at index: Int) {
        session.startTutorial(at: index)
        open = nil
        startGame()
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(Palette.ivory)
    }

    private func tile(_ image: String, label: String, id: String, panel: Panel) -> some View {
        let selected = open == panel
        return Button {
            // No animation: animating the change slid the panel in and shifted the page.
            open = selected ? nil : panel
        } label: {
            Image(image).resizable().scaledToFit()
                .shadow(color: selected ? Palette.brassLight.opacity(0.95) : .black.opacity(0.35), radius: selected ? 9 : 4, y: selected ? 0 : 3)
                .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// A chapter of Learn the game: its picture, title and what it covers, and a brass arrow.
struct LessonCard: View {
    let chapter: Lesson.Chapter
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                picture
                    .frame(width: 104, height: 104)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.3)))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.brass.opacity(0.8), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 6) {
                    Text(chapter.title)
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .foregroundStyle(Palette.brassLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 6) {
                        Rectangle().fill(Palette.brass.opacity(0.6)).frame(height: 1)
                        KnotGlyph(size: 11)
                        Rectangle().fill(Palette.brass.opacity(0.6)).frame(height: 1)
                    }
                    Text(chapter.summary)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Palette.ivory.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Palette.night)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(RadialGradient(colors: [Palette.brassLight, Palette.brass, Palette.brassDark],
                                                             center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 24)))
                    .overlay(Circle().stroke(Palette.brassDark, lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.brass.opacity(0.55), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chapter.title). \(chapter.summary)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var picture: some View {
        switch chapter {
        case .board:
            MiniBoard().padding(6)
        case .moving:
            Image(Art.die(5)).resizable().scaledToFit().padding(14)
                .background(Image(Art.darkWood).resizable(resizingMode: .tile))
        case .ghanaRules:
            Image(Art.dieFlag).resizable().scaledToFit().padding(14)
                .background(Image(Art.darkWood).resizable(resizingMode: .tile))
        }
    }
}

/// The real board, small, with every colour's tokens in its yard (the Learn card's picture).
struct MiniBoard: View {
    var body: some View {
        BoardFrame(plaque: false) {
            GeometryReader { geo in
                let layout = BoardLayout(size: geo.size.width)
                ZStack {
                    BoardCanvas(rules: .ghanaClassic)
                    ForEach(PlayerColor.allCases, id: \.self) { color in
                        ForEach(0..<4, id: \.self) { token in
                            Image(Art.pawnTop(color)).resizable().scaledToFit()
                                .frame(width: layout.cell * 1.3)
                                .position(layout.position(color, token: token, progress: Board.yard))
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
