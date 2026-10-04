import LudoAI
import LudoEngine
import SwiftUI

/// A game, on the sand table: a wooden status plaque, the board in its box, and the tray with the
/// players, the die and the cup.
struct GameView: View {
    @Environment(LudoSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    let goHome: () -> Void
    /// Which throws have landed (the tray's die and the status wait for it).
    @State private var flight = DieFlight()
    @State private var showLevels = false

    /// Throws are shown on the board (not under Reduce Motion, not in tests).
    private var animated: Bool { RollingDie.shown }
    /// Your dice throw (Settings), or the device's Reduce Motion until you choose.
    private var style: DiceAnimation { settings.diceThrow(reduceMotion: reduceMotion) }
    /// The die is in the air: the status says so until it lands.
    private var rolling: Bool { animated && session.lastRoll != nil && flight.inFlight(session.rolls) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                WoodCircleButton(systemImage: "chevron.left", action: leave)
                    .accessibilityLabel("Home")
                    .accessibilityIdentifier("btn-home")
                if session.tutorial != nil {
                    Spacer(minLength: 0)
                } else {
                    StatusPlaque(status: rolling ? "Rolling…" : session.status, line: session.log.last)
                }
                if session.tutorial == nil, let level = session.computerLevel {
                    // As in Lelu Oware: the opponents' level, tap to change it for this game.
                    Button { withAnimation(.easeInOut(duration: 0.2)) { showLevels.toggle() } } label: {
                        HStack(spacing: 4) {
                            Text(level.displayName).lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                                .rotationEffect(.degrees(showLevels ? 180 : 0))
                        }
                        .font(.system(.footnote, design: .serif).weight(.semibold))
                        .foregroundStyle(Palette.ivory)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 48)
                        .woodPanel(corner: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Opponent level, \(level.displayName). Tap to change")
                    .accessibilityIdentifier("btn-level")
                }
            }
            if showLevels, let current = session.computerLevel {
                HStack(spacing: 14) {
                    ForEach(LudoAIDifficulty.allCases, id: \.self) { level in
                        Button {
                            session.changeLevel(to: level)
                            withAnimation(.easeInOut(duration: 0.2)) { showLevels = false }
                        } label: {
                            Text(level.displayName)
                                .font(.system(.footnote, design: .serif).weight(level == current ? .bold : .regular))
                                .foregroundStyle(level == current ? Color(red: 0.95, green: 0.80, blue: 0.45) : Palette.ivory)
                                .underline(level == current)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(level == current ? .isSelected : [])
                        .accessibilityIdentifier("game-level-\(level.rawValue)")
                    }
                }
                .padding(.horizontal, 14)
                .woodPanel(corner: 22)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let tutorial = session.tutorial {
                LessonPlaque(progress: tutorial, next: next, retry: { session.retryLesson() })
            }
            Spacer(minLength: 0)
            BoardFrame(plaque: false) { BoardView() }
                .overlay {
                    // Each roll tumbles across the board; the tray's die keeps the result.
                    // Only when the dice are thrown on the board; with it off the roll shows on the tray's die.
                    if session.rolls > 0, let roll = session.lastRoll, animated, style != .off, flight.skipped < session.rolls {
                        let count = session.rolls
                        // Your throw as chosen in Settings; computers' always the quick one.
                        let yours = session.setup.seat(roll.color) == .human
                        RollingDie(value: roll.value, landing: RollingDie.landing(for: count),
                                   timing: yours ? .of(style) : .quick,
                                   landed: { flight.land(count) }, returned: { flight.returned(count) })
                            .id(count)
                            // Catches taps (to skip) only while in the air, never over the tokens after.
                            .allowsHitTesting(flight.inFlight(count))
                            .simultaneousGesture(TapGesture().onEnded { flight.skip(count) })
                    }
                }
                // Above the tray below it: the die leaves from (and goes back to) the tray's cup.
                .zIndex(1)
            // The board and its tray belong together: no gap between them, and the pair centred in
            // the room below the top bar (on a tall phone the sand goes above and below, not between).
            Tray()
            Spacer(minLength: 0)
        }
        // On iPad: a game-sized column in the middle, not a tray stretched across the screen.
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        // Text grows with the reader's setting up to the largest standard size: beyond it, a lesson's
        // words squeezed the board to a thumbnail and the plaques cut their words short.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .environment(flight)
        // A light knock as the die lands on the board.
        .sensoryFeedback(.impact(weight: .light), trigger: flight.landed) { _, _ in animated && settings.effectiveHaptics }
        // Your throw in Settings applies at once.
        // No throw on the board: the tray's die shows the roll at once.
        .onChange(of: session.rolls) { _, rolls in if !animated || style == .off { flight.returned(rolls) } }
        .onChange(of: style) { _, style in
            if session.pacing != .instant { session.pacing = .normal(style) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Table())
        .onChange(of: session.log) { _, log in
            if let line = log.last { AccessibilityNotification.Announcement(line).post() }
        }
    }
}

extension GameView {
    /// Home; a lesson in progress gives the player's own game back first.
    private func leave() {
        session.endTutorial()
        goHome()
    }

    /// The next lesson, or home after the last.
    private func next() {
        if !session.nextLesson() { leave() }
    }
}

/// Learn the game: the lesson's title, what to do (or why it worked), and Next or Try again.
struct LessonPlaque: View {
    let progress: TutorialProgress
    let next: () -> Void
    let retry: () -> Void

    var body: some View {
        let lesson = progress.lesson
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(lesson.chapter.title.uppercased()) · \(progress.index + 1) OF \(Lesson.all.count)")
                    .font(.system(.caption, design: .serif).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Palette.brassLight)   // plain brass on this wood measured 3.7:1; small text needs 4.5:1
                Spacer()
            }
            Text(lesson.title)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundStyle(Palette.brassLight)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("lesson-title")
            Text(text(lesson))
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Palette.ivory)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lesson-text")
            switch progress.outcome {
            case .playing:
                EmptyView()
            case .done:
                BrassButton(title: progress.isLast ? "Finish" : "Next", systemImage: progress.isLast ? "checkmark" : "chevron.right", compact: true, action: next)
                    .accessibilityIdentifier("btn-lesson-next")
            case .tryAgain:
                BrassButton(title: "Try again", systemImage: "arrow.counterclockwise", compact: true, action: retry)
                    .accessibilityIdentifier("btn-lesson-retry")
            }
        }
        .padding(14)
        .woodPanel(corner: 16)
        .animation(.easeInOut(duration: 0.2), value: progress)
    }

