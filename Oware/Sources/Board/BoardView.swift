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
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("board")
            .onAppear {
                scene.size = geo.size
                configureScene()
                session.attach(scene)
            }
            .onChange(of: geo.size) { _, newSize in scene.size = newSize }
            .onChange(of: settings.animationSpeed) { _, _ in configureScene() }
            .onChange(of: settings.showSeedCounts) { _, _ in configureScene() }
            .onChange(of: settings.soundEnabled) { _, _ in configureScene() }
            .onChange(of: settings.hapticsEnabled) { _, _ in configureScene() }
            .onChange(of: session.previewMove) { _, move in
                scene.showPreview(move.flatMap { session.state.preview($0) })
            }
            .onChange(of: settings.boardThemeID) { _, _ in configureScene() }
            .onChange(of: session.highlightedHouse) { _, house in scene.setHighlight(house: house) }
        }
    }

    private func configureScene() {
        scene.theme = settings.boardTheme
        scene.setHighlight(house: session.highlightedHouse)
        scene.animationSpeed = settings.effectiveSpeed
        scene.showCounts = settings.showSeedCounts
        SoundPlayer.shared.enabled = settings.soundEnabled
        Haptics.shared.enabled = settings.hapticsEnabled
    }

    @ViewBuilder
    private func houseHitArea(_ index: Int, layout: BoardLayout) -> some View {
        let owner: Player = Player.south.owns(index) ? .south : .north
        let relative = index - owner.houseRange.lowerBound
        let notation = "\(owner.label)\(relative + 1)"
        let seeds = session.state.houses[index]
        let center = layout.houseCenter(index)
        let isTurn = session.state.sideToMove == owner && !session.state.isOver

        Circle()
            .fill(Color.clear)
            .contentShape(Circle())
            .frame(width: layout.houseRadius * 2.2, height: layout.houseRadius * 2.2)
            .position(center)
            .onTapGesture {
                guard isTurn else { return }
                if let reason = session.reasonHouseIsBlocked(relative) {
                    onBlockedTap?(reason)
                } else {
                    session.play(house: relative)
                }
            }
            .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 30, perform: {}, onPressingChanged: { pressing in
                guard isTurn, session.humanToMove else { return }
                session.previewMove = pressing ? Move(player: owner, house: relative) : nil
            })
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("house-\(notation)")
            .accessibilityLabel("House \(notation)")
            .accessibilityValue("\(seeds) seeds")
            .accessibilityHint(isTurn ? "Sow these seeds" : "")
    }
}
