// Models.swift
// Otis — SwiftData @Model classes and supporting enums
//
// All models are CloudKit-compatible:
//   - No required non-optional relationships (CloudKit limitation)
//   - All properties have sensible defaults
//   - UUIDs used as stable identifiers across devices
//
// File organization:
//   1. Enums (TripType, StampType, UserSubscriptionStatus, Season, PackingCategory)
//   2. Trip
//   3. PackingItem
//   4. PackingProfile
//   5. Stamp

import Foundation
import SwiftData

// MARK: - 1. Enums

// MARK: TripType

/// The type of trip — drives AI suggestion strategy and stamp artwork selection.
enum TripType: String, Codable, CaseIterable, Identifiable {
    case beach        = "beach"
    case business     = "business"
    case mountain     = "mountain"
    case city         = "city"
    case international = "international"
    case roadTrip     = "road_trip"
    case camping      = "camping"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beach:         return "Beach"
        case .business:      return "Business"
        case .mountain:      return "Mountain"
        case .city:          return "City"
        case .international: return "International"
        case .roadTrip:      return "Road Trip"
        case .camping:       return "Camping"
        }
    }

    /// SF Symbol name representing this trip type in the UI.
    var iconName: String {
        switch self {
        case .beach:         return "sun.max.fill"
        case .business:      return "briefcase.fill"
        case .mountain:      return "mountain.2.fill"
        case .city:          return "building.2.fill"
        case .international: return "airplane"
        case .roadTrip:      return "car.fill"
        case .camping:       return "tent.fill"
        }
    }

    /// Teal-palette tint for each type's icon/chip.
    var accentColorHex: String {
        switch self {
        case .beach:         return "5BBFB5" // otisTeal
        case .business:      return "2C3E50" // otisSlate
        case .mountain:      return "7F8C8D" // slate-light
        case .city:          return "FF6B6B" // otisCoral
        case .international: return "3498DB" // sky blue
        case .roadTrip:      return "E67E22" // warm orange
        case .camping:       return "27AE60" // forest green
        }
    }

    /// Prompt modifier injected into OpenAI packing suggestions.
    var packingPromptContext: String {
        switch self {
        case .beach:
            return "beach destination with sun, sand, and water activities"
        case .business:
            return "business trip requiring professional attire and work essentials"
        case .mountain:
            return "mountain or hiking destination with variable weather and outdoor activities"
        case .city:
            return "urban city trip with walking, dining, and cultural activities"
        case .international:
            return "international trip requiring travel documents, adapters, and multi-climate packing"
        case .roadTrip:
            return "road trip with car travel, varying stops, and need for comfort items"
        case .camping:
            return "camping trip requiring outdoor survival gear, cooking equipment, and nature essentials"
        }
    }
}

// MARK: Season

/// Derived from departure date — used for stamp artwork and AI context.
enum Season: String, Codable, CaseIterable {
    case spring = "spring"
    case summer = "summer"
    case autumn = "autumn"
    case winter = "winter"

    var displayName: String { rawValue.capitalized }

    /// Derive season from a departure date (Northern Hemisphere).
    static func from(date: Date) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3, 4, 5:   return .spring
        case 6, 7, 8:   return .summer
        case 9, 10, 11: return .autumn
        default:         return .winter
        }
    }
}

// MARK: TripStatus

/// The lifecycle state of a trip.
enum TripStatus: String, Codable, CaseIterable {
    case planning   = "planning"    // created, building list
    case active     = "active"      // departure day has arrived
    case completed  = "completed"   // user marked trip done → stamp unlocked
    case archived   = "archived"    // hidden from main list, visible in full history

    var displayName: String {
        switch self {
        case .planning:  return "Planning"
        case .active:    return "Active"
        case .completed: return "Completed"
        case .archived:  return "Archived"
        }
    }
}

// MARK: StampType