    private func text(_ lesson: Lesson) -> String {
        switch progress.outcome {
        case .playing: lesson.text
        case .done: lesson.doneText
        case .tryAgain: "Not quite. " + lesson.text
        }
    }
}

/// Whose turn it is, and what just happened, carved on a wooden plaque.
struct StatusPlaque: View {
    let status: String
    let line: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(status)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Palette.ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("status")
            // Kicks, three sixes, no move: what just happened.
            if let line {
                Text(line)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Color(red: 0.95, green: 0.80, blue: 0.45))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("commentary")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .woodPanel(corner: 14)
    }
}

/// The wooden tray under the board: each player (pawn, name, tokens home) and the dice.
struct Tray: View {
    @Environment(LudoSession.self) private var session

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(session.state.players, id: \.self) { color in
                    PlayerRow(color: color, name: session.name(color), home: session.state.homeCount(color),
                              toMove: color == session.state.toMove && !session.state.isOver)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One scoreboard for VoiceOver, not a row each.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.state.players.map { "\(session.name($0)): \(session.state.homeCount($0)) of 4 home" }.joined(separator: ". "))
            .accessibilityIdentifier("scoreboard")
            DiceView()
        }
        .padding(12)
        .woodPanel(corner: 20)
    }
}

/// A player in the tray: their pawn, name and four marks for tokens home; brass when it is their turn.
struct PlayerRow: View {
    let color: PlayerColor
    let name: String
    let home: Int
    let toMove: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(Art.pawn(color)).resizable().scaledToFit().frame(height: 26)
            Text(name)
                .font(.system(.subheadline, design: .serif).weight(toMove ? .bold : .regular))
                .foregroundStyle(Palette.ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < home ? Palette.color(color) : .black.opacity(0.35))
                        .overlay(Circle().stroke(Palette.brass.opacity(0.7), lineWidth: 1))
                        .frame(width: 9, height: 9)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(toMove ? Palette.brass.opacity(0.28) : .clear))
        .overlay(Capsule().stroke(toMove ? Palette.brass : .clear, lineWidth: 1.5))
    }
}
