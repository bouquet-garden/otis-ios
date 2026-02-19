// Enums.swift
// Otis
//
// All app-wide enums in one file — no hunting across the project.
// Conforms to Codable for SwiftData persistence, CaseIterable for UI pickers,
// Identifiable where used in ForEach.
//
// Import SwiftUI here only for Color — keep model layer dependencies minimal.

import SwiftUI

// MARK: - TripType

/// The category of a trip. Drives stamp art selection, AI prompt context,
/// and suggested packing categories.
enum TripType: String, Codable, CaseIterable, Identifiable {
    case beach
    case business
    case mountain
    case city
    case international
    case weekend
    case ski

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beach:         return "Beach"
        case .business:      return "Business Trip"
        case .mountain:      return "Mountain"
        case .city:          return "City Break"
        case .international: return "International"
        case .weekend:       return "Weekend Getaway"
        case .ski:           return "Ski Trip"
        }
    }

    /// SF Symbol name representing this trip type in the UI.
    var icon: String {
        switch self {
        case .beach:         return "beach.umbrella"
        case .business:      return "briefcase"
        case .mountain:      return "mountain.2"
        case .city:          return "building.2"
        case .international: return "airplane.departure"
        case .weekend:       return "house"
        case .ski:           return "snowflake"
        }
    }

    /// Brand-aligned accent color per trip type. Used in stamp artwork and
    /// trip cards. All colors are defined as SwiftUI Color literals so they
    /// respect light/dark mode when used in the view layer.
    var defaultStampColor: Color {
        switch self {
        case .beach:         return Color(red: 0.20, green: 0.70, blue: 0.82) // teal
        case .business:      return Color(red: 0.35, green: 0.35, blue: 0.45) // slate
        case .mountain:      return Color(red: 0.30, green: 0.55, blue: 0.35) // forest
        case .city:          return Color(red: 0.60, green: 0.40, blue: 0.80) // violet
        case .international: return Color(red: 0.85, green: 0.50, blue: 0.25) // amber
        case .weekend:       return Color(red: 0.95, green: 0.55, blue: 0.45) // coral
        case .ski:           return Color(red: 0.45, green: 0.70, blue: 0.90) // ice blue
        }
    }

    /// Ordered list of packing categories most relevant to this trip type.
    /// Used when seeding a new packing list via AI or profile template.
    var suggestedPackingCategories: [ItemCategory] {
        switch self {
        case .beach:
            return [.clothing, .toiletries, .footwear, .accessories, .sports, .medications]
        case .business:
            return [.documents, .clothing, .electronics, .footwear, .accessories]
        case .mountain:
            return [.clothing, .footwear, .sports, .medications, .food, .electronics]
        case .city:
            return [.clothing, .footwear, .electronics, .documents, .accessories]
        case .international:
            return [.documents, .clothing, .electronics, .toiletries, .medications, .footwear]
        case .weekend:
            return [.clothing, .toiletries, .footwear, .entertainment, .accessories]
        case .ski:
            return [.clothing, .footwear, .sports, .medications, .accessories, .electronics]
        }
    }
}

// MARK: - ItemCategory

/// A packing item's category. Drives grouping in the list view, icon display,
/// and AI prompt structuring. sortPriority orders category sections:
/// critical items (documents, medications) appear first.
enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case clothing
    case toiletries
    case electronics
    case documents
    case medications
    case footwear
    case accessories
    case sports
    case food
    case entertainment
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clothing:      return "Clothing"
        case .toiletries:    return "Toiletries"
        case .electronics:   return "Electronics"
        case .documents:     return "Documents"
        case .medications:   return "Medications"
        case .footwear:      return "Footwear"
        case .accessories:   return "Accessories"
        case .sports:        return "Sports & Outdoors"
        case .food:          return "Food & Snacks"
        case .entertainment: return "Entertainment"
        case .other:         return "Other"
        }
    }

    /// SF Symbol name for this category.
    var icon: String {
        switch self {
        case .clothing:      return "tshirt"
        case .toiletries:    return "drop"
        case .electronics:   return "cable.connector"
        case .documents:     return "doc.text"
        case .medications:   return "pills"
        case .footwear:      return "shoe"
        case .accessories:   return "glasses"
        case .sports:        return "figure.hiking"
        case .food:          return "fork.knife"
        case .entertainment: return "headphones"
        case .other:         return "ellipsis.circle"
        }
    }

    /// Lower value = appears earlier in the packing list. Documents and
    /// medications float to the top — these are the most critical items.
    var sortPriority: Int {
        switch self {
        case .documents:     return 0
        case .medications:   return 1
        case .electronics:   return 2
        case .clothing:      return 3
        case .footwear:      return 4
        case .toiletries:    return 5
        case .accessories:   return 6
        case .sports:        return 7
        case .food:          return 8
        case .entertainment: return 9
        case .other:         return 10
        }
    }
}

// MARK: - StampType

/// The visual/thematic variant of a passport stamp. Determines which artwork
/// is rendered and whether a celebration sequence fires.
enum StampType: String, Codable, CaseIterable {
    // Special stamps
    case firstTrip      // Gold — first-ever trip, always fires confetti
    case milestone      // Silver/Gold — 5th, 10th, 25th, 50th trip

    // Destination-type stamps (mirrors TripType for most cases)
    case beach
    case mountain
    case city
    case international
    case business
    case ski
    case weekend

    // Season-based fallback stamps (used when destination type is ambiguous)
    case winter
    case spring
    case summer
    case autumn

