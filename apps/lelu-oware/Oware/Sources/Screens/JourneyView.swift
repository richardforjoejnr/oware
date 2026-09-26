import SwiftUI

struct JourneyView: View {
    @Environment(JourneyProgress.self) private var progress
    let goBack: () -> Void
    let startMatch: (Int, Int) -> Void

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
                Text("\(progress.totalStars) ★")
                    .font(Theme.caption(15))
                    .foregroundStyle(Theme.gold)
                    .padding(.trailing, 16)
                    .accessibilityIdentifier("journey-stars")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("Journey")
                        .font(Theme.title(34))
                        .foregroundStyle(Theme.ivory)
                        .accessibilityIdentifier("journey-title")

                    ForEach(Array(Journey.chapters.enumerated()), id: \.element.id) { index, chapter in
                        let unlocked = progress.isReached(chapterIndex: index)
                        let finished = chapter.opponents.allSatisfy { progress.stars(for: $0) > 0 }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 14) {
                                ZStack(alignment: .bottomTrailing) {
                                    Image("chapter-\(chapter.id)")
                                        .resizable()
                                        .scaledToFit()
                                        .saturation(unlocked ? 1 : 0.15)
                                        .opacity(unlocked ? 1 : 0.55)
                                    if !unlocked {
                                        Image("chapter-locked").resizable().scaledToFit().frame(width: 30, height: 30)
                                    } else if finished {
                                        Image("chapter-done").resizable().scaledToFit().frame(width: 30, height: 30)
                                    }
                                }
                                .frame(width: 84, height: 84)
                                .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title)
                                        .font(Theme.body(22))
                                        .foregroundStyle(unlocked ? Theme.ivory : Theme.ivoryDim.opacity(0.6))
                                    Text(chapter.region)
                                        .font(Theme.caption())
                                        .foregroundStyle(Theme.ivoryDim)
                                }
                                Spacer()
                            }
                            Text(chapter.blurb)
                                .font(Theme.caption(14))
                                .foregroundStyle(Theme.ivoryDim)
                                .lineSpacing(3)
                            if unlocked {
                                ForEach(Array(chapter.opponents.enumerated()), id: \.element.id) { oIndex, opponent in
                                    Button { startMatch(index, oIndex) } label: {
                                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                                            Text(opponent.name)
                                                .font(Theme.body(18))
                                                .foregroundStyle(Theme.ivory)
                                            Text(opponent.role)
                                                .font(Theme.caption())
                                                .foregroundStyle(Theme.ivoryDim)
                                            Spacer()
                                            Text(String(repeating: "★", count: progress.stars(for: opponent)) + String(repeating: "☆", count: 3 - progress.stars(for: opponent)))
                                                .font(Theme.caption(14))
                                                .foregroundStyle(Theme.gold)
                                        }
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("opponent-\(opponent.id)")
                                    .accessibilityLabel("\(opponent.name), \(opponent.role), \(progress.stars(for: opponent)) stars")
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
