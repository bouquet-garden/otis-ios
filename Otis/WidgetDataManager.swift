// WidgetDataManager.swift
// Main App Target — Services/
//
// Bridge between the main Otis app and the OtisWidget extension.
// Writes trip + subscription data to a shared AppGroup UserDefaults container
// so the widget extension can read it without SwiftData access.
//
// Call sites:
//   PackingListViewModel.toggleItem()         → WidgetDataManager.shared.updateWidgetData(...)
//   PackingListViewModel.completeTrip()       → WidgetDataManager.shared.updateWidgetData(...)
//   TripCreationViewModel.createTrip()        → WidgetDataManager.shared.updateWidgetData(...)
//   TripDetailViewModel (on active trip set)  → WidgetDataManager.shared.updateWidgetData(...)
//
// Deep link handling (add to OtisApp.swift):
//   .onOpenURL { url in AppRouter.shared.handle(url) }
//
// AppGroup entitlement required in BOTH targets:
//   com.apple.security.application-groups = ["group.com.bouquetgarden.otis"]

import Foundation
import WidgetKit

// MARK: - AppGroup Keys (mirrors OtisWidget/OtisWidget.swift constants)

private enum WidgetKey {
    static let suiteName            = "group.com.bouquetgarden.otis"
    static let tripName             = "widget_tripName"
    static let destination          = "widget_destination"
    static let tripID               = "widget_tripID"
    static let packingPercentage    = "widget_packingPercentage"
    static let packedCount          = "widget_packedCount"
    static let totalCount           = "widget_totalCount"
    static let departureDate        = "widget_departureDate"        // stored as TimeInterval
    static let stampCount           = "widget_stampCount"
    static let subscriptionStatus   = "widget_subscriptionStatus"   // "free" | "pro" | "lifetime"
    static let isCompleted          = "widget_isCompleted"
    static let lastPackedItem       = "widget_lastPackedItem"
}

// MARK: - Subscription Status (mirrors Enums.swift — use your actual type in production)

/// Lightweight mirror of UserSubscriptionStatus used here to avoid importing SwiftData models.
/// Replace with your real enum if it's accessible from a shared framework.
public enum WidgetSubscriptionStatus: String {
    case free
    case pro
    case lifetime

    var rawValue: String {
        switch self {
        case .free:     return "free"
        case .pro:      return "pro"
        case .lifetime: return "lifetime"
        }
    }
}

// MARK: - Widget Data Snapshot

/// Lightweight snapshot of the data written to AppGroup storage.
/// Mirrors `OtisWidgetEntry` in the widget extension (no direct dependency).
public struct WidgetDataSnapshot {
    public let tripName: String
    public let destination: String
    public let tripID: String
    public let packingPercentage: Double
    public let packedCount: Int
    public let totalCount: Int
    public let departureDate: Date?
    public let stampCount: Int
    public let subscriptionStatus: String
    public let isCompleted: Bool
    public let lastPackedItem: String?
}

// MARK: - Widget Data Manager

public final class WidgetDataManager {

    // MARK: Singleton

    public static let shared = WidgetDataManager()
    private init() {}

    // MARK: Shared defaults

    private let defaults: UserDefaults = {
        guard let suite = UserDefaults(suiteName: WidgetKey.suiteName) else {
            // This will only fail if the AppGroup entitlement is missing.
            // In that case fall back to standard defaults so the app doesn't crash,
            // but widgets will show stale / empty data.
            assertionFailure(
                "[WidgetDataManager] AppGroup '\(WidgetKey.suiteName)' is not configured. " +
                "Add the App Groups capability to both the main app and OtisWidget targets."
            )
            return .standard
        }
        return suite
    }()

    // MARK: - Write

