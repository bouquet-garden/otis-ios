// UserProfile.swift
// Otis
//
// Singleton @Model representing the current user's account state.
// There is exactly ONE UserProfile record per app install. It is created
// on first launch by AppBootstrapper and never duplicated.
//
// The fixed UUID constant (userProfileID) ensures that SwiftData can always
// fetch this record with a predicate rather than a full scan, and prevents
// accidental duplicate creation.
//
// Subscription state is read here but written by RevenueCatService after
// a purchase or restore. Views must always read effectiveSubscriptionStatus
// (not subscriptionStatus directly) to correctly honour the First Trip Free
// mechanic.

import Foundation
import SwiftData

// MARK: - Constants

extension UserProfile {
    /// The fixed UUID used for the singleton UserProfile record.
    /// Hardcoded so we can always #Predicate fetch it without a full scan.
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

// MARK: - UserProfile

@Model
final class UserProfile {

    // MARK: - Stored Properties

    /// Fixed UUID. Always equals UserProfile.singletonID.
    @Attribute(.unique)
    var id: UUID

    /// The user's actual RevenueCat entitlement tier.
    /// Do NOT read this directly in feature-gate checks — use
    /// effectiveSubscriptionStatus which layers in the First Trip Free logic.
    var subscriptionStatus: UserSubscriptionStatus

    /// True once the user has completed (not just created) their first trip.
    /// Flipped by TripService when totalTripsCompleted reaches 1.
    var isFirstTripComplete: Bool

    /// Running count of trips the user has fully completed (marked done).
    /// Incremented by TripService.completeTrip(_:). Used by StampService
    /// to assign trip numbers and detect milestones.
    var totalTripsCompleted: Int

    /// True for brand-new users. The first trip they create fires the full
    /// Pro experience automatically — AI, stamps, expressive Otis — at zero cost.
    /// Remains true until the first trip is COMPLETED (not just created).
    /// After completion, the soft paywall surfaces for trip #2.
    var isFirstTripFreeActive: Bool

    /// Set to true after the first-trip Pro experience has been consumed.
    /// Prevents the free trial from firing a second time if the user deletes
    /// and recreates their first trip.
    var proTrialUsed: Bool

    /// The RevenueCat anonymous or identified customer ID. Set by
    /// RevenueCatService after SDK initialisation. Used to link purchases
    /// across devices when the user signs in with Apple.
    var revenueCatCustomerID: String?

    /// Timestamp of record creation (= app first launch date).
    var createdAt: Date

    /// Updated every time the app comes to foreground. Used for
    /// between-trip re-engagement nudge logic (30-day inactivity check).
    var lastOpenedAt: Date

    // MARK: - Initializer

    init(
        id: UUID = UserProfile.singletonID,
        subscriptionStatus: UserSubscriptionStatus = .free,
        isFirstTripComplete: Bool = false,
        totalTripsCompleted: Int = 0,
        isFirstTripFreeActive: Bool = true,
        proTrialUsed: Bool = false,
        revenueCatCustomerID: String? = nil,
        createdAt: Date = Date(),
        lastOpenedAt: Date = Date()
    ) {
        self.id = id
        self.subscriptionStatus = subscriptionStatus
        self.isFirstTripComplete = isFirstTripComplete
        self.totalTripsCompleted = totalTripsCompleted
        self.isFirstTripFreeActive = isFirstTripFreeActive
        self.proTrialUsed = proTrialUsed
        self.revenueCatCustomerID = revenueCatCustomerID
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
    }

    // MARK: - Computed: Effective Subscription Status

    /// The subscription status that ALL feature-gate checks must use.
    ///
    /// Logic:
    ///   - If the user's first trip is in progress (isFirstTripFreeActive = true)
    ///     and the trial hasn't been consumed yet (proTrialUsed = false),
    ///     return .proAnnual so every Pro feature fires.
    ///   - Otherwise, return the real RevenueCat-backed subscriptionStatus.
    ///
    /// This means a brand-new free user gets full Pro on trip #1 with zero
    /// friction — no paywall, no credit card, no prompt. The soft paywall
    /// surfaces only after they complete that first trip.
    var effectiveSubscriptionStatus: UserSubscriptionStatus {
        if isFirstTripFreeActive && !proTrialUsed {
            return .proAnnual
        }
        return subscriptionStatus
    }

