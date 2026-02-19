// SubscriptionManager.swift
// Otis — RevenueCat subscription state manager
//
// Injected into the SwiftUI environment as @EnvironmentObject.
// Single source of truth for subscription status throughout the app.
//
// Usage:
//   @EnvironmentObject var subscriptionManager: SubscriptionManager
//   if subscriptionManager.isPro { ... }

import Foundation
import RevenueCat
import Combine
import SwiftUI

@MainActor
final class SubscriptionManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var status: UserSubscriptionStatus = .free
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    /// True when the user has an active Pro or Lifetime entitlement.
    var isPro: Bool { status.isPro }

    /// True when the user is on the Lifetime plan specifically.
    var isLifetime: Bool { status == .lifetime }

    // MARK: - First Trip Free State

    /// The total number of completed trips. Used to gate "First Trip Free" logic.
    @Published private(set) var completedTripCount: Int = 0

    /// First trip gets full Pro automatically — no payment, no friction.
    /// Returns true if this is effectively the user's first trip and they haven't paid yet.
    var isFirstTripFree: Bool {
        AppConfig.firstTripFreeEnabled && completedTripCount == 0 && !isPro
    }

    /// Whether the user should see the soft paywall (after first trip completes).
    var shouldShowSoftPaywall: Bool {
        AppConfig.firstTripFreeEnabled && completedTripCount >= 1 && !isPro
    }

    // MARK: - RevenueCat Offerings Cache

    @Published private(set) var currentOffering: Offering? = nil

    // MARK: - Private

    private var statusObserver: AnyCancellable?

    // MARK: - Init

    init() {
        observeSubscriptionNotifications()
        Task { await refreshSubscriptionStatus() }
    }

    // MARK: - Public API

    /// Refresh subscription status from RevenueCat. Call on app foreground.
    func refreshSubscriptionStatus() async {
        guard !AppConfig.revenueCatAPIKey.isEmpty else {
            // Running without RevenueCat (dev mode) — default to free.
            status = .free
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateStatus(from: customerInfo)

            // Pre-fetch offerings so paywall loads instantly.
            let offerings = try await Purchases.shared.offerings()
            currentOffering = offerings.current
        } catch {
            errorMessage = "Could not verify subscription. Please check your connection."
            print("Otis [SubscriptionManager]: Error refreshing status — \(error)")
        }

        isLoading = false
    }

    /// Purchase the Pro Annual subscription.
    /// - Returns: True if purchase succeeded.
    @discardableResult
    func purchaseProAnnual() async -> Bool {
        return await purchase(productID: AppConfig.proAnnualProductID)
    }

    /// Purchase the Lifetime plan.
    /// - Returns: True if purchase succeeded.
    @discardableResult
    func purchaseLifetime() async -> Bool {
        return await purchase(productID: AppConfig.lifetimeProductID)
    }

    /// Restore previous purchases (required by App Store guidelines).
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateStatus(from: customerInfo)
        } catch {
            errorMessage = "Could not restore purchases. Please try again."
            print("Otis [SubscriptionManager]: Restore failed — \(error)")
        }

        isLoading = false
    }

    /// Update the completed trip count. Called by StampService after a trip completes.
    func recordTripCompletion() {
        completedTripCount += 1
    }

    // MARK: - Private Helpers

    private func purchase(productID: String) async -> Bool {
        guard !AppConfig.revenueCatAPIKey.isEmpty else {
            print("Otis [SubscriptionManager]: Cannot purchase — RevenueCat not configured.")
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            // Find the package matching the requested product ID.
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current,
                  let package = offering.availablePackages.first(where: {
                      $0.storeProduct.productIdentifier == productID
                  }) else {
                errorMessage = "Product not available. Please try again later."
                isLoading = false
                return false
            }

            let (_, customerInfo, _) = try await Purchases.shared.purchase(package: package)
            updateStatus(from: customerInfo)
            isLoading = false
            return isPro
        } catch {
            if (error as NSError).code != 2 { // 2 = user cancelled — not an error to surface
                errorMessage = "Purchase failed. Please try again."
            }
            print("Otis [SubscriptionManager]: Purchase failed — \(error)")
            isLoading = false
            return false
        }
    }

    private func updateStatus(from customerInfo: CustomerInfo) {
        let proEntitlement = customerInfo.entitlements[AppConfig.proEntitlementID]

        if proEntitlement?.isActive == true {
            // Distinguish lifetime from subscription based on product ID.
            if proEntitlement?.productIdentifier == AppConfig.lifetimeProductID {
                status = .lifetime
            } else {
                status = .pro
            }
        } else {
            status = .free
        }

        print("Otis [SubscriptionManager]: Status updated → \(status.displayName)")
    }

    private func observeSubscriptionNotifications() {
        statusObserver = NotificationCenter.default
            .publisher(for: .subscriptionStatusDidChange)
            .compactMap { $0.object as? CustomerInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] customerInfo in
                self?.updateStatus(from: customerInfo)
            }
    }
}

// MARK: - Feature Gate Helper

extension SubscriptionManager {

    /// Check if a Pro feature is accessible. Takes "First Trip Free" into account.
    /// - Parameter feature: The feature being gated.
    /// - Returns: True if the user may access it.
    func canAccess(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        if feature.availableOnFirstTripFree && isFirstTripFree { return true }
        return false
    }
}

// MARK: - ProFeature Enum

enum ProFeature {
    case aiSuggestions
    case passportStamps
    case savedProfiles
    case fullTripHistory
    case iCloudSync
    case liveActivity
    case expressiveOtis

    /// Features unlocked during the "First Trip Free" trial.
    var availableOnFirstTripFree: Bool {
        switch self {
        case .aiSuggestions, .passportStamps, .expressiveOtis, .liveActivity:
            return true
        case .savedProfiles, .fullTripHistory, .iCloudSync:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .aiSuggestions:  return "AI Packing Suggestions"
        case .passportStamps: return "Passport Stamps"
        case .savedProfiles:  return "Saved Packing Profiles"
        case .fullTripHistory: return "Full Trip History"
        case .iCloudSync:     return "iCloud Sync"
        case .liveActivity:   return "Live Activity"
        case .expressiveOtis: return "Expressive Otis"
        }
    }
}
