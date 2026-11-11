import StoreKit
import SwiftUI

// MARK: - StoreClient

/// The App Store calls `StoreKitManager` makes, as values.
///
/// `Product` has no public initialiser, so a test cannot fabricate one — but
/// it can make a load fail, or come back empty, which are exactly the paths
/// that went wrong.
struct StoreClient {
    var products: (Set<String>) async throws -> [Product]
    /// The verified transactions the App Store currently says the user holds.
    var entitlements: () async -> [Entitlement]
    /// Asks the App Store to re-send this Apple ID's transactions. May show a
    /// sign-in prompt, so only ever called from an explicit Restore tap.
    var sync: () async throws -> Void

    static let live = StoreClient(
        products: { try await Product.products(for: $0) },
        entitlements: {
            var found: [Entitlement] = []
            for await result in Transaction.currentEntitlements {
                // Unverified transactions are not evidence of anything.
                guard case let .verified(transaction) = result else { continue }
                found.append(Entitlement(transaction))
            }
            return found
        },
        sync: { try await AppStore.sync() }
    )
}

// MARK: - PurchaseOutcome

/// How a purchase attempt ended, when it did not throw.
enum PurchaseOutcome: Equatable {
    case purchased
    case cancelled
    /// Waiting on someone else — Ask to Buy, or a bank check. The transaction
    /// arrives later through `Transaction.updates`.
    case pending
}

// MARK: - RestoreOutcome

/// What a Restore Purchases tap achieved, so the paywall can say so.
enum RestoreOutcome: Equatable {
    case restored
    case nothingToRestore
    /// The user dismissed the App Store sign-in. Not an error worth a message.
    case cancelled
    case failed(String)
}

// MARK: - Entitlement

/// The three facts about a transaction that decide whether it unlocks Pro.
struct Entitlement: Equatable {
    var productID: String
    var revocationDate: Date?
    var expirationDate: Date?

    init(productID: String, revocationDate: Date? = nil, expirationDate: Date? = nil) {
        self.productID = productID
        self.revocationDate = revocationDate
        self.expirationDate = expirationDate
    }

    init(_ transaction: StoreKit.Transaction) {
        self.init(
            productID: transaction.productID,
            revocationDate: transaction.revocationDate,
            expirationDate: transaction.expirationDate
        )
    }

    /// Refunded or revoked never counts; a subscription counts until it
    /// expires. `currentEntitlements` should already leave these out — this
    /// is the belt to its braces, and the part a test can hold.
    func isActive(at now: Date) -> Bool {
        guard revocationDate == nil else { return false }
        guard let expirationDate else { return true }
        return expirationDate > now
    }
}

// MARK: - StoreKitManager

/// Manages in-app purchases and subscription status using StoreKit 2.
@Observable
final class StoreKitManager {
    // MARK: - Product IDs

    static let monthlyID = "com.captionsai.pro.monthly"
    static let yearlyID = "com.captionsai.pro.yearly"
    static let productIDs: Set<String> = [monthlyID, yearlyID]

    // MARK: - State

    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoading = false
    var error: String?

    var isPro: Bool {
        !purchasedProductIDs.isEmpty
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyID }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyID }
    }

    // MARK: - Private

    private let client: StoreClient
    private var transactionListener: Task<Void, Never>?
    /// The entitlement check started at launch, kept so that a decision
    /// that depends on `isPro` can wait for it.
    private var initialEntitlementCheck: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - client: The App Store calls. Tests pass fakes.
    ///   - startImmediately: Whether to begin loading and listening now.
    ///     Tests pass `false` so nothing touches the real store behind them.
    init(client: StoreClient = .live, startImmediately: Bool = true) {
        self.client = client
        guard startImmediately else { return }
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        initialEntitlementCheck = Task { await refreshEntitlements() }
    }

    /// Returns once the launch-time entitlement check has finished.
    ///
    /// `isPro` reads false until then, so a subscriber who went straight to
    /// Export after a cold launch could get a watermark burned in, or the
    /// daily-limit paywall. Export waits on this before deciding.
    func waitForInitialEntitlements() async {
        await initialEntitlementCheck?.value
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    /// Whether the paywall should ask the store again when it opens.
    ///
    /// Products used to be fetched once, at launch. A launch in airplane mode
    /// left the paywall saying "unavailable" until the app was killed, however
    /// good the connection was by the time the user got there.
    var needsProducts: Bool {
        products.isEmpty && !isLoading
    }

    /// The plans in the order the paywall lists them: yearly first, as the
    /// better value, then the rest in the order the store gave them.
    ///
    /// Generic over the element so the order can be tested without a
    /// `Product`, which a test cannot construct. A stable partition rather
    /// than `sorted(by:)` with a yearly-first predicate, which is not a strict
    /// weak ordering for the other elements and so promises nothing about
    /// their order.
    static func yearlyFirst<Item>(_ items: [Item], id: (Item) -> String) -> [Item] {
        items.filter { id($0) == yearlyID } + items.filter { id($0) != yearlyID }
    }

    @MainActor
    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        // A retry that succeeds must not keep showing the last failure.
        error = nil

        do {
            let storeProducts = try await client.products(Self.productIDs)
            products = Self.yearlyFirst(storeProducts, id: \.id)
        } catch {
            self.error = "Failed to load products: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Purchase

    /// `.pending` used to come back as `nil`, the same as a cancel, so a
    /// child whose purchase went to a parent for approval saw nothing happen.
    @MainActor
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()

        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()

            AnalyticsService.purchaseCompleted(productID: product.id)

            return .purchased

        case .userCancelled:
            return .cancelled

        case .pending:
            return .pending

        @unknown default:
            return .cancelled
        }
    }

    // MARK: - Restore

    /// Restore used to read local entitlements only — no `AppStore.sync()`,
    /// so a purchase made on another device, or before a reinstall, often
    /// was not there to find — and returned nothing, so the button looked
    /// dead whether or not it worked.
    @MainActor
    func restorePurchases() async -> RestoreOutcome {
        var syncError: Error?
        do {
            try await client.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            syncError = error
        }

        // Rebuild even when the sync failed: whatever is already on the
        // device is still the best answer available.
        await refreshEntitlements()

        if isPro { return .restored }
        if let syncError { return .failed(syncError.localizedDescription) }
        return .nothingToRestore
    }

    // MARK: - Entitlements

    /// The product IDs that unlock Pro right now.
    static func activeProductIDs(in entitlements: [Entitlement], at now: Date) -> Set<String> {
        Set(entitlements.filter { $0.isActive(at: now) }.map(\.productID))
    }

    /// Rebuilds Pro from what the App Store says now, replacing — never
    /// adding to — what was believed before. That replacement is what lets a
    /// refund or an expiry take Pro away.
    @MainActor
    func refreshEntitlements(now: Date = Date()) async {
        purchasedProductIDs = Self.activeProductIDs(in: await client.entitlements(), at: now)
    }

    // MARK: - Transaction Listener

    /// Every update — purchase, renewal, refund, revocation — ends in a full
    /// rebuild. This used to `insert` the update's product ID whatever it
    /// said, so a refund arriving here left Pro on until the next launch
    /// happened to rebuild it.
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case let .verified(transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }

    // MARK: - Verification

    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .unverified(_, error):
            throw error
        case let .verified(safe):
            return safe
        }
    }
}
