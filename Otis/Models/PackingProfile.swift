// PackingProfile.swift
// Otis
//
// A reusable packing template that a Pro user can save and apply to new trips.
// E.g. "Beach Essentials", "Business Travel", "Ski Weekend".
//
// Each profile owns a list of TemplateItems (cascade-deleted with the profile).
// When applied to a Trip, TemplateItems are instantiated as fresh PackingItem
// records — they are not linked back to the profile after that point.
//
// Relationship graph:
//   PackingProfile ──< TemplateItem   (cascade delete)

import Foundation
import SwiftData

// MARK: - PackingProfile

@Model
final class PackingProfile {

    // MARK: - Stored Properties

    /// Stable identifier.
    @Attribute(.unique)
    var id: UUID

    /// User-facing profile name. E.g. "Beach Essentials", "Ski Weekend".
    /// Max length enforced in the ViewModel (64 chars).
    var name: String

    /// The trip type this profile is optimised for. Drives the suggested
    /// categories when the user creates a new profile, and filters which
    /// profiles surface at trip-creation time.
    var tripType: TripType

    /// SF Symbol name displayed on the profile card. Defaults to the
    /// TripType icon but can be overridden by the user.
    var icon: String

    /// Whether this is a system-provided default profile (ships with the app)
    /// or a user-created one. Default profiles can be applied but not deleted.
    var isDefault: Bool

    /// How many times this profile has been applied to a trip. Surfaced in
    /// the profiles list as a social-proof signal ("Used 12 times").
    var usageCount: Int

    /// Timestamp of record creation. Used to sort user profiles chronologically.
    var createdAt: Date

    // MARK: - Relationships

