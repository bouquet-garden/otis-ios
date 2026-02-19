// PaywallViewModel.swift
// Otis — Views/Paywall/
//
// @Observable ViewModel driving PaywallView.
// All purchases are routed through SubscriptionManager — this VM never
// calls RevenueCat directly.
//
// Context enum drives headline copy, Otis state, and layout variants.
// Price strings are fetched from live RevenueCat offerings when available,
// falling back to hardcoded strings so the UI always renders.

import SwiftUI
import Observation

// MARK: - PaywallContext

extension PaywallViewModel {

    /// Describes why the paywall was shown. Drives copy and Otis state.
    enum PaywallContext: Hashable {

        /// Soft upsell — shown after first trip completes (First Trip Free exhausted).
        case softPostTrip

        /// Hard gate — user tapped the AI Suggestions banner while on Free tier.
        case hardAISuggestions

        /// Hard gate — user tapped stamp #4+ (stamps 1-3 are free previews).
        case hardStamps

        /// Hard gate — user tapped iCloud Sync toggle in settings.
        case hardSync

        /// Opened directly from Settings > Subscription row.
        case settings

        // MARK: Copy

        /// Large headline displayed at top of paywall.
        var headline: String {
            switch self {
            case .softPostTrip:
                return "Ready for your next adventure?"
            case .hardAISuggestions:
                return "Let Otis do the thinking."
            case .hardStamps:
                return "Collect every adventure."
            case .hardSync:
                return "Your lists, everywhere."
            case .settings:
                return "Pack Smarter. Every Trip."
            }
        }

        /// Smaller secondary line beneath headline.
        var subheadline: String {
            switch self {
            case .softPostTrip:
                return "Your first trip was on us. Keep Otis going."
            case .hardAISuggestions:
                return "AI packing suggestions are a Pro feature."
            case .hardStamps:
                return "Passport stamps unlock with Pro."
            case .hardSync:
                return "iCloud sync keeps your lists on every device."
            case .settings:
                return "Otis Pro unlocks the good stuff."
            }
        }

        /// Non-nil for hard paywalls — shown in a context header above the main card.
        var contextNote: String? {
            switch self {
            case .softPostTrip, .settings:
                return nil
            case .hardAISuggestions:
                return "Otis's AI suggestions are a Pro feature"
            case .hardStamps:
                return "Passport stamps beyond 3 require Pro"
            case .hardSync:
                return "iCloud sync is a Pro feature"
            }
        }

        /// Which Otis illustration to show.
        var otisState: OtisState {
            switch self {
            case .softPostTrip:
                return .napping   // gentle, non-urgent
            default:
                return .active    // excited, ready to help
            }
        }

        /// Whether the user can dismiss this paywall without upgrading.
        var isDismissible: Bool {
            switch self {
            case .softPostTrip, .settings:
                return true
            case .hardAISuggestions, .hardStamps, .hardSync:
                return true   // always dismissible — no dark patterns
            }
        }

        /// CTA label for the dismiss / maybe-later button.
        var dismissLabel: String {
            switch self {
            case .softPostTrip:
                return "Maybe Later"
            default:
                return "Not Now"
            }
        }
    }
}

// MARK: - PaywallViewModel

@Observable
final class PaywallViewModel {

    // MARK: - Dependencies

    let subscriptionManager: SubscriptionManager
    let context: PaywallContext

    // MARK: - Purchase State

    /// True while a purchase or restore network call is in flight.
    var isPurchasing: Bool = false

    /// Non-nil when a purchase attempt surfaces an error.
    var purchaseError: String? = nil

    /// Briefly true after a successful restore — triggers the success banner.
    var showRestoreSuccess: Bool = false

    /// True after any successful purchase — signals the presenting view to dismiss.
    var purchaseSucceeded: Bool = false

    // MARK: - Price Strings
    // Populated from live RevenueCat offerings; fall back to hardcoded strings.

