import SpriteKit
import OwareEngine

/// Draws the board and animates moves. Rendering only: touches and accessibility live in the
/// SwiftUI overlay (`BoardView`), positioned by the same `BoardLayout`.
@MainActor
final class BoardScene: SKScene, BoardAnimator {
    /// 1 = normal; larger = faster; >= 100 = instant. (SKNode already has `speed`.)
    var animationSpeed: Double = 1
    var showCounts = true { didSet { countLabels.forEach { $0.isHidden = !showCounts } } }
    var sound: SoundPlayer? = .shared
    var haptics: Haptics? = .shared

    private var layout = BoardLayout(size: CGSize(width: 390, height: 300))
    private let boardNode = SKSpriteNode()
    private let boardShadow = SKShapeNode()
    private var rimNodes: [SKSpriteNode] = []
    private var houseNodes: [SKSpriteNode] = []
    private let pitTexture = SKTexture(imageNamed: "pit")
    private let seedTextures: [SKTexture] = (1...8).map { SKTexture(imageNamed: "seed\($0)") }
    private var lastBoardSize = CGSize.zero
    private var countLabels: [SKLabelNode] = []
    private var storeNodes: [SKSpriteNode] = []
    private var storeLabels: [SKLabelNode] = []
    private var seedsInHouse: [[SKNode]] = Array(repeating: [], count: 12)
    private var seedsInStore: [[SKNode]] = [[], []]
    private var hand: [SKNode] = []
    private let seedLayer = SKNode()
    private let previewLayer = SKNode()
    private let glowLayer = SKNode()
    private var current = GameState.initial
    private var built = false

    override init() {
        super.init(size: CGSize(width: 390, height: 300))
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.preferredFramesPerSecond = 120
        if !built { build() }
        relayout()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard built else { return }
        relayout()
    }

    // MARK: - Building

