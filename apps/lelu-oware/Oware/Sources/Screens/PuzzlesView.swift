import SwiftUI
import OwareAI

struct PuzzlesView: View {
    @Environment(PuzzleLibrary.self) private var library
    @Environment(GameSession.self) private var session
    let goBack: () -> Void
    let startPuzzle: (Puzzle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ivoryDim)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("btn-back")
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Ananse's riddles")
                        .font(Theme.title(34))
                        .foregroundStyle(Theme.ivory)
                        .accessibilityIdentifier("puzzles-title")

                    if let daily = library.daily {
                        QuietButton(title: "Today's riddle", subtitle: library.dailySolved ? "solved" : daily.kind.title, prominent: !library.dailySolved) {
                            startPuzzle(daily)
                        }
                        .accessibilityIdentifier("btn-daily")
                    }

                    ForEach(Puzzle.Kind.allCases, id: \.rawValue) { kind in
                        let list = library.puzzles(of: kind)
                        if !list.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(kind.title)
                                        .font(Theme.body(20))
                                        .foregroundStyle(Theme.ivory)
                                    Text("\(library.solvedCount(of: kind)) of \(list.count)")
                                        .font(Theme.caption())
                                        .foregroundStyle(Theme.ivoryDim)
                                }
                                Text(kind.instruction)
                                    .font(Theme.caption())
                                    .foregroundStyle(Theme.ivoryDim)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                                    ForEach(Array(list.enumerated()), id: \.element.id) { index, puzzle in
                                        Button { startPuzzle(puzzle) } label: {
                                            Text("\(index + 1)")
                                                .font(Theme.caption(15))
                                                .foregroundStyle(library.isSolved(puzzle) ? Theme.night : Theme.ivory)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 40)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(library.isSolved(puzzle) ? Theme.gold : Theme.ember)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("puzzle-\(puzzle.id)")
                                        .accessibilityLabel("\(kind.title) \(index + 1)\(library.isSolved(puzzle) ? ", solved" : "")")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
