import Testing
import Foundation
@testable import SupportKit

@MainActor
struct TipJarTests {
    private func defaults() -> UserDefaults {
        let name = "SupportKitTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func startsEmptyAndUnthanked() {
        let jar = TipJar(productIDs: ["a", "b"], defaults: defaults())
        #expect(jar.tips.isEmpty)
        #expect(!jar.hasTipped)
        #expect(jar.tipCount == 0)
    }

    @Test func recordingATipPersistsTheCount() {
        let d = defaults()
        let jar = TipJar(productIDs: ["a"], defaults: d)
        var reported: [String] = []
        jar.onTip = { reported.append($0) }
        jar.record(productID: "a")
        #expect(jar.tipCount == 1)
        #expect(jar.justTipped)
        #expect(jar.lastTippedProductID == "a")
        #expect(reported == ["a"])
        let again = TipJar(productIDs: ["a"], defaults: d)
        #expect(again.hasTipped)
        #expect(again.tipCount == 1)
    }

    @Test func productOrderFollowsTheIDsGiven() {
        let jar = TipJar(productIDs: ["small", "medium", "large"], defaults: defaults())
        #expect(jar.productIDs == ["small", "medium", "large"])
    }
}

/// What the player sees while the tips load and when they cannot. App Review once saw a jar whose
/// products never loaded and read it as broken; the jar must always show the tips, a loading
/// line, or a plain message with a way to try again.
@MainActor
struct TipJarLoadingTests {
    private func defaults() -> UserDefaults {
        let name = "SupportKitTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Counts calls and records the ids asked for.
    final class LoaderSpy: @unchecked Sendable {
        var calls = 0
        var requested: [[String]] = []
    }

    struct Offline: Error {}

    @Test func startsIdleWithNothingToShowYet() {
        let jar = TipJar(productIDs: ["a"], defaults: defaults(), loader: { _ in [] })
        #expect(jar.loadState == .idle)
        #expect(jar.loadMessage == nil)
    }

    @Test func asksStoreKitForExactlyItsOwnProducts() async {
        let spy = LoaderSpy()
        let jar = TipJar(productIDs: ["small", "medium", "large"], defaults: defaults(), loader: { ids in
            spy.calls += 1
            spy.requested.append(ids)
            return []
        })
        await jar.load()
        #expect(spy.requested == [["small", "medium", "large"]])
    }

    @Test func noProductsFromTheStoreIsAFailureWithAPlainMessage() async {
        let jar = TipJar(productIDs: ["a"], defaults: defaults(), loader: { _ in [] })
        await jar.load()
        #expect(jar.loadState == .failed)
        #expect(jar.tips.isEmpty)
        #expect(jar.loadMessage == TipJar.unavailableMessage)
    }

    @Test func aStoreErrorShowsThePlainMessageNotTheErrorText() async {
        let jar = TipJar(productIDs: ["a"], defaults: defaults(), loader: { _ in throw Offline() })
        await jar.load()
        #expect(jar.loadState == .failed)
        #expect(jar.loadMessage == TipJar.unavailableMessage)
    }

    @Test func retryingAsksTheStoreAgain() async {
        let spy = LoaderSpy()
        let jar = TipJar(productIDs: ["a"], defaults: defaults(), loader: { _ in
            spy.calls += 1
            throw Offline()
        })
        await jar.load()
        await jar.retry()
        #expect(spy.calls == 2)
        #expect(jar.loadState == .failed)
    }

    @Test func aStoreThatNeverAnswersTimesOut() async {
        let jar = TipJar(productIDs: ["a"], defaults: defaults(), loadTimeout: .milliseconds(100), loader: { _ in
            try await Task.sleep(for: .seconds(30))
            return []
        })
        let started = ContinuousClock.now
        await jar.load()
        #expect(jar.loadState == .failed)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func showsLoadingWhileTheStoreIsAsked() async {
        let jar = TipJar(productIDs: ["a"], defaults: defaults(), loader: { _ in
            try await Task.sleep(for: .milliseconds(300))
            return []
        })
        let loading = Task { await jar.load() }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(jar.loadState == .loading)
        #expect(jar.isLoading)
        await loading.value
        #expect(!jar.isLoading)
    }

    @Test func overlappingLoadsAskTheStoreOnce() async {
        let spy = LoaderSpy()
        let jar = TipJar(productIDs: ["a"], defaults: defaults(), loader: { _ in
            spy.calls += 1
            try await Task.sleep(for: .milliseconds(200))
            return []
        })
        async let first: Void = jar.load()
        async let second: Void = jar.load()
        _ = await (first, second)
        #expect(spy.calls == 1)
    }

    @Test func thePlainMessageNeverSoundsBrokenOrUnfinished() {
        let message = TipJar.unavailableMessage.lowercased()
        for word in ["error", "soon", "not available", "unavailable", "beta", "coming", "failed"] {
            #expect(!message.contains(word), "\(word)")
        }
    }
}
