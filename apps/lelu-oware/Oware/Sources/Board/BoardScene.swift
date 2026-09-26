import SpriteKit
import SwiftUI
import OwareEngine

/// Draws the board and animates moves. Rendering only: touches and accessibility live in the
/// SwiftUI overlay (`BoardView`), positioned by the same `BoardLayout`.
@MainActor
final class BoardScene: SKScene, BoardAnimator {
    /// 1 = normal; larger = faster; >= 100 = instant. (SKNode already has `speed`.)
    var animationSpeed: Double = 1
    var showCounts = true { didSet { (countLabels + countShadows).forEach { $0.isHidden = !showCounts } } }
    var sound: SoundPlayer? = .shared
    var haptics: Haptics? = .shared
    var theme: BoardTheme = .heritage { didSet { if built { applyTheme() } } }
    private let highlightLayer = SKNode()

    private var layout = BoardLayout(size: CGSize(width: 390, height: 300))
    private let boardNode = SKSpriteNode()
    private let boardShadow = SKShapeNode()
    private let boardShadowSoft = SKShapeNode()
    private var lastBandSizes: [CGSize] = []
    private var lastScorched = false
    private let rusticLayer = SKNode()
    /// Seeds being carried while sowing; hovers over the board between houses.
    private let handNode = SKNode()
    private var lastFrameTexture = ""
    private var rimNodes: [SKSpriteNode] = []
    private var houseNodes: [SKSpriteNode] = []
    private let pitTexture = SKTexture(imageNamed: "pit")
    private let pitHewnTexture = SKTexture(imageNamed: "pitHewn")
    private let troughTexture = SKTexture(imageNamed: "trough")
    private let seedTextures: [SKTexture] = (1...8).map { SKTexture(imageNamed: "seed\($0)") }
    private var lastBoardSize = CGSize.zero
    private var countLabels: [SKLabelNode] = []
    private var countShadows: [SKLabelNode] = []
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
    private var animating = false

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
        boardShadowSoft.lineWidth = 0
        boardShadowSoft.fillColor = UIColor(white: 0, alpha: 0.28)
        boardShadowSoft.zPosition = -3
        addChild(boardShadowSoft)
        boardShadow.lineWidth = 0
        boardShadow.fillColor = UIColor(white: 0, alpha: 0.5)
        boardShadow.zPosition = -2
        addChild(boardShadow)
        boardNode.zPosition = -1
        addChild(boardNode)
        for _ in 0..<4 {
            let rim = SKSpriteNode()
            rim.zPosition = 0
            addChild(rim)
            rimNodes.append(rim)
        }
        rusticLayer.zPosition = 0.5
        addChild(rusticLayer)

