@testable import CaptionsAI
import StoreKit
import XCTest

/// What the store manager does when the App Store misbehaves.
///
/// `Product` cannot be constructed in a test, so the fakes here fail or come
/// back empty — which are the paths that went wrong. The one test that needs
/// real products uses the scheme's `Configuration.storekit`, which Xcode
/// serves locally during test runs.
@MainActor
final class StoreKitManagerTests: XCTestCase {
    private struct Offline: LocalizedError {
        var errorDescription: String? { "The Internet connection appears to be offline." }
    }

    private func manager(products: @escaping (Set<String>) async throws -> [Product]) -> StoreKitManager {
        StoreKitManager(client: StoreClient(products: products), startImmediately: false)
    }

    // MARK: - Loading products

    func testAFailedLoadSaysWhyAndIsNotStillLoading() async {
        let store = manager { _ in throw Offline() }

        await store.loadProducts()

        XCTAssertEqual(store.error, "Failed to load products: The Internet connection appears to be offline.")
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.products.isEmpty)
    }

    /// The defect: products were fetched once, at launch. After a failed
    /// launch fetch the paywall must know to ask again.
    func testAfterAFailedLoadThePaywallKnowsToAskAgain() async {
        let store = manager { _ in throw Offline() }

        await store.loadProducts()

        XCTAssertTrue(store.needsProducts)
    }

    /// A retry that gets through must not keep showing the old failure.
    func testARetryClearsTheOldError() async {
        var attempts = 0
        let store = manager { _ in
            attempts += 1
            if attempts == 1 { throw Offline() }
            return []
        }

        await store.loadProducts()
        XCTAssertNotNil(store.error)

        await store.loadProducts()

        XCTAssertNil(store.error)
        XCTAssertEqual(attempts, 2)
    }

    /// Asks for exactly the two plans, not a stale or partial list.
    func testTheStoreIsAskedForBothPlans() async {
        var asked: Set<String> = []
        let store = manager { ids in
            asked = ids
            return []
        }

        await store.loadProducts()

        XCTAssertEqual(asked, ["com.captionsai.pro.monthly", "com.captionsai.pro.yearly"])
    }

    /// Two taps on Try Again while the first request is in flight must not
    /// start a second one.
    func testALoadAlreadyInFlightIsNotStartedTwice() async {
        var attempts = 0
        let gate = AsyncStream<Void>.makeStream()
        let store = manager { _ in
            attempts += 1
            for await _ in gate.stream { break }
            return []
        }

        let first = Task { await store.loadProducts() }
        while !store.isLoading { await Task.yield() }

        await store.loadProducts()
        XCTAssertEqual(attempts, 1, "a second request started while the first was in flight")

        gate.continuation.yield()
        await first.value
        XCTAssertFalse(store.isLoading)
    }

    func testANewManagerThatHasNotStartedNeedsProducts() {
        let store = manager { _ in [] }

        XCTAssertTrue(store.needsProducts)
        XCTAssertFalse(store.isPro)
    }

    /// Against the local StoreKit configuration: both plans load, yearly
    /// first. If this fails with no products, check the test scheme still
    /// names `Configuration.storekit`.
    func testTheLiveClientLoadsBothPlansYearlyFirst() async {
        let store = StoreKitManager(client: .live, startImmediately: false)

        await store.loadProducts()

        XCTAssertNil(store.error)
        XCTAssertEqual(store.products.map(\.id), ["com.captionsai.pro.yearly", "com.captionsai.pro.monthly"])
        XCTAssertFalse(store.needsProducts)
    }
}
