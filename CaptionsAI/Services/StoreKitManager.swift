import StoreKit
import SwiftUI

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

    private var transactionListener: Task<Void, Never>?

    // MARK: - Init

    init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await restorePurchases() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    @MainActor
    func loadProducts() async {
        isLoading = true

        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
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
