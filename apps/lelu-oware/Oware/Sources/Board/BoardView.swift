import SwiftUI
import SpriteKit
import OwareEngine

/// The SpriteKit board plus an invisible SwiftUI overlay that owns touch handling and
/// accessibility. Overlay positions come from the same `BoardLayout` the scene draws with.
struct BoardView: View {
    @Environment(GameSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @State private var scene = BoardScene()

    var onBlockedTap: ((String) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let layout = BoardLayout(size: geo.size)
            ZStack {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .accessibilityHidden(true)
                ForEach(0..<12, id: \.self) { index in
                    houseHitArea(index, layout: layout)
                }
                ForEach(Player.allCases, id: \.rawValue) { player in
                    let rect = layout.storeRect(player)
                    Color.clear
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityElement()
                        .accessibilityIdentifier("store-\(player.label)")
                        .accessibilityLabel("Store \(player.label)")
                        .accessibilityValue("\(session.state.store(of: player)) seeds")
                }
                // The plaques on the rails: whose row is whose, read out as well as drawn.
                ForEach(Player.allCases, id: \.rawValue) { player in
                    if let rect = layout.plaqueRect(player) {
                        Color.clear
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .accessibilityElement()
                            .accessibilityIdentifier("plaque-\(player.label)")
                            .accessibilityLabel(plaqueLabel(player))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("board")
            .accessibilityValue(session.isAnimating ? "Sowing" : "Still")
            .onAppear {
                scene.size = geo.size
                configureScene()
                session.attach(scene)
            }
            // Leaving the game mid-move: the board would never finish it otherwise.
            .onDisappear { scene.finishAnimation() }
            .onChange(of: geo.size) { _, newSize in scene.size = newSize }
            .onChange(of: settings.animationSpeed) { _, _ in configureScene() }
            .onChange(of: settings.showHouseLabels) { _, _ in configureScene() }
            .onChange(of: session.mode) { _, _ in configureScene() }
            .onChange(of: settings.soundEnabled) { _, _ in configureScene() }
            .onChange(of: settings.hapticsEnabled) { _, _ in configureScene() }
            .onChange(of: session.previewMove) { _, move in
                scene.showPreview(move.flatMap { session.state.preview($0) })
            }
            .onChange(of: settings.boardThemeID) { _, _ in configureScene() }
            .onChange(of: session.highlightedHouse) { _, house in scene.setHighlight(house: house) }
        }
    }

    /// "You: row A" or, in Nam-Nam, "Computer: 7 houses" (houses change hands there).
    private func plaqueLabel(_ player: Player) -> String {
        let name = session.sideName(player)
        guard session.state.rules.variant == .namNam else { return "\(name): row \(player.label)" }
        let held = session.state.houses(of: player).count
        return "\(name): \(held) \(held == 1 ? "house" : "houses")"
    }

    private func configureScene() {
        scene.theme = settings.boardTheme
        scene.setHighlight(house: session.highlightedHouse)
        scene.animationSpeed = settings.effectiveSpeed
        scene.calmMotion = settings.calmMotion
        let labelled = settings.labelsHouses(namesHouses: session.namesHouses)
        scene.showCounts = labelled
        scene.showHouseNames = labelled
        scene.sideNames = Player.allCases.map { session.sideName($0) }
        SoundPlayer.shared.enabled = settings.effectiveSound
        Haptics.shared.enabled = settings.effectiveHaptics
    }

    @ViewBuilder
    private func houseHitArea(_ index: Int, layout: BoardLayout) -> some View {
        let owner = session.state.owner(of: index)
        let notation = "\(index < 6 ? "A" : "B")\(index % 6 + 1)"
        let seeds = session.state.houses[index]
        let center = layout.houseCenter(index)
        let isTurn = session.state.sideToMove == owner && !session.state.isOver

        Circle()
            .fill(Color.clear)
            .contentShape(Circle())
            .frame(width: layout.houseRadius * 2.2, height: layout.houseRadius * 2.2)
            .position(center)
            .onTapGesture {
                scene.press(house: index)
                guard isTurn else { return }
                if let reason = session.reasonHouseIsBlocked(index) {
                    onBlockedTap?(reason)
                } else {
                    session.play(house: index)
                }
            }
            .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 30, perform: {}, onPressingChanged: { pressing in
                guard isTurn, session.humanToMove else { return }
                session.previewMove = pressing ? Move(player: owner, absoluteHouse: index) : nil
            })
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("house-\(notation)")
            .accessibilityLabel(owner == (index < 6 ? .south : .north) ? "House \(notation)" : "House \(notation), \(owner == .south ? "yours" : "theirs") this round")
            .accessibilityValue("\(seeds) seeds")
            .accessibilityHint(isTurn ? "Sow these seeds" : "")
            // VoiceOver's version of the long-press preview: where the last seed lands, what it takes.
            .accessibilityAction(named: "Preview this move") {
                guard isTurn, session.humanToMove,
                      let preview = session.state.preview(Move(player: owner, absoluteHouse: index)) else { return }
                GameSession.speak(GameSession.previewDescription(preview))
            }
    }
}