    // MARK: - Computed: Feature Gates (via effective status)

    /// Convenience pass-through so call sites don't need two hops.
    var aiSuggestionsEnabled: Bool         { effectiveSubscriptionStatus.aiSuggestionsEnabled }
    var stampUnlocksEnabled: Bool          { effectiveSubscriptionStatus.stampUnlocksEnabled }
    var iCloudSyncEnabled: Bool            { effectiveSubscriptionStatus.iCloudSyncEnabled }
    var liveActivityEnabled: Bool          { effectiveSubscriptionStatus.liveActivityEnabled }
    var savedProfilesEnabled: Bool         { effectiveSubscriptionStatus.savedProfilesEnabled }
    var tripHistoryLimit: Int?             { effectiveSubscriptionStatus.tripHistoryLimit }

    // MARK: - Computed: Otis State

    /// The Otis mascot state appropriate for the user's current context.
    /// Views observe this to swap animation assets without conditional logic.
    ///
    /// Rules:
    ///   - If the user has an active trip (evaluated externally), call .active
    ///     from the view layer — this computed property cannot see active trips.
    ///   - If the user is free tier with no active trip → .napping
    ///   - Otherwise → .calm
    ///
    /// Note: .celebration and .active are set by views/ViewModels in response
    /// to specific events (list completion, stamp unlock) — not derived here.
    var defaultOtisState: OtisState {
        if !effectiveSubscriptionStatus.isProUser {
            return .napping
        }
        return .calm
    }

    // MARK: - Computed: Next Milestone

    /// The next milestone trip number the user is working toward.
    /// Returns nil when the user has passed the highest milestone (50).
    var nextMilestone: Int? {
        let milestones = [1, 5, 10, 25, 50]
        return milestones.first { $0 > totalTripsCompleted }
    }

    /// How many trips remain until the next milestone. nil if no next milestone.
    var tripsUntilNextMilestone: Int? {
        guard let next = nextMilestone else { return nil }
        return next - totalTripsCompleted
    }

    // MARK: - Computed: Days Since Last Open

    /// Days elapsed since lastOpenedAt. Used by the between-trip nudge
    /// scheduler to fire the single re-engagement notification at 30 days.
    var daysSinceLastOpen: Int {
        Calendar.current.dateComponents([.day], from: lastOpenedAt, to: Date()).day ?? 0
    }

    // MARK: - Mutation Helpers

    /// Call when the app enters foreground. Updates lastOpenedAt.
    func recordAppOpen() {
        lastOpenedAt = Date()
    }

    /// Call when a trip is completed. Increments the counter and manages
    /// the First Trip Free state machine.
    ///
    /// - Parameter isFirstTrip: Pass true only for the very first trip
    ///   completed on this device. TripService is responsible for tracking this.
    func recordTripCompleted(isFirstTrip: Bool) {
        totalTripsCompleted += 1
        if isFirstTrip {
            isFirstTripComplete = true
            // Deactivate the free trial — Pro features require a subscription
            // from trip #2 onwards unless the user purchases.
            isFirstTripFreeActive = false
            proTrialUsed = true
        }
    }

    /// Call after RevenueCat confirms a successful purchase or restore.
    func updateSubscription(status: UserSubscriptionStatus, customerID: String? = nil) {
        subscriptionStatus = status
        if let customerID {
            revenueCatCustomerID = customerID
        }
        // If the user purchases during the free trial, deactivate the trial
        // so effectiveSubscriptionStatus reads the real purchased status.
        if status.isProUser {
            isFirstTripFreeActive = false
        }
    }
}

// MARK: - UserProfile + CustomDebugStringConvertible

extension UserProfile: CustomDebugStringConvertible {
    var debugDescription: String {
        """
        UserProfile {
          id: \(id)
          subscriptionStatus: \(subscriptionStatus.rawValue)
          effectiveStatus: \(effectiveSubscriptionStatus.rawValue)
          totalTripsCompleted: \(totalTripsCompleted)
          isFirstTripFreeActive: \(isFirstTripFreeActive)
          proTrialUsed: \(proTrialUsed)
          nextMilestone: \(nextMilestone.map(String.init) ?? "none")
          daysSinceLastOpen: \(daysSinceLastOpen)
        }
        """
    }
}
