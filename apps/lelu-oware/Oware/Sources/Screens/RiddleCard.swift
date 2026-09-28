import SwiftUI
import OwareAI
import OwareEngine

/// The whole riddle, opened by tapping the riddle line under the board: what to find, the goal,
/// how to answer and a reminder of how captures work under the riddle's rules.
struct RiddleCard: View {
    let puzzle: Puzzle
    let number: Int?
    @Environment(\.dismiss) private var dismiss

    private var rules: RuleSet.Variant { puzzle.state.rules.variant }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rules == .namNam ? "Nam-Nam riddle" : "Abapa riddle")
                            .font(Theme.caption(13))
                            .foregroundStyle(Theme.gold)
                        Text(number.map { "\(puzzle.kind.title) · \($0)" } ?? puzzle.kind.title)
                            .font(Theme.title(28))
                            .foregroundStyle(Theme.ivory)
                            .accessibilityIdentifier("riddle-card-title")
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.body(17))
                        .tint(Theme.gold)
                        .accessibilityIdentifier("btn-riddle-done")
                }
                section("The riddle", Self.question(for: puzzle))
                section("Goal", Self.goal(for: puzzle))
                section("How to answer", "Your houses are A1 to A6 (their names are shown in gold on the board). Tap the house you would sow from. A wrong answer leaves the board as it was; tap Reset to look again.")
                section(rules == .namNam ? "Nam-Nam captures" : "Abapa captures", Self.captureReminder(rules))
            }
            .padding(24)
        }
        .background(Theme.ember.ignoresSafeArea())
    }

    private func section(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(Theme.body(15).weight(.semibold))
                .foregroundStyle(Theme.goldLight)
            Text(text)
                .font(Theme.body(17))
                .foregroundStyle(Theme.ivory)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    static func question(for puzzle: Puzzle) -> String {
        switch puzzle.kind {
        case .captureInOne: "Find the one move that captures the most seeds right now."
        case .captureInTwo: "Find a first move that sets up a capture. Whatever the other player replies, your next move can still take the seeds."
        case .escapeTheTrap: "The other player is threatening to capture. Only one move keeps your seeds safe from their best reply. Find it."
        case .feedOrLose: "The other side has no seeds, so you must give them some. Several moves feed them, but only one does it without handing seeds back. Find it."
        case .winInOne: "One move ends the game in your favour. Find it."
        }
    }

    static func goal(for puzzle: Puzzle) -> String {
        let seeds = "\(puzzle.target) seed\(puzzle.target == 1 ? "" : "s")"
        switch puzzle.kind {
        case .captureInOne: return "Capture \(seeds) with a single move."
        case .captureInTwo: return "Be sure of \(seeds) within your next two moves."
        case .escapeTheTrap: return "Keep \(seeds) out of the other player's reach."
        case .feedOrLose: return "Feed them and keep \(seeds) safe."
        case .winInOne: return "Win the game this move."
        }
    }

    static func captureReminder(_ rules: RuleSet.Variant) -> String {
        switch rules {
        case .namNam:
            "Keep sowing while your last seed lands among other seeds. A house on your side that reaches four is yours at any point. A house on their side is yours only if your last seed makes it four."
        case .abapa:
            "Your turn ends where your last seed lands. If it lands on their side and makes two or three, you take it, and any houses just before it that also hold two or three."
        }
    }
}

/// The whole lesson step, opened by tapping the lesson line under the board.
struct LessonCard: View {
    let step: Tutorial.Step
    let number: Int
    let count: Int
    let done: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lesson \(number) of \(count)")
                            .font(Theme.caption(13))
                            .foregroundStyle(Theme.gold)
                        Text(step.title)
                            .font(Theme.title(28))
                            .foregroundStyle(Theme.ivory)
                            .accessibilityIdentifier("lesson-card-title")
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.body(17))
                        .tint(Theme.gold)
                        .accessibilityIdentifier("btn-lesson-done")
                }
                Text(step.prompt)
                    .font(Theme.body(18))
                    .foregroundStyle(Theme.ivory)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lesson-card-prompt")
                if done, let after = step.afterText {
                    Text(after)
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.goldLight)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let move = step.requiredMove, !done {
                    Text("Tap the glowing house, \(move.notation).")
                        .font(Theme.caption(15))
                        .foregroundStyle(Theme.ivoryDim)
                }
            }
            .padding(24)
        }
        .background(Theme.ember.ignoresSafeArea())
    }
}
