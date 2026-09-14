import StoreKit
import SwiftUI

// MARK: - PaywallCTAState

/// What the paywall's primary button can currently do.
///
/// Extracted so the "there is nothing to buy" case has somewhere to live. It
/// previously had nowhere: the button body was `if let product { … }` with no
/// `else`, so a failed product load turned the only call to action on the
/// screen into a no-op that gave the user nothing to act on.
enum PaywallCTAState: Equatable {
    /// Still asking the App Store what is for sale.
    case loading
    /// There is a product and it can be bought.
    case ready
    /// There is nothing to buy, and this is why.
    case unavailable(String)

    /// Whether tapping can actually start a purchase.
    var isPurchasable: Bool {
        self == .ready
    }
}

// MARK: - PaywallView

/// Pro upgrade screen with Free vs Pro comparison and pricing cards.
struct PaywallView: View {
    @Environment(StoreKitManager.self) private var storeKit
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: String = StoreKitManager.yearlyID
    @State private var purchaseError: String?

    /// Shown when the store could not say why it has nothing to sell.
    static let genericUnavailableMessage =
        "Subscriptions are unavailable right now. Check your connection and try again."

    /// The Pro column's claim about caption styles.
    ///
    /// Derived rather than written down. The table used to read "All 10+"
    /// against exactly ten presets, and a hardcoded replacement would simply
    /// go stale the next time a style is added or removed.
    static var proStyleCountText: String {
        "All \(CaptionStyle.presets.count)"
    }

    /// What the button can do, given what the store has told us so far.
    ///
    /// Pure, and takes its inputs rather than reading them, so the three
    /// failure shapes can be asserted without a StoreKit session.
    static func ctaState(isLoading: Bool, hasProduct: Bool, error: String?) -> PaywallCTAState {
        if hasProduct { return .ready }
        if isLoading { return .loading }
        return .unavailable(error ?? genericUnavailableMessage)
    }

    /// Stands in for a price the store has not given us.
    static let unknownPriceText = "—"

    /// The price to print for a plan.
    ///
    /// `Product.displayPrice` is already formatted for the user's storefront
    /// and locale, so it is passed through untouched. When it is absent there
    /// is nothing to print, and printing nothing is the honest answer: the
    /// cards used to fall back to "$2.99" and "$14.99", quoting US dollars to
    /// a user who would be charged yen or euros, at figures that need not
    /// match their storefront even after converting.
    static func priceText(displayPrice: String?) -> String {
        displayPrice ?? unknownPriceText
    }

    /// How much cheaper a year is than twelve separate months, or `nil` when
    /// there is no sound basis for the claim.
    ///
    /// The badge used to read a hardcoded "SAVE 58%" — arithmetic done once,
    /// by hand, on the two hardcoded dollar prices. It survived into every
    /// storefront that prices the plans differently, and would have survived a
    /// price change, asserting a discount the user was not being offered.
    static func savingsBadge(monthlyPrice: Decimal?, yearlyPrice: Decimal?) -> String? {
        guard let monthlyPrice, let yearlyPrice else { return nil }
        let twelveMonths = monthlyPrice * 12
        // No claim unless the year genuinely undercuts paying monthly.
        guard twelveMonths > 0, yearlyPrice < twelveMonths else { return nil }
        let fraction = (twelveMonths - yearlyPrice) / twelveMonths
        let percent = Int((fraction as NSDecimalNumber).doubleValue * 100)
        guard percent > 0 else { return nil }
        return "SAVE \(percent)%"
    }

    private var selectedProduct: Product? {
        selectedPlan == StoreKitManager.yearlyID
            ? storeKit.yearlyProduct
            : storeKit.monthlyProduct
    }

