import SwiftUI

/// The rules and the story of the game. Quiet, typographic, and honest about what is tradition
/// versus fact (every claim here is logged in docs/CULTURE_SOURCES.md).
struct HeritageView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case rules = "Rules", heritage = "Heritage"
        var id: String { rawValue }
    }

    let goBack: () -> Void
    @State private var tab: Tab = .rules

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
                HStack(spacing: 22) {
                    ForEach(Tab.allCases) { t in
                        Button(t.rawValue) { tab = t }
                            .buttonStyle(.plain)
                            .font(Theme.caption(15))
                            .foregroundStyle(tab == t ? Theme.gold : Theme.ivoryDim)
                            .underline(tab == t, color: Theme.gold)
                            .accessibilityIdentifier("tab-\(t.rawValue.lowercased())")
                    }
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .rules: rules
                    case .heritage: heritage
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(Theme.title(30)).foregroundStyle(Theme.ivory).padding(.top, 8)
    }
    private func sub(_ text: String) -> some View {
        Text(text).font(Theme.body(20)).foregroundStyle(Theme.gold).padding(.top, 6)
    }
    private func para(_ text: String) -> some View {
        Text(text).font(Theme.body(17)).foregroundStyle(Theme.ivory.opacity(0.88)).lineSpacing(4)
    }
    private func note(_ text: String) -> some View {
        Text(text).font(Theme.caption()).foregroundStyle(Theme.ivoryDim).lineSpacing(3)
    }

    @ViewBuilder private var rules: some View {
        heading("How to play")
            .accessibilityIdentifier("rules-title")
        para("Oware is played on two rows of six houses with 48 seeds, four in each house. You own the row nearest you. The aim is to capture more seeds than the other player: 25 wins, 24 each is a draw.")
        sub("Sowing")
        para("On your turn, pick up all the seeds in one of your houses and drop them one by one into the following houses, moving anticlockwise: along your row to the right, then along the far row to the left. Never sow into the stores, and if a house holds 12 or more seeds, skip the house you started from on each lap so it always ends empty.")
        sub("Capturing")
        para("If your last seed lands in the other player's row and brings that house to exactly two or three seeds, you capture them. Then look at the house before it: if it also holds two or three, capture that too, and keep going backwards until you reach a house that does not, or the end of the row. You never capture in your own row.")
        sub("Leave them something")
        para("A move that would capture every seed on the other side is allowed, but the capture is forfeited: the seeds stay. And if the other row is empty at the start of your turn, you must play a move that gives them seeds if you can. If no move can, you keep the seeds on your side and the game ends.")
        sub("Ending")
        para("The game ends when someone has 25 seeds, when the board is empty, when a player cannot be fed, or when the position keeps repeating, in which case each player keeps the seeds on their own side.")
        note("These are the Abapa rules used in adult and tournament play. The app's settings offer the other common grand-slam conventions.")
    }

    @ViewBuilder private var heritage: some View {
        heading("Ɔware")
            .padding(.leading, 8) // the open-O glyph has a negative side bearing in the serif face
            .accessibilityIdentifier("heritage-title")
        Image("hero")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.vertical, 4)
            .accessibilityLabel("A carved oware board with nickernut seeds")
        para("Oware is the national game of the Asante and Bono peoples of Ghana, and it is played under many names across West Africa and the Caribbean: awale in Côte d'Ivoire, ayo among the Yoruba, warri in Antigua, adji among the Ewe and awele among the Ga.")
        sub("The name")
        para("In Twi, ware means to marry. It is said that a man and a woman once played so endlessly that they married so they could keep playing. Another tradition credits the Asantehene Opoku Ware I, who ruled in the early eighteenth century, with sitting quarrelling couples down to play until they were reconciled.")
        sub("The board")
        para("Carvers in Ahwiaa, near Kumasi, shape boards from a single block of osese wood with an adze, knives and gouges, then stain them with red and black dye and finish them with wax. Many boards fold on hinges and carry the seeds inside, with an Adinkra symbol or an elephant carved on the lid. The seeds are oware aba, the grey, glossy nickernuts of the bonduc shrub.")
        sub("Playing together")
        para("Oware is famously social. Onlookers are expected to advise, argue and laugh, and the game has long been used to teach counting and foresight to children. In this app, Nana is that voice at your shoulder.")
        sub("Words you will see")
        para("Akwaaba: welcome. Medaase: thank you. Ayekoo: well done. Nana: an elder, a title of respect.")
        note("Where this app says 'it is said', it means tradition rather than documented history. Sources are listed in the project's cultural sources log.")
    }
}
