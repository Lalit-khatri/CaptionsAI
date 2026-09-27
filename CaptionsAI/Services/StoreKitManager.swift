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

    static let live = StoreClient(
        products: { try await Product.products(for: $0) }
    )
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
        Task { await restorePurchases() }
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

    @MainActor
    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        // A retry that succeeds must not keep showing the last failure.
        error = nil

        do {
            let storeProducts = try await client.products(Self.productIDs)
            // Sort: yearly first (better value)
            products = storeProducts.sorted { $0.id == Self.yearlyID && $1.id != Self.yearlyID }
        } catch {
            self.error = "Failed to load products: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Purchase

    @MainActor
    func purchase(_ product: Product) async throws -> StoreKit.Transaction? {
        let result = try await product.purchase()

        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()

            AnalyticsService.purchaseCompleted(productID: product.id)

            return transaction

        case .userCancelled:
            return nil

        case .pending:
            return nil

        @unknown default:
            return nil
        }
    }

    // MARK: - Restore

    @MainActor
    func restorePurchases() async {
        var purchasedIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchasedIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchasedIDs
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await MainActor.run {
                        self?.purchasedProductIDs.insert(transaction.productID)
                    }
                    await transaction.finish()
                }
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