    private func build() {
        built = true
        boardShadow.lineWidth = 0
        boardShadow.fillColor = UIColor(white: 0, alpha: 0.55)
        boardShadow.zPosition = -2
        addChild(boardShadow)
        boardNode.zPosition = -1
        addChild(boardNode)
        for _ in 0..<2 {
            let rim = SKSpriteNode(texture: SKTexture(imageNamed: "rim"))
            rim.alpha = 0.85
            rim.zPosition = 0
            addChild(rim)
            rimNodes.append(rim)
        }
        for i in 0..<12 {
            let house = SKSpriteNode(texture: pitTexture)
            house.zPosition = 1
            addChild(house)
            houseNodes.append(house)

            let label = SKLabelNode(fontNamed: "Georgia")
            label.fontColor = UIColor(red: 0.92, green: 0.85, blue: 0.72, alpha: 0.55)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 5
            addChild(label)
            countLabels.append(label)
            _ = i
        }
        for _ in 0..<2 {
            let store = SKSpriteNode(texture: pitTexture)
            store.zPosition = 1
            addChild(store)
            storeNodes.append(store)

            let label = SKLabelNode(fontNamed: "Georgia")
            label.fontColor = UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.55)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 2   // behind the seeds: a quiet numeral in the bowl
            addChild(label)
            storeLabels.append(label)
        }
        glowLayer.zPosition = 2
        addChild(glowLayer)
        seedLayer.zPosition = 3
        addChild(seedLayer)
        previewLayer.zPosition = 4
        addChild(previewLayer)
    }

    private func relayout() {
        layout = BoardLayout(size: size)
        let r = layout.sk(layout.boardRect)
        if lastBoardSize != r.size {
            lastBoardSize = r.size
            boardNode.texture = BoardTexture.make(size: r.size, cornerRadius: layout.cell * 0.5)
            boardNode.size = r.size
        }
        boardNode.position = CGPoint(x: r.midX, y: r.midY)
        let shadowRect = r.offsetBy(dx: layout.cell * 0.06, dy: -layout.cell * 0.12).insetBy(dx: -layout.cell * 0.04, dy: -layout.cell * 0.04)
        boardShadow.path = CGPath(roundedRect: shadowRect, cornerWidth: layout.cell * 0.55, cornerHeight: layout.cell * 0.55, transform: nil)

        // Carved Adinkra band along the two long edges.
        let bandThickness = layout.cell * 0.2
        let inset = layout.cell * 0.07
        for (k, rim) in rimNodes.enumerated() {
            switch layout.orientation {
            case .horizontal:
                rim.zRotation = 0
                rim.size = CGSize(width: r.width - inset * 2, height: bandThickness)
                rim.position = CGPoint(x: r.midX, y: k == 0 ? r.maxY - inset - bandThickness / 2 : r.minY + inset + bandThickness / 2)
            case .vertical:
                rim.zRotation = .pi / 2
                rim.size = CGSize(width: r.height - inset * 2, height: bandThickness)
                rim.position = CGPoint(x: k == 0 ? r.minX + inset + bandThickness / 2 : r.maxX - inset - bandThickness / 2, y: r.midY)
            }
        }

        for i in 0..<12 {
            let c = layout.sk(layout.houseCenter(i))
            let radius = layout.houseRadius
            houseNodes[i].position = c
            houseNodes[i].size = CGSize(width: radius * 2.15, height: radius * 1.9)
            countLabels[i].fontSize = max(10, layout.cell * 0.2)
            countLabels[i].position = layout.sk(layout.countLabelPoint(i))
        }
        for p in Player.allCases {
            let rect = layout.sk(layout.storeRect(p))
            storeNodes[p.rawValue].position = CGPoint(x: rect.midX, y: rect.midY)
            storeNodes[p.rawValue].size = CGSize(width: rect.width * 1.08, height: rect.height * 1.06)
            storeLabels[p.rawValue].fontSize = max(14, layout.cell * 0.5)
            storeLabels[p.rawValue].position = layout.sk(layout.storeLabelPoint(p))
        }
        render(current)
    }

    // MARK: - Seeds

    private func makeSeed() -> SKNode {
        let r = layout.seedRadius
        let body = SKSpriteNode(texture: seedTextures.randomElement()!)
        body.size = CGSize(width: r * 2.6, height: r * 2.6)
        body.zRotation = CGFloat.random(in: -.pi ... .pi)
        let shadow = SKShapeNode(ellipseIn: CGRect(x: -r * 0.95, y: -r * 0.8, width: r * 1.9, height: r * 1.6))
        shadow.fillColor = UIColor(white: 0, alpha: 0.35)
        shadow.lineWidth = 0
        shadow.position = CGPoint(x: r * 0.18, y: -r * 0.22)
        shadow.zPosition = -0.5
        shadow.zRotation = -body.zRotation
        body.addChild(shadow)
        return body
    }

    private func settle(_ seed: SKNode, at point: CGPoint, duration: TimeInterval) -> SKAction {
        let target = layout.sk(point)
        guard duration > 0 else { return SKAction.move(to: target, duration: 0) }
        let dx = target.x - seed.position.x
        let dy = target.y - seed.position.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let path = CGMutablePath()
        path.move(to: seed.position)
        let control = CGPoint(x: (seed.position.x + target.x) / 2, y: max(seed.position.y, target.y) + min(distance * 0.35, layout.cell * 0.9))
        path.addQuadCurve(to: target, control: control)
        let fly = SKAction.follow(path, asOffset: false, orientToPath: false, duration: duration)
        fly.timingMode = .easeInEaseOut
        let land = SKAction.sequence([
            SKAction.scale(to: 1.18, duration: duration * 0.12),
            SKAction.scale(to: 1.0, duration: duration * 0.18),
        ])
        return SKAction.sequence([fly, land])
    }

    /// Instantly make the scene match `state`. Safe to call before the scene is presented:
    /// the state is remembered and drawn once `didMove(to:)` builds the nodes.
    func render(_ state: GameState) {
        current = state
        guard built else { return }
        hand.forEach { $0.removeFromParent() }
        hand = []
        seedLayer.removeAllChildren()
        previewLayer.removeAllChildren()
        glowLayer.removeAllChildren()
        seedsInHouse = Array(repeating: [], count: 12)
        seedsInStore = [[], []]
        for i in 0..<12 {
            for k in 0..<state.houses[i] {
                let seed = makeSeed()
                seed.position = layout.sk(layout.seedSlot(in: i, index: k))
                seedLayer.addChild(seed)
                seedsInHouse[i].append(seed)
            }
        }
        for p in Player.allCases {
            for k in 0..<state.stores[p.rawValue] {
                let seed = makeSeed()
                seed.position = layout.sk(layout.storeSlot(p, index: k))
                seedLayer.addChild(seed)
                seedsInStore[p.rawValue].append(seed)
            }
        }
        updateLabels(state)
    }

    private func updateLabels(_ state: GameState) {
        for i in 0..<12 {
            countLabels[i].text = state.houses[i] == 0 ? "" : "\(state.houses[i])"
            countLabels[i].isHidden = !showCounts
        }
        for p in Player.allCases {
            storeLabels[p.rawValue].text = "\(state.stores[p.rawValue])"
        }
    }

    // MARK: - Animation

    private var isInstant: Bool { animationSpeed >= 100 || view == nil || isPaused }

    private func wait(_ seconds: TimeInterval) async {
        guard seconds > 0, !isInstant else { return }
        await run(SKAction.wait(forDuration: seconds / animationSpeed))
    }

    private func run(_ action: SKAction, on node: SKNode? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            (node ?? self).run(action) { continuation.resume() }
        }
    }

    func animate(events: [MoveEvent], from before: GameState, to after: GameState) async {
        if isInstant {
            render(after)
            playEndSounds(after)
            return
        }
        // Start from a clean, exact rendering of the position before the move.
        render(before)
        var working = before
        let sowCount = events.filter { if case .sow = $0 { return true } else { return false } }.count
        let perSeed = min(0.17, max(0.07, 2.2 / Double(max(sowCount, 1))))

        for event in events {
            switch event {
            case let .pickUp(house, _):
                let seeds = seedsInHouse[house]
                seedsInHouse[house] = []
                hand = seeds
                working.houses[house] = 0
                updateLabels(working)
                sound?.play(.pickUp, volume: 0.8)
                haptics?.pickUp()
                let target = layout.handPoint(for: house)
                for (k, seed) in seeds.enumerated() {
                    let angle = Double(k) * 2.399963
                    let r = layout.seedRadius * 1.1 * CGFloat(Double(k).squareRoot())
                    let spread = CGPoint(x: target.x + r * CGFloat(cos(angle)), y: target.y + r * CGFloat(sin(angle)))
                    let move = SKAction.move(to: layout.sk(spread), duration: 0.16 / animationSpeed)
                    move.timingMode = .easeOut
                    seed.zPosition = 10
                    seed.run(move, withKey: "move")
                }
                await wait(0.2)

            case let .sow(house, count):
                guard let seed = hand.popLast() else { continue }
                working.houses[house] = count
                let slot = layout.seedSlot(in: house, index: count - 1)
                let action = settle(seed, at: slot, duration: perSeed / animationSpeed)
                seedsInHouse[house].append(seed)
                seed.run(action, withKey: "sow")
                await wait(perSeed * 0.85)
                seed.zPosition = 0
                updateLabels(working)
                sound?.play(.tick, volume: 0.7)
                haptics?.seedDrop()

            case .skipOrigin:
                await wait(0.05)

            case let .capture(house, seeds, by):
                await pulse(house: house, color: UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.9))
                let taken = seedsInHouse[house]
                seedsInHouse[house] = []
                working.houses[house] = 0
                working.stores[by.rawValue] += seeds
                sound?.play(.capture)
                haptics?.capture()
                for (k, seed) in taken.enumerated() {
                    let index = seedsInStore[by.rawValue].count
                    seedsInStore[by.rawValue].append(seed)
                    seed.zPosition = 10
                    let delay = SKAction.wait(forDuration: Double(k) * 0.03 / animationSpeed)
                    seed.run(SKAction.sequence([delay, settle(seed, at: layout.storeSlot(by, index: index), duration: 0.38 / animationSpeed)]), withKey: "capture")
                }
                await wait(0.42)
                updateLabels(working)

            case let .grandSlamForfeited(_, houses):
                for h in houses {
                    Task { await self.pulse(house: h, color: UIColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 0.8)) }
                }
                await wait(0.5)

            case let .sweep(player, _):
                var moved = 0
                for house in player.houseRange {
                    let taken = seedsInHouse[house]
                    seedsInHouse[house] = []
                    working.houses[house] = 0
                    for seed in taken {
                        let index = seedsInStore[player.rawValue].count
                        seedsInStore[player.rawValue].append(seed)
                        seed.zPosition = 10
                        let delay = SKAction.wait(forDuration: Double(moved) * 0.02 / animationSpeed)
                        seed.run(SKAction.sequence([delay, settle(seed, at: layout.storeSlot(player, index: index), duration: 0.45 / animationSpeed)]), withKey: "sweep")
                        moved += 1
                    }
                }
                working.stores = after.stores
                await wait(0.6)
                updateLabels(working)

            case .gameOver:
                break
            }
        }
        // Snap to the exact final position (guards against any drift).
        render(after)
        playEndSounds(after)
    }

    private func playEndSounds(_ state: GameState) {
        guard let outcome = state.outcome else { return }
        switch outcome {
        case .win: sound?.play(.win)
        case .draw: sound?.play(.win, volume: 0.6)
        }
    }

    private func pulse(house: Int, color: UIColor) async {
        let c = layout.sk(layout.houseCenter(house))
        let radius = layout.houseRadius
        let glow = SKShapeNode(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius * 0.86, width: radius * 2, height: radius * 1.72))
        glow.fillColor = color.withAlphaComponent(0.25)
        glow.strokeColor = color
        glow.lineWidth = 1.5
        glow.alpha = 0
        glowLayer.addChild(glow)
        let sequence = SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.12 / animationSpeed),
            SKAction.wait(forDuration: 0.18 / animationSpeed),
            SKAction.fadeOut(withDuration: 0.3 / animationSpeed),
            SKAction.removeFromParent(),
        ])
        await run(sequence, on: glow)
    }

    // MARK: - Preview

    /// Ghost the sowing path and landing house for a long-pressed move.
    func showPreview(_ preview: MovePreview?) {
        previewLayer.removeAllChildren()
        guard built, let preview else { return }
        var counts = current.houses
        counts[preview.move.absoluteIndex] = 0
        for house in preview.path {
            counts[house] += 1
            let dot = SKShapeNode(circleOfRadius: layout.seedRadius * 0.8)
            dot.fillColor = UIColor(red: 0.92, green: 0.85, blue: 0.72, alpha: 0.35)
            dot.lineWidth = 0
            dot.position = layout.sk(layout.seedSlot(in: house, index: counts[house] - 1))
            previewLayer.addChild(dot)
        }
        let c = layout.sk(layout.houseCenter(preview.landingHouse))
        let radius = layout.houseRadius * 1.08
        let ring = SKShapeNode(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius * 0.86, width: radius * 2, height: radius * 1.72))
        ring.fillColor = .clear
        ring.strokeColor = UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.9)
        ring.lineWidth = 1.5
        previewLayer.addChild(ring)
        for house in preview.captures {
            let cc = layout.sk(layout.houseCenter(house))
            let r2 = layout.houseRadius * 1.0
            let capture = SKShapeNode(ellipseIn: CGRect(x: cc.x - r2, y: cc.y - r2 * 0.86, width: r2 * 2, height: r2 * 1.72))
            capture.fillColor = UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.18)
            capture.lineWidth = 0
            previewLayer.addChild(capture)
        }
    }
}
