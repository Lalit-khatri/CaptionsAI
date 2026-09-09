import SwiftUI

// MARK: - PaywallView

/// Pro upgrade screen with Free vs Pro comparison and pricing cards.
struct PaywallView: View {
    @Environment(StoreKitManager.self) private var storeKit
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: String = StoreKitManager.yearlyID

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
            ComparisonRow(feature: "Caption Styles", free: "3", pro: "All 10+")
            ComparisonRow(feature: "Word Highlight", free: "No", pro: "Yes", proIsGood: true)
            ComparisonRow(feature: "Priority Support", free: "No", pro: "Yes", proIsGood: true)
        }
    }

    // MARK: - Pricing

    private var pricingSection: some View {
        HStack(spacing: 12) {
            // Monthly
            PricingCard(
                price: storeKit.monthlyProduct?.displayPrice ?? "$2.99",
                period: "/month",
                badge: nil,
                isSelected: selectedPlan == StoreKitManager.monthlyID,
                isGradient: false
            )
            .onTapGesture { selectedPlan = StoreKitManager.monthlyID }

            // Yearly
            PricingCard(
                price: storeKit.yearlyProduct?.displayPrice ?? "$14.99",
                period: "/year",
                badge: "SAVE 58%",
                isSelected: selectedPlan == StoreKitManager.yearlyID,
                isGradient: true
            )
            .onTapGesture { selectedPlan = StoreKitManager.yearlyID }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            Task {
                let product = selectedPlan == StoreKitManager.yearlyID
                    ? storeKit.yearlyProduct
                    : storeKit.monthlyProduct

                if let product {
                    _ = try? await storeKit.purchase(product)
                    if storeKit.isPro {
                        dismiss()
                    }
                }
            }
        } label: {
            Text("Start Free Trial")
                .font(.headline)
                .foregroundColor(.white)
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
        }
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