    var displayName: String {
        switch self {
        case .firstTrip:     return "First Adventure"
        case .milestone:     return "Milestone"
        case .beach:         return "Beach Escape"
        case .mountain:      return "Mountain Explorer"
        case .city:          return "City Dweller"
        case .international: return "World Traveler"
        case .business:      return "Road Warrior"
        case .ski:           return "Powder Hound"
        case .weekend:       return "Weekend Wanderer"
        case .winter:        return "Winter Voyager"
        case .spring:        return "Spring Roamer"
        case .summer:        return "Summer Drifter"
        case .autumn:        return "Autumn Rambler"
        }
    }

    /// Maps to an entry in the Xcode asset catalog under Assets.xcassets/Stamps/.
    /// Convention: stamp_<rawValue> — e.g. stamp_firstTrip, stamp_beach.
    var stampAssetName: String {
        "stamp_\(rawValue)"
    }

    /// True for stamp types that trigger Otis's celebration animation sequence
    /// and unlock the confetti/haptic burst. Regular destination stamps are
    /// satisfying but subdued; celebration stamps go all out.
    var isCelebration: Bool {
        switch self {
        case .firstTrip, .milestone:
            return true
        default:
            return false
        }
    }

    /// Derives the appropriate StampType from a TripType + Season combination.
    /// Milestone and firstTrip are assigned by StampService, not derived here.
    static func from(tripType: TripType, season: Season) -> StampType {
        switch tripType {
        case .beach:         return .beach
        case .business:      return .business
        case .mountain:      return .mountain
        case .city:          return .city
        case .international: return .international
        case .ski:           return .ski
        case .weekend:
            // Weekend trips fall back to seasonal stamp for variety
            switch season {
            case .winter:    return .winter
            case .spring:    return .spring
            case .summer:    return .summer
            case .autumn:    return .autumn
            }
        }
    }
}

// MARK: - Season

/// Calendar season derived from a departure date. Used to vary stamp artwork
/// and surface relevant packing context (e.g. "pack layers" in autumn).
enum Season: String, Codable {
    case spring
    case summer
    case autumn
    case winter

    /// Derives a Season from any Date using the Northern Hemisphere calendar.
    /// Month boundaries: Dec/Jan/Feb=winter, Mar/Apr/May=spring,
    /// Jun/Jul/Aug=summer, Sep/Oct/Nov=autumn.
    static func from(date: Date) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5:   return .spring
        case 6...8:   return .summer
        case 9...11:  return .autumn
        default:      return .winter // 12, 1, 2
        }
    }

    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        case .winter: return "Winter"
        }
    }

    /// SF Symbol for season. Used in trip summary cards and stamp overlays.
    var icon: String {
        switch self {
        case .spring: return "leaf"
        case .summer: return "sun.max"
        case .autumn: return "wind"
        case .winter: return "snowflake"
        }
    }
}

// MARK: - UserSubscriptionStatus

/// The user's current subscription tier. Drives feature gating throughout the
/// app. Computed via UserProfile.effectiveSubscriptionStatus — callers should
/// almost always use that computed property rather than this raw value, because
/// it factors in the First Trip Free mechanic.
enum UserSubscriptionStatus: String, Codable {
    case free
    case proAnnual
    case lifetime

    var displayName: String {
        switch self {
        case .free:      return "Free"
        case .proAnnual: return "Otis Pro"
        case .lifetime:  return "Otis Lifetime"
        }
    }

    /// True when the user has any paid tier (annual or lifetime).
    var isProUser: Bool {
        switch self {
        case .free:               return false
        case .proAnnual, .lifetime: return true
        }
    }

    // MARK: Feature gates

    /// AI packing suggestions via OpenAI — Pro only.
    var aiSuggestionsEnabled: Bool { isProUser }

    /// Passport stamps unlock after trip completion — Pro only.
    var stampUnlocksEnabled: Bool { isProUser }

    /// iCloud sync across devices — Pro only.
    var iCloudSyncEnabled: Bool { isProUser }

    /// Dynamic Island / Live Activity showing packing % — Pro only.
    var liveActivityEnabled: Bool { isProUser }

    /// Save and reuse custom packing profiles — Pro only.
    var savedProfilesEnabled: Bool { isProUser }

    /// Maximum trips shown in history. nil means unlimited.
    /// Free users see only their last 3 trips.
    var tripHistoryLimit: Int? {
        switch self {
        case .free:               return 3
        case .proAnnual, .lifetime: return nil
        }
    }
}

// MARK: - OtisState

/// Represents Otis's current animation/emotional state. Views observe this
/// via the app's central OtisStateManager and swap assets accordingly.
/// Defined as a plain enum (not @Model) — this is runtime-only state, not persisted.
enum OtisState: String {
    /// Default state between trips or when idle. Otis holds his checklist.
    case calm

    /// Active packing session underway. Otis looks alert, eyes wide.
    case active

    /// Trip complete or stamp unlocked. Otis jumps, confetti fires.
    case celebration

    /// Free tier, between trips. Otis is asleep, small "zzz" animation.
    case napping

    /// Asset name used to look up the correct Lottie JSON or SF Symbol set.
    /// Convention: otis_<rawValue> — e.g. otis_calm, otis_celebration.
    var animationName: String {
        "otis_\(rawValue)"
    }

    /// VoiceOver label for Otis when in this state. Never reads the asset name.
    var accessibilityLabel: String {
        switch self {
        case .calm:
            return "Otis, ready to help you pack"
        case .active:
            return "Otis is on the case"
        case .celebration:
            return "Otis is celebrating"
        case .napping:
            return "Otis is napping. Upgrade to Pro to wake him up."
        }
    }
}
