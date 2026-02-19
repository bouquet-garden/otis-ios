// Stamp.swift
// Otis
//
// A passport stamp earned when a Trip is marked complete. Each completed trip
// earns exactly one stamp. Stamps are permanent — they are never deleted when
// a trip is deleted (deleteRule: .nullify on Trip.stamp).
//
// StampService (Services/StampService.swift) is the sole creator of Stamp
// records. Views only read stamps — they never construct them directly.
//
// Relationship graph:
//   Stamp ── Trip?   (nullify — stamp survives if trip is deleted)

import Foundation
import SwiftData

@Model
final class Stamp {

    // MARK: - Stored Properties

    /// Stable identifier.
    @Attribute(.unique)
    var id: UUID

    /// The user's overall trip number when this stamp was earned.
    /// 1 = first trip ever, 5 = fifth trip, etc.
    /// Assigned by StampService from UserProfile.totalTripsCompleted + 1.
    var tripNumber: Int

    /// The visual/thematic category of the stamp. Determines artwork and
    /// whether a celebration animation fires.
    var stampType: StampType

    /// The destination string copied from the parent trip at completion time.
    /// Stored here so the stamp remains meaningful even if the trip is deleted.
    var destination: String

    /// The trip type copied from the parent trip at completion time.
    var destinationType: TripType

    /// The calendar season at the time of the parent trip's departure date.
    var season: Season

    /// Timestamp when the stamp was awarded (i.e. when the trip was completed).
    var earnedAt: Date

    /// True for milestone trip numbers: 1, 5, 10, 25, 50.
    /// Milestone stamps get a special border treatment in the passport grid.
    var isMilestone: Bool

    /// Which milestone number this is (1, 5, 10, 25, 50), if isMilestone is true.
    /// nil for regular stamps.
    var milestoneNumber: Int?

    // MARK: - Relationships

    /// The trip that earned this stamp. May become nil if the trip is deleted,
    /// but the stamp itself persists (nullify delete rule).
    var trip: Trip?

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        tripNumber: Int,
        stampType: StampType,
        destination: String,
        destinationType: TripType,
        season: Season,
        earnedAt: Date = Date(),
        isMilestone: Bool,
        milestoneNumber: Int? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.tripNumber = tripNumber
        self.stampType = stampType
        self.destination = destination
        self.destinationType = destinationType
        self.season = season
        self.earnedAt = earnedAt
        self.isMilestone = isMilestone
        self.milestoneNumber = milestoneNumber
        self.trip = trip
    }

    // MARK: - Computed: Display Title

    /// A human-readable title for this stamp. Shown in the passport grid
    /// tooltip, the stamp detail sheet, and the shareable stamp card.
    ///
    /// Priority order:
    ///   1. firstTrip special stamp  →  unique pioneer titles
    ///   2. Milestone stamp          →  milestone-number-specific title
    ///   3. Destination-type stamp   →  destination + season combinations
    var displayTitle: String {
        switch stampType {

        // MARK: First Trip — most special stamp in the passport
        case .firstTrip:
            return "The Pioneer"

        // MARK: Milestones — each gets a distinct achievement title
        case .milestone:
            switch milestoneNumber {
            case 5:   return "The Frequent Flyer"
            case 10:  return "Road Warrior"
            case 25:  return "The Globetrotter"
            case 50:  return "Legend in Transit"
            default:  return "Milestone Achieved"
            }

        // MARK: Destination-type stamps — season adds flavour
        case .beach:
            switch season {
            case .summer: return "Pacific Dreamer"
            case .spring: return "Shoreline Escape"
            case .autumn: return "Off-Season Surfer"
            case .winter: return "Winter Shore"
            }

        case .mountain:
            switch season {
            case .summer: return "Summit Seeker"
            case .spring: return "Alpine Wanderer"
            case .autumn: return "Foliage Chaser"
            case .winter: return "Powder Run"
            }

        case .city:
            switch season {
            case .summer: return "Urban Explorer"
            case .spring: return "City in Bloom"
            case .autumn: return "Neon & Rain"
            case .winter: return "Winter Streets"
            }

        case .international:
            switch season {
            case .summer: return "Passport Stamped"
            case .spring: return "The Wanderer"
            case .autumn: return "Far From Home"
            case .winter: return "Polar Expedition"
            }

        case .business:
            switch season {
            case .summer: return "Corner Office"
            case .spring: return "Q2 Hustle"
            case .autumn: return "Q4 Push"
            case .winter: return "Year-End Run"
            }

        case .ski:
            switch season {
            case .winter: return "First Tracks"
            case .spring: return "Spring Slush"
            case .summer: return "Glacial Descent"
            case .autumn: return "Pre-Season Pilgrim"
            }

        case .weekend:
            switch season {
            case .summer: return "Long Weekend"
            case .spring: return "Spring Escape"
            case .autumn: return "Leaf Peeper"
            case .winter: return "Cabin Fever"
            }

        // MARK: Season-based fallbacks
        case .winter:  return "Winter Voyager"
        case .spring:  return "Spring Roamer"
        case .summer:  return "Summer Drifter"
        case .autumn:  return "Autumn Rambler"
        }
    }

    // MARK: - Computed: Asset Name

    /// The image asset name for this stamp's graphic. Maps to an entry in
    /// Assets.xcassets/Stamps/. Views load this via Image(shareImageName).
    ///
    /// Naming convention:
    ///   stamp_<type>_<season>   for destination + season combinations
    ///   stamp_firsttrip          for the first-trip gold stamp
    ///   stamp_milestone_<N>      for milestone stamps (5, 10, 25, 50)
    var shareImageName: String {
        switch stampType {
        case .firstTrip:
            return "stamp_firsttrip"
        case .milestone:
            let n = milestoneNumber ?? 0
            return "stamp_milestone_\(n)"
        default:
            return "stamp_\(stampType.rawValue)_\(season.rawValue)"
        }
    }

    // MARK: - Computed: Subtitle

    /// Short subtitle shown beneath the stamp title in the passport grid.
    /// Combines destination and formatted date. E.g. "Tulum · Summer 2025"
    var subtitle: String {
        let year = Calendar.current.component(.year, from: earnedAt)
        return "\(destination) · \(season.displayName) \(year)"
    }

    // MARK: - Computed: Ordinal Label

    /// Human-readable trip ordinal. E.g. "1st Trip", "5th Trip", "23rd Trip".
    var tripOrdinalLabel: String {
        let suffix: String
        let n = tripNumber
        switch n % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch n % 10 {
            case 1:  suffix = "st"
            case 2:  suffix = "nd"
            case 3:  suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix) Trip"
    }
}

// MARK: - Stamp + Comparable

extension Stamp: Comparable {
    /// Sort stamps chronologically ascending (oldest first) for the passport
    /// grid, which renders in the order they were earned.
    static func < (lhs: Stamp, rhs: Stamp) -> Bool {
        lhs.earnedAt < rhs.earnedAt
    }
}