/// Determines stamp artwork, rarity, and animation intensity.
enum StampType: String, Codable, CaseIterable {
    // Destination-based stamps
    case beach         = "stamp_beach"
    case business      = "stamp_business"
    case mountain      = "stamp_mountain"
    case city          = "stamp_city"
    case international = "stamp_international"
    case roadTrip      = "stamp_road_trip"
    case camping       = "stamp_camping"

    // Season-based stamps
    case springTrip    = "stamp_spring"
    case summerTrip    = "stamp_summer"
    case autumnTrip    = "stamp_autumn"
    case winterTrip    = "stamp_winter"

    // Milestone stamps (override destination/season)
    case firstTrip     = "stamp_milestone_1"
    case fifthTrip     = "stamp_milestone_5"
    case tenthTrip     = "stamp_milestone_10"
    case twentyFifthTrip = "stamp_milestone_25"
    case fiftiethTrip  = "stamp_milestone_50"

    var displayName: String {
        switch self {
        case .beach:           return "Beach Escape"
        case .business:        return "Business Class"
        case .mountain:        return "Summit Seeker"
        case .city:            return "City Slicker"
        case .international:   return "Globe Trotter"
        case .roadTrip:        return "Open Road"
        case .camping:         return "Into the Wild"
        case .springTrip:      return "Spring Wanderer"
        case .summerTrip:      return "Summer Drifter"
        case .autumnTrip:      return "Autumn Roamer"
        case .winterTrip:      return "Winter Voyager"
        case .firstTrip:       return "First Adventure"
        case .fifthTrip:       return "Seasoned Packer"
        case .tenthTrip:       return "Otis Veteran"
        case .twentyFifthTrip: return "Quarter Century"
        case .fiftiethTrip:    return "Legendary Traveler"
        }
    }

    var isMilestone: Bool {
        switch self {
        case .firstTrip, .fifthTrip, .tenthTrip, .twentyFifthTrip, .fiftiethTrip:
            return true
        default:
            return false
        }
    }

    /// Asset catalog image name for the stamp artwork.
    var assetName: String { rawValue }

    /// Milestone stamps get extended celebration animation.
    var celebrationDuration: Double {
        isMilestone ? 3.5 : 2.0
    }
}

// MARK: PackingCategory

/// Organizes packing items into logical groups within the list.
enum PackingCategory: String, Codable, CaseIterable, Identifiable {
    case clothing      = "clothing"
    case toiletries    = "toiletries"
    case electronics   = "electronics"
    case documents     = "documents"
    case health        = "health"
    case entertainment = "entertainment"
    case gear          = "gear"
    case food          = "food"
    case misc          = "misc"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clothing:      return "Clothing"
        case .toiletries:    return "Toiletries"
        case .electronics:   return "Electronics"
        case .documents:     return "Documents"
        case .health:        return "Health"
        case .entertainment: return "Entertainment"
        case .gear:          return "Gear"
        case .food:          return "Food & Snacks"
        case .misc:          return "Miscellaneous"
        }
    }

    var iconName: String {
        switch self {
        case .clothing:      return "tshirt.fill"
        case .toiletries:    return "shower.fill"
        case .electronics:   return "bolt.fill"
        case .documents:     return "doc.fill"
        case .health:        return "cross.case.fill"
        case .entertainment: return "headphones"
        case .gear:          return "backpack.fill"
        case .food:          return "fork.knife"
        case .misc:          return "bag.fill"
        }
    }
}

// MARK: UserSubscriptionStatus

/// The current subscription state of the user.
/// Source of truth is RevenueCat — this mirrors the entitlement locally.
enum UserSubscriptionStatus: String, Codable {
    case free     = "free"     // default, no purchase
    case pro      = "pro"      // active RevenueCat "pro" entitlement
    case lifetime = "lifetime" // one-time purchase, never expires

    var isPro: Bool { self == .pro || self == .lifetime }
    var displayName: String {
        switch self {
        case .free:     return "Free"
        case .pro:      return "Pro"
        case .lifetime: return "Lifetime"
        }
    }
}

