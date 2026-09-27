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
    /// A purchase sheet is up or a purchase is being confirmed. A second tap
    /// here used to start a second purchase.
    case purchasing
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
    /// Why this paywall is up. The paywall logs `paywall_shown` itself, once,
    /// so callers pass the reason instead of logging it a second time.
    let trigger: PaywallTrigger
    @State private var selectedPlan: String = StoreKitManager.yearlyID
    @State private var purchaseError: String?
    @State private var isRestoring = false
    @State private var isPurchasing = false
    @State private var restoreMessage: String?
    /// Whether StoreKit says this user may still take the introductory offer.
    /// Assumed false until asked, so we never promise a trial we cannot give.
    @State private var isEligibleForIntroOffer = false

    init(trigger: PaywallTrigger = .manual) {
        self.trigger = trigger
    }

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
    static func ctaState(
        isLoading: Bool,
        hasProduct: Bool,
        error: String?,
        isPurchasing: Bool = false
    ) -> PaywallCTAState {
        if isPurchasing { return .purchasing }
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

    /// What to tell the user after a purchase attempt that did not close the
    /// paywall. `nil` when there is nothing to say.
    static func purchaseMessage(for outcome: PurchaseOutcome) -> String? {
        switch outcome {
        case .purchased, .cancelled:
            return nil
        case .pending:
            return "Your purchase is waiting for approval. Pro unlocks as soon as it's approved."
        }
    }

    /// What to tell the user after Restore Purchases. `nil` for a restore that
    /// worked (the paywall closes) or that the user cancelled.
    static func restoreMessage(for outcome: RestoreOutcome) -> String? {
        switch outcome {
        case .restored, .cancelled:
            return nil
        case .nothingToRestore:
            return "No active subscription was found for this Apple ID."
        case let .failed(reason):
            return "Could not restore purchases. \(reason)"
        }
    }

    /// The words on the primary button.
    ///
    /// It used to read "Start Free Trial" unconditionally. A returning
    /// subscriber who had already consumed the introductory offer — or any
    /// user at all, if the product never carried one — tapped a promise of a
    /// free trial and was charged instead.
    static func ctaTitle(hasFreeTrial: Bool) -> String {
        hasFreeTrial ? "Start Free Trial" : "Subscribe"
    }

    /// How a subscription period reads inside a sentence.
    static func periodName(unit: Product.SubscriptionPeriod.Unit, value: Int) -> String {
        let singular: String
        switch unit {
        case .day: singular = "day"
        case .week: singular = "week"
        case .month: singular = "month"
        case .year: singular = "year"
        @unknown default: singular = "period"
        }
        // "per year", not "per 1 year" — but "7 days" has to keep its count.
        return value == 1 ? singular : "\(value) \(singular)s"
    }

    /// How long something lasts, always with its count: "1 week", "7 days".
    ///
    /// `periodName` drops a count of one because it follows "per". A trial
    /// follows "Free for", and the shipped one-week trial read "Free for
    /// week, then …".
    static func durationName(unit: Product.SubscriptionPeriod.Unit, value: Int) -> String {
        let name = periodName(unit: unit, value: value)
        return value == 1 ? "1 \(name)" : name
    }

    /// What the user will actually be charged, and when.
    ///
    /// The screen said this nowhere. A trial in particular has to name the
    /// price that follows it, both because App Review 3.1.2 requires it and
    /// because it is the number the decision turns on. Returns `nil` when the
    /// price is unknown: silence beats a sentence with a hole in it.
    static func priceDisclosure(
        displayPrice: String?,
        periodName: String,
        freeTrialName: String?
    ) -> String? {
        guard let displayPrice else { return nil }
        let recurring = "\(displayPrice) per \(periodName). Cancel anytime."
        guard let freeTrialName else { return recurring }
        return "Free for \(freeTrialName), then \(recurring)"
    }

    /// One row of the Free-vs-Pro table.
    struct ComparisonClaim: Equatable {
        let feature: String
        let free: String
        let pro: String
        var proIsGood: Bool = false
    }

    // MARK: - Legal

    struct LegalLink {
        let title: String
        let url: URL
    }

    /// Apple's standard EULA. An app that does not supply its own Terms of Use
    /// is licensed under this one, and linking it is explicitly allowed —
    /// which makes it the right answer for a solo developer with no lawyer.
    static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    /// The policy lives in this repository rather than on separate hosting.
    ///
    /// A privacy policy URL is a mandatory App Store Connect field *and* a
    /// mandatory in-app link under 3.1.2, and the usual failure is that the
    /// domain it points at lapses years later while the shipped binary keeps
    /// pointing at it. Keeping the document next to the code means the link is
    /// live the moment the commit lands, it is versioned with the behaviour it
    /// describes, and it cannot rot on its own.
    static let privacyPolicyURL = URL(
        string: "https://github.com/Lalit-khatri/CaptionsAI/blob/main/PRIVACY.md"
    )!

    /// Both documents, as data, so the footer's wiring can be asserted.
    ///
    /// The screen this replaces had a `Text("Terms & Privacy")` that looked
    /// finished and did nothing. Two constants that no view renders would be
    /// the same defect wearing a better hat, so the footer reads this array
    /// and a test checks it points at both.
    static var legalLinks: [LegalLink] {
        [
            LegalLink(title: "Terms of Use", url: termsOfUseURL),
            LegalLink(title: "Privacy Policy", url: privacyPolicyURL),
        ]
    }

    /// What the table claims, derived rather than written down.
    ///
    /// The Free column used to be hand-written and described an app that did
    /// not exist: two exports a day where the code allows five, and Free
    /// denied caption styles and word highlighting, neither of which is gated
    /// anywhere. Overstating what Pro adds is both an App Review 3.1.1 problem
    /// and a way of selling someone something they already have. The two rows
    /// that are not differences now say so plainly.
    ///
    /// Priority Support used to be a fifth row and is gone for the same
    /// reason. There is one feedback channel, it is on the same screens for
    /// everyone, it routes to the same mailbox, and the message carries no
    /// subscription marker — so a paid report is indistinguishable from a free
    /// one on arrival. A row here has to name a difference the code actually
    /// makes.
    static var comparisonRows: [ComparisonClaim] {
        [
            ComparisonClaim(
                feature: "Exports per day",
                free: "\(AppState.freeExportLimit)",
                pro: "Unlimited"
            ),
            ComparisonClaim(feature: "Watermark", free: "Yes", pro: "No", proIsGood: true),
            ComparisonClaim(
                feature: "Caption Styles",
                free: proStyleCountText,
                pro: proStyleCountText
            ),
            ComparisonClaim(feature: "Word Highlight", free: "Yes", pro: "Yes"),
        ]
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
            error: storeKit.error,
            isPurchasing: isPurchasing
        )
    }

    /// The selected plan's free trial, but only if this user can still take it.
    ///
    /// Eligibility is a question only StoreKit can answer, and only
    /// asynchronously, so it is resolved in a `.task` and cached. Defaulting
    /// to ineligible means the worst case is that we fail to advertise a trial
    /// the user could have had — the opposite mistake charges them.
    private var freeTrialName: String? {
        guard isEligibleForIntroOffer,
              let offer = selectedProduct?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else { return nil }
        return Self.durationName(unit: offer.period.unit, value: offer.period.value)
    }

    private var selectedPeriodName: String? {
        guard let period = selectedProduct?.subscription?.subscriptionPeriod else { return nil }
        return Self.periodName(unit: period.unit, value: period.value)
    }

    private var priceDisclosureText: String? {
        guard let periodName = selectedPeriodName else { return nil }
        return Self.priceDisclosure(
            displayPrice: selectedProduct?.displayPrice,
            periodName: periodName,
            freeTrialName: freeTrialName
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

                    // What this will actually cost, and when
                    disclosureMessage

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
                    // Icon-only, so VoiceOver would otherwise read the
                    // symbol name.
                    .accessibilityLabel(Self.closeLabel)
                }
            }
        }
        .onAppear {
            AnalyticsService.paywallShown(trigger)
        }
        // The launch-time fetch may have failed offline; opening the paywall
        // is the moment the user needs the products, so ask again.
        .task {
            if storeKit.needsProducts {
                await storeKit.loadProducts()
            }
        }
        // Keyed on the product id so this also runs on the nil-to-loaded
        // transition, not just when the user switches plan.
        .task(id: selectedProduct?.id) {
            guard let subscription = selectedProduct?.subscription else {
                isEligibleForIntroOffer = false
                return
            }
            isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
        }
    }

    // MARK: - Status

    /// The reason the button is not going to work, or the reason a tap did not
    /// result in a purchase. Both used to be recorded and never shown.
    @ViewBuilder
    private var statusMessage: some View {
        if let message = purchaseError ?? restoreMessage ?? unavailableMessage {
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
        }

        if unavailableMessage != nil {
            Button(Self.retryTitle) {
                Task { await storeKit.loadProducts() }
            }
            .font(.subheadline.bold())
        }
    }

    static let retryTitle = "Try Again"
    static let closeLabel = "Close"

    private var unavailableMessage: String? {
        if case let .unavailable(message) = ctaState { return message }
        return nil
    }

    /// The terms of the thing the button is about to do.
    @ViewBuilder
    private var disclosureMessage: some View {
        if let text = priceDisclosureText {
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
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
            ForEach(Self.comparisonRows, id: \.feature) { claim in
                ComparisonRow(
                    feature: claim.feature,
                    free: claim.free,
                    pro: claim.pro,
                    proIsGood: claim.proIsGood
                )
            }
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
            guard let product = selectedProduct, !isPurchasing else { return }
            Task {
                purchaseError = nil
                restoreMessage = nil
                isPurchasing = true
                defer { isPurchasing = false }
                do {
                    let outcome = try await storeKit.purchase(product)
                    if storeKit.isPro {
                        dismiss()
                    } else {
                        purchaseError = Self.purchaseMessage(for: outcome)
                    }
                } catch {
                    // Previously `try?`, which discarded the reason the
                    // purchase failed and left the screen looking idle.
                    purchaseError = error.localizedDescription
                }
            }
        } label: {
            Group {
                if ctaState == .loading || ctaState == .purchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(Self.ctaTitle(hasFreeTrial: freeTrialName != nil))
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
            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .disabled(isRestoring)
            .font(.subheadline)
            .foregroundColor(.secondary)

            HStack(spacing: 16) {
                ForEach(Self.legalLinks, id: \.title) { link in
                    Link(link.title, destination: link.url)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.bottom, 32)
    }
}

// MARK: - Restore

private extension PaywallView {
    func restore() async {
        isRestoring = true
        restoreMessage = nil
        purchaseError = nil
        let outcome = await storeKit.restorePurchases()
        isRestoring = false

        if outcome == .restored {
            dismiss()
        } else {
            restoreMessage = Self.restoreMessage(for: outcome)
        }
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
