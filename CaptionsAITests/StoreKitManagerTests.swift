@testable import CaptionsAI
import StoreKit
import XCTest

/// What the store manager does when the App Store misbehaves.
///
/// `Product` cannot be constructed in a test, so the fakes here fail or come
/// back empty — which are the paths that went wrong. Nothing here talks to
/// StoreKit: SKTestSession cannot start under `xcodebuild test` on the build
/// loop (SKInternalErrorDomain 3), so a live-products test only ever failed
/// there. The paywall order is tested through `yearlyFirst(_:id:)` instead.
@MainActor
final class StoreKitManagerTests: XCTestCase {
    private struct Offline: LocalizedError {
        var errorDescription: String? { "The Internet connection appears to be offline." }
    }

    private func manager(
        products: @escaping (Set<String>) async throws -> [Product] = { _ in [] },
        entitlements: @escaping () async -> [Entitlement] = { [] },
        sync: @escaping () async throws -> Void = {}
    ) -> StoreKitManager {
        StoreKitManager(
            client: StoreClient(products: products, entitlements: entitlements, sync: sync),
            startImmediately: false
        )
    }

    // MARK: - Waiting for the launch check

    func testWaitingForEntitlementsDoesNotHangWhenNothingWasStarted() async {
        // Export awaits this before every decision; with no launch check in
        // flight (tests, previews) it must return straight away.
        let store = manager()
        await store.waitForInitialEntitlements()
        XCTAssertFalse(store.isPro)
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

    // MARK: - Plan order

    private func order(_ ids: [String]) -> [String] {
        StoreKitManager.yearlyFirst(ids, id: { $0 })
    }

    func testYearlyIsListedBeforeMonthly() {
        XCTAssertEqual(
            order(["com.captionsai.pro.monthly", "com.captionsai.pro.yearly"]),
            ["com.captionsai.pro.yearly", "com.captionsai.pro.monthly"]
        )
    }

    func testAnAlreadyYearlyFirstListIsUnchanged() {
        XCTAssertEqual(
            order(["com.captionsai.pro.yearly", "com.captionsai.pro.monthly"]),
            ["com.captionsai.pro.yearly", "com.captionsai.pro.monthly"]
        )
    }

    func testWithoutYearlyTheStoreOrderIsKept() {
        XCTAssertEqual(order(["b", "com.captionsai.pro.monthly", "a"]), ["b", "com.captionsai.pro.monthly", "a"])
    }

    func testOnlyYearlyMovesTheOthersKeepTheirOrder() {
        XCTAssertEqual(
            order(["c", "com.captionsai.pro.monthly", "com.captionsai.pro.yearly", "a"]),
            ["com.captionsai.pro.yearly", "c", "com.captionsai.pro.monthly", "a"]
        )
    }

    func testNoPlansStayNoPlans() {
        XCTAssertEqual(order([]), [])
    }

    // MARK: - Which transactions unlock Pro

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAnUnrevokedUnexpiredSubscriptionIsActive() {
        let entitlement = Entitlement(productID: "p", expirationDate: now.addingTimeInterval(60))
        XCTAssertTrue(entitlement.isActive(at: now))
    }

    func testANonExpiringPurchaseIsActive() {
        XCTAssertTrue(Entitlement(productID: "p").isActive(at: now))
    }

    func testARefundedOrRevokedTransactionIsNeverActive() {
        let revoked = Entitlement(
            productID: "p",
            revocationDate: now.addingTimeInterval(-60),
            expirationDate: now.addingTimeInterval(3600)
        )
        XCTAssertFalse(revoked.isActive(at: now))
    }

    func testAnExpiredSubscriptionIsNotActive() {
        XCTAssertFalse(Entitlement(productID: "p", expirationDate: now.addingTimeInterval(-1)).isActive(at: now))
    }

    /// Expiring at exactly this instant means it has run out.
    func testASubscriptionExpiringNowIsNotActive() {
        XCTAssertFalse(Entitlement(productID: "p", expirationDate: now).isActive(at: now))
    }

    func testOnlyActiveEntitlementsCountTowardsPro() {
        let ids = StoreKitManager.activeProductIDs(
            in: [
                Entitlement(productID: StoreKitManager.yearlyID, expirationDate: now.addingTimeInterval(86400)),
                Entitlement(productID: StoreKitManager.monthlyID, revocationDate: now),
            ],
            at: now
        )

        XCTAssertEqual(ids, [StoreKitManager.yearlyID])
    }

    // MARK: - Rebuilding Pro

    func testRefreshingWithAnActiveSubscriptionTurnsProOn() async {
        let store = manager(entitlements: { [Entitlement(productID: StoreKitManager.yearlyID)] })

        await store.refreshEntitlements(now: now)

        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.purchasedProductIDs, [StoreKitManager.yearlyID])
    }

    /// The defect: updates were inserted, never replaced, so a refund could
    /// not take Pro away. A refresh after the refund must end Pro.
    func testARefundTakesProAwayOnTheNextRefresh() async {
        var revocationDate: Date?
        let store = manager(entitlements: {
            [Entitlement(productID: StoreKitManager.monthlyID, revocationDate: revocationDate)]
        })

        await store.refreshEntitlements(now: now)
        XCTAssertTrue(store.isPro)

        revocationDate = now
        await store.refreshEntitlements(now: now)

        XCTAssertFalse(store.isPro)
    }