        handNode.zPosition = 8
        addChild(handNode)
        for i in 0..<12 {
            let house = SKSpriteNode(texture: pitTexture)
            house.zPosition = 1
            addChild(house)
            houseNodes.append(house)

            let shadow = SKLabelNode(fontNamed: "Georgia")
            shadow.fontColor = UIColor(red: 0.08, green: 0.04, blue: 0.02, alpha: 0.85)
            shadow.verticalAlignmentMode = .center
            shadow.horizontalAlignmentMode = .center
            shadow.zPosition = 4.9
            addChild(shadow)
            countShadows.append(shadow)
            let label = SKLabelNode(fontNamed: "Georgia")
            label.fontColor = UIColor(red: 0.96, green: 0.90, blue: 0.78, alpha: 0.9)
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
            label.fontColor = UIColor(red: 0.93, green: 0.89, blue: 0.82, alpha: 0.9)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 5   // at the bowl's end, clear of the seeds
            addChild(label)
            storeLabels.append(label)
        }
        glowLayer.zPosition = 2
        addChild(glowLayer)
        seedLayer.zPosition = 3
        addChild(seedLayer)
        previewLayer.zPosition = 4
        addChild(previewLayer)
        highlightLayer.zPosition = 4.5
        addChild(highlightLayer)
        applyTheme()
    }

    private func applyTheme() {
        boardNode.color = theme.uiTint
        boardNode.colorBlendFactor = theme.tintStrength
        rusticLayer.isHidden = !theme.rustic
        if !animating, lastScorched != theme.rustic || lastFrameTexture != theme.frameTexture {
            lastScorched = theme.rustic
            lastFrameTexture = theme.frameTexture
            lastBoardSize = .zero
            lastBandSizes = []
            relayout()
            return
        }
        for rim in rimNodes {
            rim.isHidden = !theme.carvedFrame
            rim.alpha = theme.rimOpacity
            rim.color = theme.uiTint
            rim.colorBlendFactor = theme.tintStrength * 0.6
        }
        for house in houseNodes {
            house.texture = theme.rustic ? pitHewnTexture : pitTexture
        }
        for store in storeNodes {
            store.texture = theme.rustic ? pitHewnTexture : troughTexture
        }
        for house in houseNodes + storeNodes {
            house.color = theme.uiTint
            house.colorBlendFactor = theme.tintStrength * 0.8
        }
    }

    /// A slow gold pulse on one house (used by the lesson to say "tap this one").
    func highlight(house: Int?) {
        highlightLayer.removeAllChildren()
        guard built, let house else { return }
        let c = layout.sk(layout.houseCenter(house))
        let radius = layout.houseRadius * 1.12
        let ring = SKShapeNode(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius * 0.86, width: radius * 2, height: radius * 1.72))
        ring.fillColor = .clear
        ring.strokeColor = UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.95)
        ring.lineWidth = 2
        ring.glowWidth = 3
        // Pulse around the ring's own centre: offset the ring inside a holder placed at the house.
        let holder = SKNode()
        holder.position = c
        ring.position = CGPoint(x: -c.x, y: -c.y)
        holder.addChild(ring)
        highlightLayer.addChild(holder)
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.06, duration: 0.9), SKAction.fadeAlpha(to: 0.55, duration: 0.9)]),
            SKAction.group([SKAction.scale(to: 1.0, duration: 0.9), SKAction.fadeAlpha(to: 1.0, duration: 0.9)]),
        ]))
        holder.run(pulse, withKey: "pulse")
    }

    private func relayout() {
        layout = BoardLayout(size: size)
        let r = layout.sk(layout.boardRect)
        if lastBoardSize != r.size {
            lastBoardSize = r.size
            boardNode.texture = BoardTexture.make(size: r.size, cornerRadius: layout.cornerRadius, scorched: theme.rustic,
                                                  wood: theme.rustic ? "woodHewn" : "wood")
            boardNode.size = r.size
        }
        boardNode.position = CGPoint(x: r.midX, y: r.midY)
        let shadowRect = r.offsetBy(dx: layout.cell * 0.03, dy: -layout.cell * 0.06).insetBy(dx: -layout.cell * 0.02, dy: -layout.cell * 0.02)
        boardShadow.path = CGPath(roundedRect: shadowRect, cornerWidth: layout.cell * 0.55, cornerHeight: layout.cell * 0.55, transform: nil)
        let softRect = r.offsetBy(dx: layout.cell * 0.06, dy: -layout.cell * 0.14).insetBy(dx: -layout.cell * 0.08, dy: -layout.cell * 0.08)
        boardShadowSoft.path = CGPath(roundedRect: softRect, cornerWidth: layout.cell * 0.7, cornerHeight: layout.cell * 0.7, transform: nil)

        // Carved Kente relief framing all four edges.
        let bandThickness = layout.cell * 0.30
        let inset = layout.cell * 0.04
        let longSide = layout.orientation == .horizontal ? r.width - inset * 2 : r.height - inset * 2
        let shortSide = (layout.orientation == .horizontal ? r.height : r.width) - inset * 2 - bandThickness * 2
        let sizes = [CGSize(width: longSide, height: bandThickness), CGSize(width: longSide, height: bandThickness),
                     CGSize(width: shortSide, height: bandThickness), CGSize(width: shortSide, height: bandThickness)]
        if sizes != lastBandSizes {
            lastBandSizes = sizes
            for (k, rim) in rimNodes.enumerated() {
                rim.texture = BoardTexture.band(named: theme.frameTexture, length: sizes[k].width, thickness: sizes[k].height)
                rim.size = sizes[k]
            }
        }
        let half = bandThickness / 2
        switch layout.orientation {
        case .horizontal:
            rimNodes[0].zRotation = 0;        rimNodes[0].position = CGPoint(x: r.midX, y: r.maxY - inset - half)
            rimNodes[1].zRotation = .pi;      rimNodes[1].position = CGPoint(x: r.midX, y: r.minY + inset + half)
            rimNodes[2].zRotation = .pi / 2;  rimNodes[2].position = CGPoint(x: r.minX + inset + half, y: r.midY)
            rimNodes[3].zRotation = -.pi / 2; rimNodes[3].position = CGPoint(x: r.maxX - inset - half, y: r.midY)
        case .vertical:
            rimNodes[0].zRotation = .pi / 2;  rimNodes[0].position = CGPoint(x: r.minX + inset + half, y: r.midY)
            rimNodes[1].zRotation = -.pi / 2; rimNodes[1].position = CGPoint(x: r.maxX - inset - half, y: r.midY)
            rimNodes[2].zRotation = 0;        rimNodes[2].position = CGPoint(x: r.midX, y: r.maxY - inset - half)
            rimNodes[3].zRotation = .pi;      rimNodes[3].position = CGPoint(x: r.midX, y: r.minY + inset + half)
        }

        buildRusticDetails(in: r)
        for i in 0..<12 {
            let c = layout.sk(layout.houseCenter(i))
            let radius = layout.houseRadius
            houseNodes[i].position = c
            houseNodes[i].size = theme.rustic ? CGSize(width: radius * 2.15, height: radius * 1.9) : CGSize(width: radius * 2.4, height: radius * 2.4)
            countLabels[i].fontSize = max(10, layout.cell * 0.2)
            countLabels[i].position = layout.sk(layout.countLabelPoint(i))
            countShadows[i].fontSize = countLabels[i].fontSize
            countShadows[i].position = CGPoint(x: countLabels[i].position.x + 0.7, y: countLabels[i].position.y - 0.9)
        }
        for p in Player.allCases {
            let rect = layout.sk(layout.storeRect(p))
            storeNodes[p.rawValue].position = CGPoint(x: rect.midX, y: rect.midY)
            if theme.rustic {
                storeNodes[p.rawValue].size = CGSize(width: rect.width * 1.08, height: rect.height * 1.06)
            } else {
                // The trough sprite keeps its own proportions (3.09:1); the layout's store rect is its bowl.
                let w = rect.width / BoardLayout.troughBowlFraction
                storeNodes[p.rawValue].size = CGSize(width: w, height: w / 3.09)
            }
            storeLabels[p.rawValue].fontSize = max(13, layout.cell * 0.3)
            storeLabels[p.rawValue].position = layout.sk(layout.storeLabelPoint(p))
        }
        if !animating { render(current) }
        applyTheme()
        highlight(house: highlightedHouse)
    }

    /// Two iron hinges on the fold between the rows and scratched cross-hatch marks between
    /// neighbouring hollows, as on the village boards the look is based on.
    private func buildRusticDetails(in board: CGRect) {
        rusticLayer.removeAllChildren()
        let cell = layout.cell
        let alongLength = layout.orientation == .vertical
        // Hinges at a third and two thirds of the length, on the centre line.
        for f in [CGFloat(0.34), CGFloat(0.66)] {
            let hinge = SKNode()
            let plateW = cell * 0.3, plateH = cell * 0.17
            let plate = SKShapeNode(rectOf: CGSize(width: plateW, height: plateH), cornerRadius: plateH * 0.18)
            plate.fillColor = UIColor(red: 0.36, green: 0.34, blue: 0.32, alpha: 1)
            plate.strokeColor = UIColor(red: 0.16, green: 0.14, blue: 0.12, alpha: 0.9)
            plate.lineWidth = 1
            hinge.addChild(plate)
            let knuckle = SKShapeNode(rectOf: CGSize(width: plateW * 0.14, height: plateH * 1.1), cornerRadius: plateW * 0.06)
            knuckle.fillColor = UIColor(red: 0.30, green: 0.28, blue: 0.26, alpha: 1)
            knuckle.lineWidth = 0
            hinge.addChild(knuckle)
            for sx in [-0.3, 0.3] {
                let screw = SKShapeNode(circleOfRadius: plateH * 0.14)
                screw.fillColor = UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1)
                screw.lineWidth = 0
                screw.position = CGPoint(x: plateW * CGFloat(sx), y: 0)
                hinge.addChild(screw)
            }
            let shadow = SKShapeNode(rectOf: CGSize(width: plateW * 1.08, height: plateH * 1.16), cornerRadius: plateH * 0.2)
            shadow.fillColor = UIColor(white: 0, alpha: 0.35)
            shadow.lineWidth = 0
            shadow.position = CGPoint(x: 1, y: -1.5)
            shadow.zPosition = -0.1
            hinge.addChild(shadow)
            if alongLength {
                hinge.position = CGPoint(x: board.midX, y: board.minY + board.height * f)
            } else {
                hinge.position = CGPoint(x: board.minX + board.width * f, y: board.midY)
                hinge.zRotation = .pi / 2
            }
            rusticLayer.addChild(hinge)
        }
        // Scratched hatch marks between neighbouring hollows in each row.
        let scratch = UIColor(red: 0.16, green: 0.10, blue: 0.05, alpha: 0.55)
        for player in Player.allCases {
            let houses = Array(player.houseRange)
            for k in 0..<(houses.count - 1) {
                let a = layout.sk(layout.houseCenter(houses[k])), b = layout.sk(layout.houseCenter(houses[k + 1]))
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let path = CGMutablePath()
                let len = cell * 0.16
                for i in -1...1 {
                    let o = CGFloat(i) * cell * 0.05
                    // two crossed sets of three short lines
                    path.move(to: CGPoint(x: mid.x - len + o, y: mid.y - len * 0.6))
                    path.addLine(to: CGPoint(x: mid.x + len * 0.4 + o, y: mid.y + len * 0.6))
                    path.move(to: CGPoint(x: mid.x - len * 0.4 + o, y: mid.y + len * 0.6))
                    path.addLine(to: CGPoint(x: mid.x + len + o, y: mid.y - len * 0.6))
                }
                let marks = SKShapeNode(path: path)
                marks.strokeColor = scratch
                marks.lineWidth = max(0.8, cell * 0.012)
                marks.zRotation = alongLength ? .pi / 2 : 0
                // rotate about the mark centre
                let holder = SKNode()
                holder.position = mid
                marks.position = CGPoint(x: -mid.x, y: -mid.y)
                holder.addChild(marks)
                holder.zRotation = alongLength ? .pi / 2 : 0
                marks.zRotation = 0
                rusticLayer.addChild(holder)
            }
        }
    }

    /// The house answers a touch like a real board would: a 3 % lift and back, nothing coloured.
    func press(house: Int) {
        guard built, houseNodes.indices.contains(house) else { return }
        let node = houseNodes[house]
        node.removeAction(forKey: "press")
        node.run(SKAction.sequence([
            SKAction.scale(to: 1.03, duration: 0.06),
            SKAction.scale(to: 1.0, duration: 0.12),
        ]), withKey: "press")
    }

    private var highlightedHouse: Int?
    func setHighlight(house: Int?) {
        highlightedHouse = house
        highlight(house: house)
    }

    // MARK: - Seeds

    private func makeSeed() -> SKNode {
        let r = layout.seedRadius
        let body = SKSpriteNode(texture: seedTextures.randomElement()!)
        body.size = CGSize(width: r * 2.3, height: r * 2.3)
        body.zRotation = CGFloat.random(in: -.pi ... .pi)
        let shadow = SKShapeNode(ellipseIn: CGRect(x: -r * 1.0, y: -r * 0.85, width: r * 2.0, height: r * 1.7))
        shadow.fillColor = UIColor(white: 0, alpha: 0.42)
        shadow.lineWidth = 0
        shadow.position = CGPoint(x: r * 0.18, y: -r * 0.22)
        shadow.zPosition = -0.5
        shadow.zRotation = -body.zRotation
        shadow.name = "shadow"
        body.addChild(shadow)
        return body
    }

    /// Lift a seed toward the viewer (bigger, shadow drifts away and softens) or set it down.
    private func lift(_ seed: SKNode, up: Bool, duration: TimeInterval) -> SKAction {
        let r = layout.seedRadius
        if let shadow = seed.childNode(withName: "shadow") {
            let move = SKAction.move(to: up ? CGPoint(x: r * 0.9, y: -r * 1.1) : CGPoint(x: r * 0.18, y: -r * 0.22), duration: duration)
            let fade = SKAction.fadeAlpha(to: up ? 0.22 : 1.0, duration: duration)
            shadow.run(SKAction.group([move, fade]))
        }
        let scale = SKAction.scale(to: up ? 1.18 : 1.0, duration: duration)
        scale.timingMode = up ? .easeOut : .easeIn
        return scale
    }

    /// A faint ring that spreads where a seed lands.
    private func puff(at point: CGPoint) {
        let ring = SKShapeNode(circleOfRadius: layout.seedRadius * 0.9)
        ring.strokeColor = UIColor(white: 1, alpha: 0.35)
        ring.lineWidth = 1
        ring.fillColor = .clear
        ring.position = point
        glowLayer.addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 2.2, duration: 0.28 / animationSpeed), SKAction.fadeOut(withDuration: 0.28 / animationSpeed)]),
            SKAction.removeFromParent(),
        ]))
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
        handNode.removeAllChildren()
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
            countShadows[i].text = countLabels[i].text
            countShadows[i].isHidden = !showCounts
        }
        for p in Player.allCases {
            storeLabels[p.rawValue].text = state.stores[p.rawValue] == 0 ? "" : "\(state.stores[p.rawValue])"
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
        handNode.removeAllChildren()
        animating = true
        defer { animating = false }
        var working = before
        let sowCount = events.filter { if case .sow = $0 { return true } else { return false } }.count
        // The hand carries the seeds and lets one fall into each house in turn. Long laps speed up
        // a little so a twenty-seed sowing still finishes in a few seconds.
        let step = min(0.16, max(0.12, 2.0 / Double(max(sowCount, 1))))   // hand travel between houses (120–160 ms)
        let drop = min(0.14, max(0.11, step * 0.85))                        // fall time

        for event in events {
            switch event {
            case let .pickUp(house, _):
                let seeds = seedsInHouse[house]
                seedsInHouse[house] = []
                working.houses[house] = 0
                updateLabels(working)
                sound?.play(.pickUp, volume: 0.8)
                haptics?.pickUp()
                handNode.position = layout.sk(layout.houseCenter(house))
                for (k, seed) in seeds.enumerated() {
                    // Re-parent into the hand, keeping the world position, then gather into a loose cluster.
                    let world = seed.position
                    seed.removeFromParent()
                    seed.position = CGPoint(x: world.x - handNode.position.x, y: world.y - handNode.position.y)
                    handNode.addChild(seed)
                    let angle = Double(k) * 2.399963
                    let rr = layout.seedRadius * 0.95 * CGFloat(Double(k).squareRoot())
                    let gather = SKAction.move(to: CGPoint(x: rr * CGFloat(cos(angle)), y: rr * CGFloat(sin(angle))), duration: 0.22 / animationSpeed)
                    gather.timingMode = .easeOut
                    seed.run(SKAction.group([gather, lift(seed, up: true, duration: 0.22 / animationSpeed)]), withKey: "move")
                }
                let rise = SKAction.move(to: layout.sk(layout.handPoint(for: house)), duration: 0.26 / animationSpeed)
                rise.timingMode = .easeOut
                handNode.run(rise, withKey: "hand")
                await wait(0.3)

            case let .sow(house, count):
                guard let seed = handNode.children.last else { continue }
                working.houses[house] = count
                // Carry the hand over the next house…
                let travel = SKAction.move(to: layout.sk(layout.handPoint(for: house)), duration: step / animationSpeed)
                travel.timingMode = .easeInEaseOut
                handNode.run(travel, withKey: "hand")
                await wait(step * 0.7)
                // …and let one seed go. It falls, tumbles, lands with a small settle and a puff.
                let world = handNode.convert(seed.position, to: self)
                seed.removeFromParent()
                seed.position = world
                seed.zPosition = 10
                seedLayer.addChild(seed)
                seedsInHouse[house].append(seed)
                let slot = layout.sk(layout.seedSlot(in: house, index: count - 1))
                let fall = SKAction.move(to: slot, duration: drop / animationSpeed)
                fall.timingMode = .easeIn
                let tumble = SKAction.rotate(byAngle: CGFloat.random(in: -1.4 ... 1.4), duration: drop / animationSpeed)
                let settle = SKAction.sequence([
                    SKAction.scale(to: 0.9, duration: 0.05 / animationSpeed),
                    SKAction.scale(to: 1.0, duration: 0.09 / animationSpeed),
                ])
                seed.run(SKAction.sequence([SKAction.group([fall, tumble, lift(seed, up: false, duration: drop / animationSpeed)]), settle]), withKey: "sow")
                await wait(drop * 0.9)
                seed.zPosition = 0
                updateLabels(working)
                sound?.play(.tick, volume: Float.random(in: 0.5 ... 0.8))
                haptics?.seedDrop()
                puff(at: slot)

            case .skipOrigin:
                await wait(step * 0.4)

            case let .capture(house, seeds, by):
                await pulse(house: house, color: UIColor(red: 0.10, green: 0.05, blue: 0.02, alpha: 0.6))
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
                    let delay = SKAction.wait(forDuration: Double(k) * 0.035 / animationSpeed)
                    let flight = self.settle(seed, at: layout.storeSlot(by, index: index), duration: 0.42 / animationSpeed)
                    let tumble = SKAction.rotate(byAngle: CGFloat.random(in: -2 ... 2), duration: 0.42 / animationSpeed)
                    // One flip as it comes to rest in the bowl says "captured" without any glow.
                    let flip = SKAction.sequence([
                        SKAction.scaleY(to: 0.15, duration: 0.09 / animationSpeed),
                        SKAction.scaleY(to: 1.0, duration: 0.11 / animationSpeed),
                    ])
                    seed.run(SKAction.sequence([delay, SKAction.group([flight, tumble, self.lift(seed, up: true, duration: 0.2 / animationSpeed)]),
                                                self.lift(seed, up: false, duration: 0.1 / animationSpeed), flip]), withKey: "capture")
                }
                await wait(0.62 + Double(taken.count) * 0.035)
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
                        seed.run(SKAction.sequence([delay, self.settle(seed, at: layout.storeSlot(player, index: index), duration: 0.45 / animationSpeed)]), withKey: "sweep")
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
        handNode.removeAllChildren()
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
        glow.fillColor = .clear
        glow.strokeColor = color
        glow.lineWidth = 2
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