// MARK: - 2. Trip

/// A single user trip. The central entity in Otis — everything else
/// (packing items, stamps) hangs off a Trip.
@Model
final class Trip {

    // MARK: Identity
    @Attribute(.unique) var id: UUID
    var name: String
    var destinationCity: String
    var destinationCountry: String
    var tripType: TripType

    // MARK: Dates
    var departureDate: Date
    var returnDate: Date?
    var createdAt: Date
    var completedAt: Date?

    // MARK: Status
    var status: TripStatus

    // MARK: Pro / AI
    /// Whether this trip was created under "First Trip Free" Pro trial.
    var wasFirstTripFree: Bool
    /// Whether the user has triggered AI suggestions for this trip.
    var aiSuggestionsGenerated: Bool

    // MARK: Notes
    var notes: String

    // MARK: Relationships
    /// All packing items for this trip. Using optional array with CloudKit compatibility.
    @Relationship(deleteRule: .cascade, inverse: \PackingItem.trip)
    var items: [PackingItem]

    /// The stamp earned when this trip was completed. Nil until trip is marked complete.
    @Relationship(deleteRule: .cascade, inverse: \Stamp.trip)
    var stamp: Stamp?

    // MARK: Init

    init(
        id: UUID = UUID(),
        name: String,
        destinationCity: String,
        destinationCountry: String = "",
        tripType: TripType,
        departureDate: Date,
        returnDate: Date? = nil,
        notes: String = "",
        wasFirstTripFree: Bool = false
    ) {
        self.id = id
        self.name = name
        self.destinationCity = destinationCity
        self.destinationCountry = destinationCountry
        self.tripType = tripType
        self.departureDate = departureDate
        self.returnDate = returnDate
        self.createdAt = Date()
        self.completedAt = nil
        self.status = .planning
        self.wasFirstTripFree = wasFirstTripFree
        self.aiSuggestionsGenerated = false
        self.notes = notes
        self.items = []
        self.stamp = nil
    }

    // MARK: Computed Properties

    /// Human-readable destination string.
    var destination: String {
        destinationCountry.isEmpty
            ? destinationCity
            : "\(destinationCity), \(destinationCountry)"
    }

    /// Number of nights (0 if no return date).
    var durationNights: Int {
        guard let returnDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: departureDate, to: returnDate).day ?? 0
    }

    /// Packing completion percentage (0.0 – 1.0).
    var packingProgress: Double {
        guard !items.isEmpty else { return 0.0 }
        let checked = items.filter { $0.isChecked }.count
        return Double(checked) / Double(items.count)
    }

    /// Formatted progress string, e.g. "7 of 12 packed".
    var packingProgressSummary: String {
        let checked = items.filter { $0.isChecked }.count
        return "\(checked) of \(items.count) packed"
    }

    /// True when all items are checked.
    var isFullyPacked: Bool {
        !items.isEmpty && items.allSatisfy { $0.isChecked }
    }

    /// Season derived from departure date — used for stamp selection.
    var departureSeason: Season {
        Season.from(date: departureDate)
    }

    /// Whether departure date is today or in the past (trip is active).
    var isDepartureDay: Bool {
        Calendar.current.isDateInToday(departureDate) ||
        departureDate < Date()
    }

    /// The smart travel-day notification fire date (3 hours before departure).
    var travelDayNotificationDate: Date {
        departureDate.addingTimeInterval(-AppConfig.travelDayLeadTimeHours * 3600)
    }
}

// MARK: - 3. PackingItem

/// A single item in a trip's packing list. Can be manually added or
/// AI-suggested. AI-suggested items start unaccepted until user taps "Add".
@Model
final class PackingItem {

    // MARK: Identity
    @Attribute(.unique) var id: UUID
    var name: String
    var category: PackingCategory
    var quantity: Int

