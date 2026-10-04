import LudoAI
import LudoEngine
import XCTest
@testable import LeluLudo

/// Choosing your colour against the computer (owner, 2026-10-04).
final class ComputerSeatingTests: XCTestCase {
    func testComputersTakeTheColoursLeftOppositeYouFirst() {
        for you in PlayerColor.allCases {
            for n in 1...3 {
                let setup = GameSetup.versusComputer(you: you, opponents: n, level: .novice, rules: .ghanaClassic)
                XCTAssertEqual(setup.seat(you), .human)
                XCTAssertEqual(setup.colors.count, n + 1)
                XCTAssertEqual(setup.colors.filter { setup.seat($0) == .human }, [you], "only you are a person")
                let opposite = PlayerColor(rawValue: (you.rawValue + 2) % 4)!
                XCTAssertEqual(setup.seat(opposite), .computer(.novice), "\(you): the first computer sits opposite")
            }
        }
        XCTAssertEqual(GameSetup.opponentColours(for: .red, count: 3), [.black, .yellow, .green], "as before for red")
        XCTAssertEqual(GameSetup.opponentColours(for: .yellow, count: 3), [.green, .black, .red])
    }

    func testRandomColourAlwaysChangesIt() {
        var rng = SeededGenerator(seed: 7)
        var seating = ComputerSeating()
        for _ in 0..<50 {
            let before = seating.you
            seating.randomColour(using: &rng)
            XCTAssertNotEqual(seating.you, before)
        }
    }

    @MainActor
    func testYouPlayYourColourAndAreCalledYou() async {
        let s = TestSupport.session(dice: [6])
        s.newGame(.versusComputer(you: .green, opponents: 1, level: .novice, rules: .ghanaClassic))
        XCTAssertEqual(s.state.players, [.yellow, .green], "you and the computer opposite you")
        XCTAssertEqual(s.name(.green), "You")
        XCTAssertEqual(s.name(.yellow), "Yellow")
        XCTAssertEqual(s.state.toMove, .green, "you go first, whichever colour you chose")
        XCTAssertTrue(s.canRoll)
    }
}

/// Colours and names for pass & play (owner, 2026-10-04): a colour each, never the same one twice.
final class FriendsSeatingTests: XCTestCase {
    func testStartsWithTwoPlayersFacingEachOther() {
        let seating = FriendsSeating()
        XCTAssertEqual(seating.colours, [.red, .black])
        XCTAssertTrue(seating.canPlay)
    }

    func testTappingAColourAddsThenRemovesThatPlayer() {
        var seating = FriendsSeating()
        seating.toggle(.yellow)
        XCTAssertEqual(seating.colours, [.red, .yellow, .black])
        seating.toggle(.yellow)
        XCTAssertEqual(seating.colours, [.red, .black])
    }

    func testAColourCanNeverBeTakenTwice() {
        var seating = FriendsSeating()
        seating.toggle(.green)
        seating.toggle(.yellow)
        seating.setName("Kofi", for: .green)
        seating.setName("Ama", for: .green)    // the same colour again: the same player, renamed
        XCTAssertEqual(seating.colours.count, Set(seating.colours).count)
        XCTAssertEqual(seating.displayName(.green), "Ama")
        let setup = seating.setup(rules: .ghanaClassic)!
        XCTAssertEqual(setup.colors, [.red, .yellow, .black, .green])
        XCTAssertEqual(Set(setup.colors).count, 4)
    }

    func testTwoToFourPlayers() {
        var seating = FriendsSeating()
        seating.toggle(.black)
        XCTAssertFalse(seating.canPlay, "one player is not a game")
        XCTAssertNil(seating.setup(rules: .ghanaClassic))
        for c in PlayerColor.allCases where !seating.isPlaying(c) { seating.toggle(c) }
        XCTAssertEqual(seating.colours.count, 4)
        XCTAssertTrue(seating.canPlay)
        XCTAssertNil(GameSetup.passAndPlay([.red: ""], rules: .ghanaClassic))
    }

