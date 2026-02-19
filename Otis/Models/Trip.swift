// Trip.swift
// Otis
//
// Central @Model class representing a single travel trip. All packing items
// and the passport stamp belong to a Trip. CloudKit sync is handled at the
// ModelContainer level (see OtisApp.swift) — no per-model changes needed.
//
// Relationship graph:
//   Trip ──< PackingItem   (cascade delete)
//   Trip ──  Stamp?        (nullify on trip delete — stamp is the record)

import Foundation
import SwiftData

@Model
final class Trip {

    // MARK: - Stored Properties

    /// Stable identifier. Set once at creation and never changed.
    @Attribute(.unique)
    var id: UUID

    /// User-facing trip name. E.g. "Cabo with Sarah", "Q3 Chicago Conference".
    var name: String

    /// Free-text destination. E.g. "Tulum, Mexico", "Chicago, IL".
    var destination: String

    /// Optional coordinates for the destination. Reserved for v2 weather
    /// integration — stored now so existing records don't need migration.
    var destinationLatitude: Double?
    var destinationLongitude: Double?

    /// The category of trip. Drives stamp art, AI prompt context, and the
    /// suggested packing categories seeded at list creation.
    /// Stored as its String rawValue by SwiftData.
    var tripType: TripType

    /// The day the user departs. Used to derive Season and to schedule the
    /// smart travel-day nudge (3 hours before departure time).
    var departureDate: Date

    /// Optional return date. nil for one-way or open-ended trips.
    var returnDate: Date?

    /// Whether the user has marked this trip as done and claimed the stamp.
    var isCompleted: Bool

    /// Timestamp of record creation. Used to sort trips in history.
    var createdAt: Date

    /// Timestamp when the user tapped "Mark Trip Complete". nil until then.
    var completedAt: Date?

    /// Set to true for the very first trip ever created by this user.
    /// Triggers the First Trip Free Pro experience and the special
    /// firstTrip stamp type. Assigned by TripService at creation time.
    var isFirstTrip: Bool

    // MARK: - Relationships

    /// All packing items belonging to this trip. Cascade-deleted with the trip.
    @Relationship(deleteRule: .cascade, inverse: \PackingItem.trip)
    var items: [PackingItem]

    /// The passport stamp earned when this trip is marked complete.
    /// nil until trip completion. Inverse declared on Stamp.trip.
    @Relationship(deleteRule: .nullify, inverse: \Stamp.trip)
    var stamp: Stamp?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String,
        destination: String,
        destinationLatitude: Double? = nil,
        destinationLongitude: Double? = nil,
        tripType: TripType,
        departureDate: Date,
        returnDate: Date? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        isFirstTrip: Bool = false
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.destinationLatitude = destinationLatitude
        self.destinationLongitude = destinationLongitude
        self.tripType = tripType
        self.departureDate = departureDate
        self.returnDate = returnDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.isFirstTrip = isFirstTrip
        self.items = []
        self.stamp = nil
    }

    // MARK: - Computed Properties

    /// Total number of items on the packing list.
    var totalItemCount: Int {
        items.count
    }

    /// Number of items the user has checked off.
    var packedItemCount: Int {
        items.filter(\.isPacked).count
    }

    /// Packing completion ratio from 0.0 (nothing packed) to 1.0 (all packed).
    /// Returns 0.0 for an empty list to avoid division-by-zero.
    var packingPercentage: Double {
        guard totalItemCount > 0 else { return 0.0 }
        return Double(packedItemCount) / Double(totalItemCount)
    }

    /// Packing completion as a display-friendly integer percentage (0–100).
    var packingPercentageInt: Int {
        Int(packingPercentage * 100)
    }

    /// Calendar season derived from the departure date. Used to vary stamp
    /// artwork and surface seasonal packing tips via Otis.
    var season: Season {
        Season.from(date: departureDate)
    }

    /// Duration of the trip in days. Returns nil if no return date is set.
    var durationInDays: Int? {
        guard let returnDate else { return nil }
        return Calendar.current.dateComponents([.day], from: departureDate, to: returnDate).day
    }

    /// True when the trip departure date is today.
    var isDepartingToday: Bool {
        Calendar.current.isDateInToday(departureDate)
    }

    /// True when all items are packed and the list is non-empty.
    var isFullyPacked: Bool {
        totalItemCount > 0 && packedItemCount == totalItemCount
    }

    /// Items sorted for display: unpacked first (ascending by sortOrder),
    /// then packed items at the bottom (also ascending by sortOrder).
    /// This keeps the actionable items visible at the top.
    var itemsForDisplay: [PackingItem] {
        let unpacked = items
            .filter { !$0.isPacked }
            .sorted { $0.sortOrder < $1.sortOrder }
        let packed = items
            .filter { $0.isPacked }
            .sorted { $0.sortOrder < $1.sortOrder }
        return unpacked + packed
    }

    /// Items grouped by category, sorted by ItemCategory.sortPriority.
    /// Used in the grouped list view variant.
    var itemsByCategory: [(category: ItemCategory, items: [PackingItem])] {
        let grouped = Dictionary(grouping: items) { $0.category }
        return ItemCategory.allCases
            .compactMap { category -> (ItemCategory, [PackingItem])? in
                guard let categoryItems = grouped[category], !categoryItems.isEmpty else { return nil }
                let sorted = categoryItems.sorted { $0.sortOrder < $1.sortOrder }
                return (category, sorted)
            }
            .sorted { $0.0.sortPriority < $1.0.sortPriority }
    }
}
