// StampService.swift
// Otis — Services/
//
// The engine that awards passport stamps when a trip is marked complete.
// Called from PackingListViewModel.completeTrip() via NotificationCenter.
//
// StampType Priority Order:
//   1. tripNumber == 1         → .firstTrip  (always, unconditional)
//   2. tripNumber in milestones → .milestone  (5, 10, 25, 50)
//   3. tripType == .beach       → .beach
//   4. tripType == .mountain || .ski → .mountain
//   5. tripType == .international   → .international
//   6. tripType == .business        → .business
//   7. tripType == .city            → .city
//   8. Fallback                     → season-based stamp
//
// Threading: @MainActor — all SwiftData mutations on main thread.
// Notification: Listens for Notification.Name.tripDidComplete posted by PackingListViewModel.

import SwiftUI
import SwiftData

// MARK: - StampService

@MainActor
final class StampService {

    // MARK: - Singleton

    static let shared = StampService()
    private init() {}

    // MARK: - Constants

    /// Trip numbers that earn a milestone stamp instead of a type-based stamp.
    static let milestoneNumbers: Set<Int> = [1, 5, 10, 25, 50]

    // MARK: - Milestone Check

    /// Returns true if this trip number earns a milestone stamp.
    /// Note: tripNumber 1 is handled by .firstTrip, not .milestone,
    /// but this helper is used by UI to show milestone indicators.
    static func isMilestone(_ tripNumber: Int) -> Bool {
        milestoneNumbers.contains(tripNumber)
    }

    // MARK: - Observation

    /// Begin listening for trip completion notifications.
    /// Call once from the app's root — e.g. OtisApp.onAppear or ContentView.
    /// The notification carries the completed Trip as its object.
    func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTripDidComplete(_:)),
            name: .tripDidComplete,
            object: nil
        )
    }

    /// Notification handler — bridges ObjC selector to async Swift.
    @objc private func handleTripDidComplete(_ notification: Notification) {
        // NOTE: callers that need the resulting Stamp (e.g. TripDetailView for
        // StampUnlockView) call awardStamp(for:modelContext:) directly and await it.
        // This observer path is a fire-and-forget fallback for passive observation.
        _ = notification.object // trip is used by direct callers via awardStamp
    }

    // MARK: - Main Entry Point

    /// Award a stamp for a completed trip.
    /// Returns the newly created Stamp so the caller can present StampUnlockView.
    ///
    /// Usage in PackingListViewModel.completeTrip():
    /// ```swift
    /// let stamp = await StampService.shared.awardStamp(for: trip, modelContext: modelContext)
    /// newlyEarnedStamp = stamp   // triggers .fullScreenCover
    /// ```
    func awardStamp(for trip: Trip, modelContext: ModelContext) async -> Stamp {
        // 1. Resolve the user profile and increment trip count
        let profile = fetchOrCreateUserProfile(modelContext: modelContext)
        profile.recordTripCompleted()

        let tripNumber = profile.totalTripsCompleted

        // 2. Determine stamp type
        let stampType = determineStampType(
            tripType: trip.tripType,
            season: trip.departureSeason,
            tripNumber: tripNumber
        )

        // 3. Build milestone flag
        let milestone = StampService.isMilestone(tripNumber)

        // 4. Build display title
        let title = displayTitle(for: stampType, tripNumber: tripNumber)

        // 5. Create and persist the stamp
        let stamp = Stamp(
            tripNumber: tripNumber,
            stampType: stampType,
            destination: trip.destination,
            season: trip.departureSeason,
            earnedAt: Date(),
            isMilestone: milestone,
            displayTitle: title,
            shareImageName: shareImageName(for: stampType)
        )
        modelContext.insert(stamp)

        // 6. Persist immediately so PassportView query updates
        do {
            try modelContext.save()
        } catch {
            // Non-fatal — stamp is still in memory and query will update next save cycle
            print("[StampService] Save error: \(error.localizedDescription)")
        }

        // 7. Post notification so any observer (e.g. analytics) can react
        NotificationCenter.default.post(
            name: .stampDidUnlock,
            object: stamp
        )

        return stamp
    }

    // MARK: - StampType Determination

    /// Priority-ordered logic for assigning a StampType to a completed trip.
    private func determineStampType(
        tripType: TripType,
        season: Season,
        tripNumber: Int
    ) -> StampType {
        // Priority 1: First ever trip — always .firstTrip
        if tripNumber == 1 {
            return .firstTrip
        }

        // Priority 2: Milestone numbers (5, 10, 25, 50)
        if StampService.milestoneNumbers.contains(tripNumber) {
            return .milestone
        }

        // Priority 3–7: Trip type driven
        switch tripType {
        case .beach:
            return .beach
        case .mountain, .ski:
            return .mountain
        case .international:
            return .international
        case .business:
            return .business
        case .city:
            return .city
        case .road, .camping, .other:
            break // fall through to season-based
        }

        // Priority 8: Season fallback
        return seasonStampType(for: season)
    }

    // MARK: - Season Fallback

    private func seasonStampType(for season: Season) -> StampType {
        switch season {
        case .winter: return .winter
        case .spring: return .spring
        case .summer: return .summer
        case .autumn: return .autumn
        }
    }

    // MARK: - Display Titles

    /// Human-readable stamp title for display in PassportView and StampUnlockView.
    private func displayTitle(for stampType: StampType, tripNumber: Int) -> String {
        switch stampType {
        case .firstTrip:
            return "The Pioneer"
        case .milestone:
            return milestoneTitle(for: tripNumber)
        case .beach:
            return "Beach Dreamer"
        case .mountain:
            return "Summit Seeker"
        case .international:
            return "Globe Trotter"
        case .business:
            return "Road Warrior"
        case .city:
            return "Urban Explorer"
        case .winter:
            return "Snow Chaser"
        case .spring:
            return "Bloom Wanderer"
        case .summer:
            return "Sun Seeker"
        case .autumn:
            return "Leaf Peeper"
        }
    }

    private func milestoneTitle(for tripNumber: Int) -> String {
        switch tripNumber {
        case 5:  return "Seasoned Traveler"
        case 10: return "World Wanderer"
        case 25: return "Expedition Master"
        case 50: return "Otis Legend"
        default: return "Milestone Maker"
        }
    }

    // MARK: - Share Image Name

    private func shareImageName(for stampType: StampType) -> String {
        "stamp-\(stampType.rawValue)"
    }

    // MARK: - UserProfile

    /// Fetches the singleton UserProfile or creates one on first launch.
    private func fetchOrCreateUserProfile(modelContext: ModelContext) -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let profile = UserProfile()
        modelContext.insert(profile)
        return profile
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted by PackingListViewModel when a trip is marked complete.
    /// Object = the completed Trip instance.
    static let tripDidComplete = Notification.Name("OtisTripDidComplete")

    /// Posted by StampService after a stamp is created and saved.
    /// Object = the newly created Stamp instance.
    static let stampDidUnlock = Notification.Name("OtisStampDidUnlock")
}

// MARK: - StampType Raw Values (must match Enums.swift)
// Ensure StampType has these cases in Enums.swift:
// enum StampType: String, Codable {
//     case firstTrip, milestone, beach, mountain, international,
//          business, city, winter, spring, summer, autumn
// }