    /// Write all widget-relevant data from an active trip to the shared AppGroup container,
    /// then ask WidgetKit to reload all timelines so widgets update immediately.
    ///
    /// - Parameters:
    ///   - trip:               The currently active trip, or `nil` to clear widget state.
    ///   - stampCount:         Total stamps the user has collected.
    ///   - subscriptionStatus: The user's current subscription tier.
    ///   - lastPackedItem:     The most recently checked item name (optional, for Live Activity).
    public func updateWidgetData(
        tripName: String?,
        destination: String?,
        tripID: String?,
        packingPercentage: Double,
        packedCount: Int,
        totalCount: Int,
        departureDate: Date?,
        isCompleted: Bool,
        stampCount: Int,
        subscriptionStatus: WidgetSubscriptionStatus,
        lastPackedItem: String? = nil
    ) {
        defaults.set(tripName ?? "",                forKey: WidgetKey.tripName)
        defaults.set(destination ?? "",             forKey: WidgetKey.destination)
        defaults.set(tripID ?? "",                  forKey: WidgetKey.tripID)
        defaults.set(packingPercentage,             forKey: WidgetKey.packingPercentage)
        defaults.set(packedCount,                   forKey: WidgetKey.packedCount)
        defaults.set(totalCount,                    forKey: WidgetKey.totalCount)
        defaults.set(isCompleted,                   forKey: WidgetKey.isCompleted)
        defaults.set(stampCount,                    forKey: WidgetKey.stampCount)
        defaults.set(subscriptionStatus.rawValue,   forKey: WidgetKey.subscriptionStatus)

        if let dep = departureDate {
            defaults.set(dep.timeIntervalSince1970, forKey: WidgetKey.departureDate)
        } else {
            defaults.removeObject(forKey: WidgetKey.departureDate)
        }

        if let item = lastPackedItem {
            defaults.set(item, forKey: WidgetKey.lastPackedItem)
        } else {
            defaults.removeObject(forKey: WidgetKey.lastPackedItem)
        }

        // Flush synchronously so widget provider reads fresh data
        defaults.synchronize()

        // Tell WidgetKit to invalidate all timelines — provider.getTimeline() will be called
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Convenience overload that accepts a `WidgetDataSnapshot` directly.
    public func updateWidgetData(from snapshot: WidgetDataSnapshot) {
        let status = WidgetSubscriptionStatus(rawValue: snapshot.subscriptionStatus) ?? .free
        updateWidgetData(
            tripName: snapshot.tripName,
            destination: snapshot.destination,
            tripID: snapshot.tripID,
            packingPercentage: snapshot.packingPercentage,
            packedCount: snapshot.packedCount,
            totalCount: snapshot.totalCount,
            departureDate: snapshot.departureDate,
            isCompleted: snapshot.isCompleted,
            stampCount: snapshot.stampCount,
            subscriptionStatus: status,
            lastPackedItem: snapshot.lastPackedItem
        )
    }

    /// Clear all widget data (e.g. on sign-out or when no trips exist).
    public func clearWidgetData() {
        let keys: [String] = [
            WidgetKey.tripName, WidgetKey.destination, WidgetKey.tripID,
            WidgetKey.packingPercentage, WidgetKey.packedCount, WidgetKey.totalCount,
            WidgetKey.departureDate, WidgetKey.isCompleted, WidgetKey.stampCount,
            WidgetKey.subscriptionStatus, WidgetKey.lastPackedItem
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Read

    /// Read the current widget data snapshot from shared AppGroup storage.
    /// Useful for debugging or pre-populating UI that mirrors widget state.
    public func readWidgetData() -> WidgetDataSnapshot {
        var departureDate: Date?
        let interval = defaults.double(forKey: WidgetKey.departureDate)
        if interval > 0 {
            departureDate = Date(timeIntervalSince1970: interval)
        }

        return WidgetDataSnapshot(
            tripName:           defaults.string(forKey: WidgetKey.tripName) ?? "",
            destination:        defaults.string(forKey: WidgetKey.destination) ?? "",
            tripID:             defaults.string(forKey: WidgetKey.tripID) ?? "",
            packingPercentage:  defaults.double(forKey: WidgetKey.packingPercentage),
            packedCount:        defaults.integer(forKey: WidgetKey.packedCount),
            totalCount:         defaults.integer(forKey: WidgetKey.totalCount),
            departureDate:      departureDate,
            stampCount:         defaults.integer(forKey: WidgetKey.stampCount),
            subscriptionStatus: defaults.string(forKey: WidgetKey.subscriptionStatus) ?? "free",
            isCompleted:        defaults.bool(forKey: WidgetKey.isCompleted),
            lastPackedItem:     defaults.string(forKey: WidgetKey.lastPackedItem)
        )
    }

    // MARK: - Widget Kind Invalidation

    /// Reload only the packing progress widgets (e.g. after a single item toggle).
    /// More efficient than reloadAllTimelines() when stamp count hasn't changed.
    public func reloadPackingWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "OtisPackingWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "OtisSimpleWidget")
    }

    /// Reload only the stamp widget (e.g. after a new stamp is unlocked).
    public func reloadStampWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "OtisStampWidget")
    }
}