    var annualPriceString: String = "$19.99 / year"
    var annualMonthlyBreakdown: String = "Less than $1.67 / month"
    var lifetimePriceString: String = "$59.99"

    /// True when RevenueCat reports the user is eligible for a trial on the annual plan.
    var isTrialEligible: Bool = false

    // MARK: - Init

    init(subscriptionManager: SubscriptionManager, context: PaywallContext) {
        self.subscriptionManager = subscriptionManager
        self.context = context
        Task { await loadOfferings() }
    }

    // MARK: - Computed

    /// Headline copy — delegated to context enum.
    var headline: String { context.headline }

    /// Subheadline copy — delegated to context enum.
    var subheadline: String { context.subheadline }

    /// Non-nil for hard paywalls — shown in a banner above main content.
    var contextNote: String? { context.contextNote }

    /// Which Otis illustration to use.
    var otisState: OtisState { context.otisState }

    /// "Best Value" badge on lifetime card — power-user signal.
    var showBestValueBadge: Bool {
        subscriptionManager.totalTripsCompleted >= 2
    }

    /// CTA button title — changes based on trial eligibility.
    var primaryCTATitle: String {
        if isTrialEligible { return "Start Free Trial" }
        return "Unlock Pro"
    }

    /// True when the user is already subscribed (paywall should auto-dismiss).
    var isAlreadyPro: Bool {
        subscriptionManager.isPro
    }

    // MARK: - Offerings Fetch

    /// Attempts to pull real price strings and trial eligibility from RevenueCat.
    /// Silently falls back to hardcoded strings on any failure.
    @MainActor
    func loadOfferings() async {
        do {
            let offerings = try await subscriptionManager.fetchOfferings()

            if let annualPackage = offerings?.current?.annual {
                let product = annualPackage.storeProduct
                annualPriceString = "\(product.localizedPriceString) / year"

                // Compute monthly breakdown
                if let price = product.price as Decimal?, price > 0 {
                    let monthly = price / 12
                    let formatter = NumberFormatter()
                    formatter.numberStyle = .currency
                    formatter.locale = product.priceLocale
                    if let formatted = formatter.string(from: monthly as NSDecimalNumber) {
                        annualMonthlyBreakdown = "Less than \(formatted) / month"
                    }
                }

                // Trial eligibility
                if let discount = product.introductoryDiscount,
                   discount.paymentMode == .freeTrial {
                    isTrialEligible = true
                }
            }

            if let lifetimePackage = offerings?.current?.lifetime {
                lifetimePriceString = lifetimePackage.storeProduct.localizedPriceString
            }

        } catch {
            // Silent fallback — hardcoded strings remain
        }
    }

    // MARK: - Purchase Actions

    /// Purchase the Pro Annual subscription.
    @MainActor
    func purchaseAnnual() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil

        do {
            try await subscriptionManager.purchaseProAnnual()
            purchaseSucceeded = true
        } catch {
            purchaseError = friendlyError(error)
        }

        isPurchasing = false
    }

    /// Purchase the Lifetime unlock.
    @MainActor
    func purchaseLifetime() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil

        do {
            try await subscriptionManager.purchaseLifetime()
            purchaseSucceeded = true
        } catch {
            purchaseError = friendlyError(error)
        }

        isPurchasing = false
    }

    /// Restore previous purchases.
    @MainActor
    func restorePurchases() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseError = nil

        do {
            try await subscriptionManager.restorePurchases()
            showRestoreSuccess = true

            // Auto-dismiss success banner after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showRestoreSuccess = false

            if isAlreadyPro { purchaseSucceeded = true }
        } catch {
            purchaseError = friendlyError(error)
        }

        isPurchasing = false
    }

    // MARK: - Helpers

    private func friendlyError(_ error: Error) -> String {
        let desc = error.localizedDescription
        if desc.contains("cancelled") || desc.contains("cancel") {
            return "Purchase cancelled."
        }
        if desc.contains("network") || desc.contains("internet") {
            return "No internet connection. Please try again."
        }
        return "Something went wrong. Please try again."
    }
}