    /// The template items that make up this profile. Cascade-deleted.
    @Relationship(deleteRule: .cascade, inverse: \TemplateItem.profile)
    var templateItems: [TemplateItem]

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String,
        tripType: TripType,
        icon: String? = nil,
        isDefault: Bool = false,
        usageCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.tripType = tripType
        // If no icon is provided, inherit the trip type's icon
        self.icon = icon ?? tripType.icon
        self.isDefault = isDefault
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.templateItems = []
    }

    // MARK: - Computed Properties

    /// Total number of template items in this profile.
    var itemCount: Int {
        templateItems.count
    }

    /// Template items sorted by their sort order, then grouped by category
    /// (ascending by sortPriority). Used when previewing the profile.
    var itemsSortedForDisplay: [TemplateItem] {
        templateItems.sorted {
            if $0.category.sortPriority != $1.category.sortPriority {
                return $0.category.sortPriority < $1.category.sortPriority
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    /// A short subtitle shown on the profile card in the picker.
    /// E.g. "12 items · Beach"
    var subtitle: String {
        "\(itemCount) item\(itemCount == 1 ? "" : "s") · \(tripType.displayName)"
    }

    // MARK: - Factory: System Default Profiles

    /// Returns the four system-provided default profiles that ship with the app.
    /// These are inserted into the ModelContext on first launch if no profiles exist.
    /// Default profiles are never editable or deletable by the user.
    @MainActor
    static func systemDefaults() -> [PackingProfile] {
        [
            beachDefault(),
            businessDefault(),
            skiDefault(),
            cityDefault()
        ]
    }

    @MainActor
    private static func beachDefault() -> PackingProfile {
        let profile = PackingProfile(
            name: "Beach Essentials",
            tripType: .beach,
            icon: "beach.umbrella",
            isDefault: true
        )
        let items: [(String, ItemCategory, Int)] = [
            ("Swimsuit", .clothing, 0),
            ("Cover-up", .clothing, 1),
            ("Sunscreen SPF 50", .toiletries, 2),
            ("After-sun lotion", .toiletries, 3),
            ("Sunglasses", .accessories, 4),
            ("Beach towel", .accessories, 5),
            ("Flip flops", .footwear, 6),
            ("Water shoes", .footwear, 7),
            ("Reusable water bottle", .sports, 8),
            ("Beach bag", .accessories, 9),
            ("Portable speaker", .entertainment, 10),
            ("Book or e-reader", .entertainment, 11)
        ]
        profile.templateItems = items.map { name, category, order in
            TemplateItem(name: name, category: category, sortOrder: order, profile: profile)
        }
        return profile
    }

    @MainActor
    private static func businessDefault() -> PackingProfile {
        let profile = PackingProfile(
            name: "Business Travel",
            tripType: .business,
            icon: "briefcase",
            isDefault: true
        )
        let items: [(String, ItemCategory, Int)] = [
            ("Passport / ID", .documents, 0),
            ("Business cards", .documents, 1),
            ("Laptop", .electronics, 2),
            ("Laptop charger", .electronics, 3),
            ("USB-C hub", .electronics, 4),
            ("Phone charger", .electronics, 5),
            ("Dress shirt x2", .clothing, 6),
            ("Dress trousers", .clothing, 7),
            ("Blazer", .clothing, 8),
            ("Dress shoes", .footwear, 9),
            ("Belt", .accessories, 10),
            ("Notebook and pen", .documents, 11)
        ]
        profile.templateItems = items.map { name, category, order in
            TemplateItem(name: name, category: category, sortOrder: order, profile: profile)
        }
        return profile
    }

    @MainActor
    private static func skiDefault() -> PackingProfile {
        let profile = PackingProfile(
            name: "Ski Trip",
            tripType: .ski,
            icon: "snowflake",
            isDefault: true
        )
        let items: [(String, ItemCategory, Int)] = [
            ("Ski jacket", .clothing, 0),
            ("Ski trousers", .clothing, 1),
            ("Thermal base layer x2", .clothing, 2),
            ("Ski socks x4", .clothing, 3),
            ("Ski boots", .footwear, 4),
            ("Warm boots (apres-ski)", .footwear, 5),
            ("Ski gloves", .accessories, 6),
            ("Helmet", .sports, 7),
            ("Goggles", .sports, 8),
            ("Ski pass / lift ticket", .documents, 9),
            ("Lip balm SPF", .toiletries, 10),
            ("Hand warmers", .accessories, 11),
            ("Sunscreen SPF 50", .toiletries, 12)
        ]
        profile.templateItems = items.map { name, category, order in
            TemplateItem(name: name, category: category, sortOrder: order, profile: profile)
        }
        return profile
    }

    @MainActor
    private static func cityDefault() -> PackingProfile {
        let profile = PackingProfile(
            name: "City Break",
            tripType: .city,
            icon: "building.2",
            isDefault: true
        )
        let items: [(String, ItemCategory, Int)] = [
            ("Passport / ID", .documents, 0),
            ("Travel wallet", .accessories, 1),
            ("Comfortable walking shoes", .footwear, 2),
            ("Smart casual outfit x2", .clothing, 3),
            ("Light jacket", .clothing, 4),
            ("Phone charger + power bank", .electronics, 5),
            ("Earbuds / headphones", .electronics, 6),
            ("Day bag / backpack", .accessories, 7),
            ("Toiletries kit", .toiletries, 8),
            ("Camera", .electronics, 9)
        ]
        profile.templateItems = items.map { name, category, order in
            TemplateItem(name: name, category: category, sortOrder: order, profile: profile)
        }
        return profile
    }
}

// MARK: - TemplateItem

/// A single item within a PackingProfile template. When a profile is applied
/// to a trip, each TemplateItem is copied into a fresh PackingItem — the
/// TemplateItem itself is never modified after that.
@Model
final class TemplateItem {

    // MARK: - Stored Properties

    @Attribute(.unique)
    var id: UUID

    /// Item name. E.g. "Sunscreen SPF 50", "Laptop charger".
    var name: String

    /// Category of this template item. Inherited by the PackingItem on apply.
    var category: ItemCategory

    /// Sort position within this profile. Lower = appears earlier.
    var sortOrder: Int

    // MARK: - Relationships

    /// The profile this template item belongs to.
    var profile: PackingProfile?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        name: String,
        category: ItemCategory = .other,
        sortOrder: Int = 0,
        profile: PackingProfile? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.sortOrder = sortOrder
        self.profile = profile
    }

    // MARK: - Computed

    /// Converts this template item into a fresh PackingItem for a given trip.
    /// Called by TripService.applyProfile(_:to:) — never call directly from views.
    func toPackingItem(for trip: Trip) -> PackingItem {
        PackingItem(
            name: name,
            category: category,
            isPacked: false,
            isAISuggested: false,
            sortOrder: sortOrder,
            trip: trip
        )
    }
}