// MARK: - Deep Link Router

/// Handles `otis://` URL scheme routing from widget taps.
/// Register in OtisApp.swift:
///
///     WindowGroup {
///         ContentView()
///             .onOpenURL { url in AppRouter.shared.handle(url) }
///     }
public final class AppRouter: ObservableObject {

    public static let shared = AppRouter()
    private init() {}

    /// The deep link destination to navigate to (observed by ContentView / root coordinator).
    @Published public var pendingDeepLink: OtisDeepLink?

    public func handle(_ url: URL) {
        guard url.scheme == "otis" else { return }

        switch url.host {
        case "trip":
            let tripID = url.pathComponents.dropFirst().first ?? ""
            if tripID.isEmpty {
                // Graceful fallback — open app root if trip ID is missing
                pendingDeepLink = .root
            } else {
                pendingDeepLink = .trip(id: tripID)
            }

        case "passport":
            pendingDeepLink = .passport

        default:
            pendingDeepLink = .root
        }
    }
}

// MARK: - Deep Link Destination

public enum OtisDeepLink: Equatable {
    case root
    case trip(id: String)
    case passport
}

// MARK: - PackingListViewModel Integration Notes
// -----------------------------------------------
// In PackingListViewModel.toggleItem(_:):
//
//   func toggleItem(_ item: PackingItem) {
//       item.isPacked.toggle()
//       // ... persist via SwiftData ...
//
//       let percentage = Double(packedItems.count) / Double(allItems.count)
//
//       // 1. Update widget
//       WidgetDataManager.shared.updateWidgetData(
//           tripName: trip.name,
//           destination: trip.destination,
//           tripID: trip.id.uuidString,
//           packingPercentage: percentage,
//           packedCount: packedItems.count,
//           totalCount: allItems.count,
//           departureDate: trip.departureDate,
//           isCompleted: percentage >= 1.0,
//           stampCount: stampCount,
//           subscriptionStatus: subscriptionStatus,
//           lastPackedItem: item.name
//       )
//
//       // 2. Update Live Activity (Pro users only)
//       if subscriptionManager.liveActivityEnabled {
//           Task {
//               await LiveActivityManager.shared.updateActivity(
//                   packingPercentage: percentage,
//                   packedCount: packedItems.count,
//                   totalCount: allItems.count,
//                   lastPackedItem: item.name
//               )
//           }
//       }
//   }
//
// In PackingListViewModel.completeTrip():
//
//   func completeTrip() {
//       // ... mark trip complete in SwiftData ...
//
//       WidgetDataManager.shared.updateWidgetData(
//           tripName: trip.name,
//           destination: trip.destination,
//           tripID: trip.id.uuidString,
//           packingPercentage: 1.0,
//           packedCount: allItems.count,
//           totalCount: allItems.count,
//           departureDate: trip.departureDate,
//           isCompleted: true,
//           stampCount: stampCount,
//           subscriptionStatus: subscriptionStatus,
//           lastPackedItem: nil
//       )
//
//       if subscriptionManager.liveActivityEnabled {
//           Task { await LiveActivityManager.shared.endActivity() }
//       }
//   }
//
// In TripCreationViewModel.createTrip():
//
//   // After saving to SwiftData, immediately prime the widget:
//   WidgetDataManager.shared.updateWidgetData(
//       tripName: newTrip.name,
//       destination: newTrip.destination,
//       tripID: newTrip.id.uuidString,
//       packingPercentage: 0.0,
//       packedCount: 0,
//       totalCount: estimatedItemCount,
//       departureDate: newTrip.departureDate,
//       isCompleted: false,
//       stampCount: stampCount,
//       subscriptionStatus: subscriptionStatus
//   )