    func testNamesAreOptionalTidiedAndKeptShort() {
        var seating = FriendsSeating()
        seating.setName("  Akosua  ", for: .black)
        seating.setName("   ", for: .red)
        XCTAssertEqual(seating.displayName(.black), "Akosua")
        XCTAssertEqual(seating.displayName(.red), "Red", "no name: called by the colour")
        seating.setName(String(repeating: "x", count: 40), for: .black)
        XCTAssertEqual(seating.displayName(.black).count, GameSetup.nameLimit)
        seating.setName("Kofi", for: .green)
        XCTAssertFalse(seating.isPlaying(.green), "a name for a colour nobody chose is ignored")
        let setup = seating.setup(rules: .ghanaClassic)!
        XCTAssertEqual(setup.names, [.black: String(repeating: "x", count: GameSetup.nameLimit)], "blank names aren't stored")
    }

    func testRandomColoursKeepThePlayersAndTheirNames() {
        var rng = SeededGenerator(seed: 3)
        var seating = FriendsSeating()
        seating.toggle(.yellow)
        seating.setName("Ama", for: .red)
        seating.setName("Kofi", for: .yellow)
        for _ in 0..<30 {
            seating.randomColours(using: &rng)
            XCTAssertEqual(seating.colours.count, 3)
            XCTAssertEqual(Set(seating.colours.map(seating.displayName)).intersection(["Ama", "Kofi"]), ["Ama", "Kofi"])
        }
        var few = FriendsSeating()
        few.toggle(.red)
        few.randomColours(using: &rng)
        XCTAssertTrue(few.canPlay, "with fewer than two, two random colours")
    }

    @MainActor
    func testTheGameCallsPlayersByTheirNames() async {
        let s = TestSupport.session(dice: [3, 3])
        var seating = FriendsSeating()
        seating.setName("Kwame", for: .red)
        s.newGame(seating.setup(rules: .ghanaClassic)!)
        XCTAssertEqual(s.status, "Kwame to roll")
        await s.roll()   // a 3: nobody out, Kwame passes
        XCTAssertEqual(s.name(.black), "Black", "no name typed: the colour")
        XCTAssertEqual(s.status, "Black to roll")
        XCTAssertTrue(s.log.last?.contains("Kwame") ?? false, "\(s.log)")
    }

    @MainActor
    func testNamesAreSavedWithTheGame() {
        let store = TestSupport.store()
        let s = TestSupport.session(dice: [3], store: store)
        s.newGame(GameSetup.passAndPlay([.red: "Kwame", .green: "Esi"], rules: .ghanaClassic)!)
        let reopened = TestSupport.session(dice: [3], store: store)
        XCTAssertEqual(reopened.name(.green), "Esi")
        XCTAssertEqual(reopened.name(.red), "Kwame")
    }

    func testOldSavesWithoutNamesStillLoad() throws {
        // A save from before names: today's encoding with the `names` key taken out.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GameSetup.passAndPlay(players: 2, rules: .ghanaClassic))) as! [String: Any]
        json["names"] = nil
        let setup = try JSONDecoder().decode(GameSetup.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(setup.names, [:])
        XCTAssertEqual(setup.colors, [.red, .black])
    }
}

/// Tips: the product ids the app asks the App Store for are Lelu Ludo's own, the three made in App
/// Store Connect, and the same as in the local test store.
final class TipsTests: XCTestCase {
    func testTheTipProductsAreLeluLudosOwnAndMatchTheTestStore() throws {
        XCTAssertEqual(Tips.productIDs, ["com.richardforjoe.leluludo.tip.small", "com.richardforjoe.leluludo.tip.medium",
                                         "com.richardforjoe.leluludo.tip.large"])
        let storeFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LeluLudo/Resources/Tips.storekit")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: storeFile)) as! [String: Any]
        let ids = (json["products"] as! [[String: Any]]).compactMap { $0["productID"] as? String }
        XCTAssertEqual(Set(ids), Set(Tips.productIDs))
        XCTAssertFalse(Bundle.main.bundleURL.appendingPathComponent("Tips.storekit").path.isEmpty)
        XCTAssertNil(Bundle.main.url(forResource: "Tips", withExtension: "storekit"), "the test store never ships in the app")
    }

    func testTheReviewLinkIsLeluLudosAppStorePage() {
        XCTAssertEqual(Links.writeReview.host, "apps.apple.com")
        XCTAssertTrue(Links.writeReview.absoluteString.contains("id6818915279"))
    }
}