    private var ctaState: PaywallCTAState {
        Self.ctaState(
            isLoading: storeKit.isLoading,
            hasProduct: selectedProduct != nil,
            error: storeKit.error
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    headerSection

                    // Comparison table
                    comparisonSection

                    // Pricing cards
                    pricingSection

                    // CTA
                    ctaButton

                    // Anything that went wrong, said out loud
                    statusMessage

                    // Restore + Terms
                    footerLinks
                }
                .padding(.top, 24)
            }
            .background(
                LinearGradient(
                    colors: [Color(hex: "#1A1040").opacity(0.5), Color(uiColor: .systemBackground)],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .onAppear {
            AnalyticsService.paywallShown(trigger: "manual")
        }
    }

    // MARK: - Status

    /// The reason the button is not going to work, or the reason a tap did not
    /// result in a purchase. Both used to be recorded and never shown.
    @ViewBuilder
    private var statusMessage: some View {
        if let message = purchaseError ?? unavailableMessage {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
        }
    }

    private var unavailableMessage: String? {
        if case let .unavailable(message) = ctaState { return message }
        return nil
    }


    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: "#7C3AED"))

            Text("CaptionsAI Pro")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Comparison

    private var comparisonSection: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .font(.headline)
                    .frame(width: 70)
                Text("Pro")
                    .font(.headline)
                    .foregroundColor(Color(hex: "#7C3AED"))
                    .frame(width: 70)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Rows
            ComparisonRow(feature: "Exports per day", free: "2", pro: "Unlimited")
            ComparisonRow(feature: "Watermark", free: "Yes", pro: "No", proIsGood: true)
            ComparisonRow(feature: "Caption Styles", free: "3", pro: Self.proStyleCountText)
            ComparisonRow(feature: "Word Highlight", free: "No", pro: "Yes", proIsGood: true)
            ComparisonRow(feature: "Priority Support", free: "No", pro: "Yes", proIsGood: true)
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        HStack(spacing: 12) {
            // Monthly
            PricingCard(
                price: Self.priceText(displayPrice: storeKit.monthlyProduct?.displayPrice),
                period: "/month",
                badge: nil,
                isSelected: selectedPlan == StoreKitManager.monthlyID,
                isGradient: false
            )
            .onTapGesture { selectedPlan = StoreKitManager.monthlyID }

            // Yearly
            PricingCard(
                price: Self.priceText(displayPrice: storeKit.yearlyProduct?.displayPrice),
                period: "/year",
                badge: Self.savingsBadge(
                    monthlyPrice: storeKit.monthlyProduct?.price,
                    yearlyPrice: storeKit.yearlyProduct?.price
                ),
                isSelected: selectedPlan == StoreKitManager.yearlyID,
                isGradient: true
            )
            .onTapGesture { selectedPlan = StoreKitManager.yearlyID }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - CTA

    /// The primary call to action.
    ///
    /// Reads `ctaState` rather than re-deriving the product inline, so the
    /// three cases the store can be in — still loading, ready, nothing to
    /// sell — each produce a button the user can make sense of. The old
    /// version wrapped the whole action in `if let product` with no `else`,
    /// so when the product load failed the button stayed fully lit and did
    /// nothing at all when tapped.
    private var ctaButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            Task {
                purchaseError = nil
                do {
                    _ = try await storeKit.purchase(product)
                    if storeKit.isPro {
                        dismiss()
                    }
                } catch {
                    // Previously `try?`, which discarded the reason the
                    // purchase failed and left the screen looking idle.
                    purchaseError = error.localizedDescription
                }
            }
        } label: {
            Group {
                if ctaState == .loading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Start Free Trial")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#7C3AED"), Color(hex: "#3B82F6")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(ctaState.isPurchasable ? 1 : 0.5)
        }
        .disabled(!ctaState.isPurchasable)
        .padding(.horizontal, 24)
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 12) {
            Button("Restore Purchases") {
                Task { await storeKit.restorePurchases() }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            Text("Terms & Privacy")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.bottom, 32)
    }
}

// MARK: - Comparison Row

private struct ComparisonRow: View {
    let feature: String
    let free: String
    let pro: String
    var proIsGood: Bool = false

    var body: some View {
        HStack {
            Text(feature)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(free)
                .font(.subheadline)
                .frame(width: 70)

            HStack(spacing: 4) {
                if proIsGood {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(Color(hex: "#7C3AED"))
                }
                Text(pro)
                    .font(.subheadline.bold())
            }
            .frame(width: 70)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.05))
    }
}

// MARK: - Pricing Card

private struct PricingCard: View {
    let price: String
    let period: String
    let badge: String?
    let isSelected: Bool
    let isGradient: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let badge {
                Text(badge)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#3B82F6"))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(price)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text(period)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            Group {
                if isGradient {
                    LinearGradient(
                        colors: [Color(hex: "#7C3AED").opacity(0.6), Color(hex: "#3B82F6").opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color(hex: "#7C3AED") : Color.gray.opacity(0.3), lineWidth: 2)
        )
    }
}