    /// `currentEntitlements` stops listing a product once it lapses; the
    /// rebuild has to drop it rather than keep the stale ID.
    func testAProductNoLongerListedIsDropped() async {
        var listed = [Entitlement(productID: StoreKitManager.monthlyID)]
        let store = manager(entitlements: { listed })

        await store.refreshEntitlements(now: now)
        listed = []
        await store.refreshEntitlements(now: now)

        XCTAssertEqual(store.purchasedProductIDs, [])
        XCTAssertFalse(store.isPro)
    }

    // MARK: - Restore Purchases

    /// Restore has to ask the App Store to re-send transactions; reading the
    /// local cache alone misses purchases from another device or before a
    /// reinstall.
    func testRestoreSyncsWithTheAppStoreOnce() async {
        var syncs = 0
        let store = manager(sync: { syncs += 1 })

        _ = await store.restorePurchases()

        XCTAssertEqual(syncs, 1)
    }

    /// The sync must come before the rebuild, or the rebuild reads the old
    /// cache.
    func testRestoreRebuildsAfterTheSyncNotBefore() async {
        var synced = false
        let store = manager(
            entitlements: { synced ? [Entitlement(productID: StoreKitManager.yearlyID)] : [] },
            sync: { synced = true }
        )

        let outcome = await store.restorePurchases()

        XCTAssertEqual(outcome, .restored)
        XCTAssertTrue(store.isPro)
    }

    func testRestoreWithNothingToFindSaysSo() async {
        let store = manager()

        let outcome = await store.restorePurchases()

        XCTAssertEqual(outcome, .nothingToRestore)
        XCTAssertFalse(store.isPro)
    }

    func testAFailedSyncWithNothingOnTheDeviceReportsTheReason() async {
        let store = manager(sync: { throw Offline() })

        let outcome = await store.restorePurchases()

        XCTAssertEqual(outcome, .failed("The Internet connection appears to be offline."))
    }

    /// A failed sync is not the last word if the device already knows about
    /// an active subscription.
    func testAFailedSyncStillRestoresWhatTheDeviceAlreadyHas() async {
        let store = manager(
            entitlements: { [Entitlement(productID: StoreKitManager.monthlyID)] },
            sync: { throw Offline() }
        )

        let outcome = await store.restorePurchases()

        XCTAssertEqual(outcome, .restored)
        XCTAssertTrue(store.isPro)
    }

    /// Dismissing the App Store sign-in is the user's choice, not a failure,
    /// and must not wipe Pro by rebuilding from a half-finished sync.
    func testCancellingTheSignInIsNotAFailureAndChangesNothing() async {
        var rebuilt = false
        let store = manager(
            entitlements: {
                rebuilt = true
                return []
            },
            sync: { throw StoreKitError.userCancelled }
        )

        let outcome = await store.restorePurchases()

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(rebuilt)
    }

    // MARK: - What the paywall says after Restore

    func testASuccessfulOrCancelledRestoreShowsNoMessage() {
        XCTAssertNil(PaywallView.restoreMessage(for: .restored))
        XCTAssertNil(PaywallView.restoreMessage(for: .cancelled))
    }

    func testNothingToRestoreIsSaidPlainly() {
        XCTAssertEqual(
            PaywallView.restoreMessage(for: .nothingToRestore),
            "No active subscription was found for this Apple ID."
        )
    }

    func testAFailedRestoreCarriesTheReason() {
        XCTAssertEqual(
            PaywallView.restoreMessage(for: .failed("Network down.")),
            "Could not restore purchases. Network down."
        )
    }

    // MARK: - While a purchase is in progress

    /// A second tap during the purchase sheet used to start a second purchase.
    func testTheButtonCannotBeTappedAgainWhilePurchasing() {
        let state = PaywallView.ctaState(isLoading: false, hasProduct: true, error: nil, isPurchasing: true)

        XCTAssertEqual(state, .purchasing)
        XCTAssertFalse(state.isPurchasable)
    }

    /// Purchasing wins over a background reload finishing or failing mid-way.
    func testPurchasingWinsOverLoadingAndErrors() {
        XCTAssertEqual(
            PaywallView.ctaState(isLoading: true, hasProduct: false, error: "x", isPurchasing: true),
            .purchasing
        )
    }

    func testTheButtonIsLiveAgainOncePurchasingEnds() {
        XCTAssertEqual(
            PaywallView.ctaState(isLoading: false, hasProduct: true, error: nil, isPurchasing: false),
            .ready
        )
    }

    // MARK: - What the paywall says after a purchase attempt

    /// Ask to Buy used to look exactly like a cancel: nothing happened.
    func testAPendingPurchaseSaysItIsWaitingForApproval() {
        XCTAssertEqual(
            PaywallView.purchaseMessage(for: .pending),
            "Your purchase is waiting for approval. Pro unlocks as soon as it's approved."
        )
    }

    func testAPurchaseOrCancelShowsNoMessage() {
        XCTAssertNil(PaywallView.purchaseMessage(for: .purchased))
        XCTAssertNil(PaywallView.purchaseMessage(for: .cancelled))
    }
}