    // MARK: State
    var isChecked: Bool       // packed / not packed
    var isAISuggested: Bool   // came from OpenAI
    var isAccepted: Bool      // user tapped "Add" on an AI suggestion
    var sortOrder: Int        // for user-defined reordering

    // MARK: Metadata
    var addedAt: Date
    var checkedAt: Date?
    var notes: String

    // MARK: Relationship
    var trip: Trip?

    // MARK: Init

    init(
        id: UUID = UUID(),
        name: String,
        category: PackingCategory = .misc,
        quantity: Int = 1,
        isChecked: Bool = false,
        isAISuggested: Bool = false,
        isAccepted: Bool = true,   // manual additions are auto-accepted
        sortOrder: Int = 0,
        notes: String = "",
        trip: Trip? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.isChecked = isChecked
        self.isAISuggested = isAISuggested
        self.isAccepted = isAccepted
        self.sortOrder = sortOrder
        self.addedAt = Date()
        self.checkedAt = nil
        self.notes = notes
        self.trip = trip
    }

    // MARK: Computed

    var displayName: String {
        quantity > 1 ? "\(name) (×\(quantity))" : name
    }
}

// MARK: - 4. PackingProfile

/// A saved, reusable packing template (e.g. "Beach Weekend", "Work Conference").
/// Pro feature — free users can't save profiles.
@Model
final class PackingProfile {

    // MARK: Identity
    @Attribute(.unique) var id: UUID
    var name: String
    var tripType: TripType
    var createdAt: Date
    var lastUsedAt: Date?

    // MARK: Content
    /// Serialized as JSON string for CloudKit compatibility.
    /// Each element is `PackingProfileItem` encoded to JSON.
    var itemsJSON: String

    // MARK: Init

    init(
        id: UUID = UUID(),
        name: String,
        tripType: TripType,
        items: [PackingProfileItem] = []
    ) {
        self.id = id
        self.name = name
        self.tripType = tripType
        self.createdAt = Date()
        self.lastUsedAt = nil
        self.itemsJSON = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    // MARK: Computed

    var items: [PackingProfileItem] {
        get {
            guard let data = itemsJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([PackingProfileItem].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            itemsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
    }

    var itemCount: Int { items.count }
}

/// A lightweight item definition stored inside a PackingProfile.
/// Not a SwiftData model — stored as JSON in PackingProfile.itemsJSON.
struct PackingProfileItem: Codable, Identifiable {
    var id: UUID
    var name: String
    var category: PackingCategory
    var quantity: Int
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        category: PackingCategory = .misc,
        quantity: Int = 1,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.sortOrder = sortOrder
    }
}

// MARK: - 5. Stamp

/// A passport stamp earned when a trip is marked complete.
/// One stamp per trip. Stamp type is determined by StampService.
@Model
final class Stamp {

    // MARK: Identity
    @Attribute(.unique) var id: UUID
    var stampType: StampType
    var earnedAt: Date

    // MARK: Trip Context (denormalized for display without loading trip)
    var tripName: String
    var tripDestination: String
    var tripType: TripType
    var tripNumber: Int   // which trip this was (1, 5, 10, etc.) for milestone display

    // MARK: Relationship
    var trip: Trip?

    // MARK: Social / Sharing
    /// Whether the user has shared this stamp card.
    var hasBeenShared: Bool

    // MARK: Init

    init(
        id: UUID = UUID(),
        stampType: StampType,
        tripName: String,
        tripDestination: String,
        tripType: TripType,
        tripNumber: Int,
        trip: Trip? = nil
    ) {
        self.id = id
        self.stampType = stampType
        self.earnedAt = Date()
        self.tripName = tripName
        self.tripDestination = tripDestination
        self.tripType = tripType
        self.tripNumber = tripNumber
        self.trip = trip
        self.hasBeenShared = false
    }

    // MARK: Computed

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: earnedAt)
    }

    var shareTitle: String {
        "Trip #\(tripNumber) to \(tripDestination) — \(stampType.displayName)"
    }
}
