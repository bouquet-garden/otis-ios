// PackingItem.swift
// Otis
//
// A single item on a trip's packing list. Items belong to exactly one Trip
// and are cascade-deleted when the trip is deleted.
//
// The inverse relationship (\PackingItem.trip) is declared here and
// referenced in Trip.items so SwiftData can maintain both sides of the link.

import Foundation
import SwiftData

@Model
final class PackingItem {

    // MARK: - Stored Properties

    /// Stable identifier. Set once at creation.
    @Attribute(.unique)
    var id: UUID

    /// The item name as entered by the user or suggested by Otis.
    /// E.g. "Sunscreen SPF 50", "MacBook Pro charger", "Passport".
    var name: String

    /// Category used for grouping, icons, and AI prompt structuring.
    /// Stored as String rawValue by SwiftData.
    var category: ItemCategory

    /// Whether the user has checked this item off. Setting true also
    /// records packedAt. Unsetting clears packedAt.
    var isPacked: Bool {
        didSet {
            packedAt = isPacked ? Date() : nil
        }
    }

    /// True when this item was added by Otis's AI suggestion flow rather
    /// than typed manually. Used to surface AI contribution stats and to
    /// style AI-suggested items distinctly in the list (e.g. sparkle icon).
    var isAISuggested: Bool

    /// Timestamp of when isPacked was set to true. Cleared if unchecked.
    /// nil for unpacked items.
    var packedAt: Date?

    /// Manual sort position within the list. Lower = appears earlier.
    /// Populated at insertion and updated when the user reorders items.
    var sortOrder: Int

    // MARK: - Relationships

    /// The trip this item belongs to. Weak reference — the trip owns items,
    /// not the other way around. SwiftData resolves the inverse via Trip.items.
    var trip: Trip?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String,
        category: ItemCategory = .other,
        isPacked: Bool = false,
        isAISuggested: Bool = false,
        packedAt: Date? = nil,
        sortOrder: Int = 0,
        trip: Trip? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.isPacked = isPacked
        self.isAISuggested = isAISuggested
        self.packedAt = packedAt
        self.sortOrder = sortOrder
        self.trip = trip
    }

    // MARK: - Computed Properties

    /// Display-friendly category label. Delegates to ItemCategory.displayName.
    var categoryDisplayName: String {
        category.displayName
    }

    /// SF Symbol name for this item's category. Used in list row icons.
    var categoryIcon: String {
        category.icon
    }

    /// True when the item has been named (non-empty, non-whitespace).
    /// Guards against saving blank items from the add-item flow.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
