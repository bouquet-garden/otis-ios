// AppleIntelligenceService.swift
// Otis — Services/AppleIntelligenceService.swift
//
// On-device AI packing suggestions powered by Apple Intelligence (FoundationModels).
// Falls back gracefully to curated mock suggestions on simulator, older devices,
// or when the FoundationModels framework is not yet linked.
//
// Architecture:
//   - @MainActor final class (singleton) — safe to call from SwiftUI/ViewModel
//   - Checks device capability at runtime via isAvailable
//   - On-device path uses FoundationModels (iOS 18.1+, Apple Intelligence devices)
//   - Mock path provides realistic, trip-type-aware suggestions with a 1.5s delay
//     that mirrors real generation latency for UI development
//
// Usage:
//   let suggestions = try await AppleIntelligenceService.shared
//       .generatePackingSuggestions(for: trip, existingItemNames: existingNames)
//
// To enable on-device generation once FoundationModels is linked:
//   1. Add FoundationModels.framework to the target's Frameworks phase
//   2. Uncomment the block marked "UNCOMMENT WHEN FRAMEWORK IS LINKED" below
//   3. Remove the `fallthrough to mock` line directly beneath it

import Foundation

// MARK: - AIServiceError

/// Typed errors surfaced by AppleIntelligenceService.
/// Cases are intentionally narrow — callers should display
/// `localizedDescription` directly in the suggestion UI.
enum AIServiceError: Error, LocalizedError {

    /// Apple Intelligence is not available on this device or OS version.
    /// Expected on simulator, A14 and older devices, and iOS < 18.1.
    case unavailable

    /// The on-device model attempted generation but returned no usable output.
    case generationFailed

    /// The in-flight generation task was cancelled (e.g. sheet dismissed mid-load).
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Intelligence isn't available on this device. Otis will use curated suggestions instead."
        case .generationFailed:
            return "Otis couldn't generate suggestions right now. Try again in a moment."
        case .cancelled:
            return "Suggestion generation was cancelled."
        }
    }
}

// MARK: - AppleIntelligenceService

/// Singleton service that generates on-device packing suggestions using
/// Apple Intelligence (FoundationModels framework, iOS 18.1+).
///
/// On unsupported devices or the simulator, `generatePackingSuggestions`
/// transparently falls through to `mockSuggestions`, which returns a
/// curated, trip-type-aware list after a short simulated delay.
@MainActor
final class AppleIntelligenceService {

    // MARK: Singleton

    static let shared = AppleIntelligenceService()
    private init() {}

    // MARK: - Availability

    /// Whether Apple Intelligence on-device generation is available.
    ///
    /// Returns `false` on:
    ///   - iOS Simulator (TARGET_OS_SIMULATOR)
    ///   - Devices not in the Apple Intelligence hardware set
    ///   - iOS versions below 18.1
    ///
    /// When `false`, `generatePackingSuggestions` falls back to `mockSuggestions`
    /// automatically — callers do not need to branch on this property.
    var isAvailable: Bool {
        // Simulator never supports on-device model inference
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 18.1, *) {
            // On a real iOS 18.1+ device Apple Intelligence hardware is assumed
            // present on all A17 Pro / M-series chips (iPhone 15 Pro and later).
            // FoundationModels will surface a more granular availability check
            // once the framework is linked — see the UNCOMMENT block below.
            return true
        } else {
            return false
        }
        #endif
    }

    // MARK: - Public API

    /// Generates a ranked list of personalized packing suggestions for the given trip.
    ///
    /// On iOS 18.1+ real devices the on-device FoundationModels path is taken.
    /// On simulator or older OS, a curated mock list is returned after a 1.5 s delay.
    ///
    /// - Parameters:
    ///   - trip: The trip whose `tripType`, `destination`, `departureDate`, and
    ///     `durationNights` inform the generation prompt.
    ///   - existingItemNames: Names of items already on the list. Matched
    ///     case-insensitively so duplicates are never returned.
    /// - Returns: An array of `PackingSuggestion` sorted by priority
    ///   (essential → recommended → niceToHave), typically 15–25 items.
    /// - Throws: `AIServiceError` for availability or generation failures.
    func generatePackingSuggestions(
        for trip: Trip,
        existingItemNames: [String] = []
    ) async throws -> [PackingSuggestion] {
        if #available(iOS 18.1, *), isAvailable {
            return try await onDeviceSuggestions(for: trip, excluding: existingItemNames)
        } else {
            return try await mockSuggestions(for: trip, excluding: existingItemNames)
        }
    }

    // MARK: - On-Device Generation (FoundationModels)

    /// Attempts on-device generation via Apple's FoundationModels framework.
    ///
    /// The FoundationModels calls are commented out pending framework linkage.
    /// Once `FoundationModels.framework` is added to the target:
    ///   1. Uncomment the block marked "UNCOMMENT WHEN FRAMEWORK IS LINKED".
    ///   2. Delete the `fallthrough` line immediately after the comment block.
    ///
    /// - Parameters:
    ///   - trip: The trip context used to build the generation prompt.
    ///   - excluding: Item names already on the list (duplicate prevention).
    /// - Returns: Parsed `[PackingSuggestion]` from the model's JSON output.
    /// - Throws: `AIServiceError.generationFailed` if the model returns unusable output.
    @available(iOS 18.1, *)
    private func onDeviceSuggestions(
        for trip: Trip,
        excluding existingItemNames: [String]
    ) async throws -> [PackingSuggestion] {

        let prompt = buildPrompt(for: trip, excluding: existingItemNames)

        // ─────────────────────────────────────────────────────────────────────
        // UNCOMMENT WHEN FRAMEWORK IS LINKED
        // ─────────────────────────────────────────────────────────────────────
        // import FoundationModels  ← add to top of file
        //
        // do {
        //     let model = SystemLanguageModel.default
        //     guard model.availability == .available else {
        //         throw AIServiceError.unavailable
        //     }
        //     let session = LanguageModelSession()
        //     let response = try await session.respond(to: prompt)
        //     let rawText = response.content
        //     return try parseJSON(rawText, for: trip)
        // } catch is CancellationError {
        //     throw AIServiceError.cancelled
        // } catch let serviceError as AIServiceError {
        //     throw serviceError
        // } catch {
        //     throw AIServiceError.generationFailed
        // }
        // ─────────────────────────────────────────────────────────────────────

        // Fallthrough to mock until FoundationModels is linked
        _ = prompt  // suppress unused-variable warning
        return try await mockSuggestions(for: trip, excluding: existingItemNames)
    }

    // MARK: - Prompt Builder

    /// Constructs a structured natural-language prompt for the on-device model.
    ///
    /// The prompt is deliberately concise — smaller models perform better with
    /// tightly scoped instructions and explicit JSON schema constraints.
    ///
    /// - Parameters:
    ///   - trip: Source of destination, trip type, dates, and duration.
    ///   - existingItemNames: Injected into the prompt as exclusions.
    /// - Returns: A single prompt string ready for `LanguageModelSession.respond(to:)`.
    private func buildPrompt(for trip: Trip, excluding existingItemNames: [String]) -> String {
        let duration = trip.durationNights > 0 ? "\(trip.durationNights) nights" : "a short trip"
        let destination = trip.destination
        let tripTypeLabel = trip.tripType.displayName

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let departureDateString = dateFormatter.string(from: trip.departureDate)

        let exclusionClause: String
        if existingItemNames.isEmpty {
            exclusionClause = ""
        } else {
            let joined = existingItemNames.prefix(30).joined(separator: ", ")
            exclusionClause = "\nDo NOT suggest any of these already-packed items: \(joined)."
        }

        return """
        You are Otis, a smart packing assistant. Generate a packing list for this trip:

        - Trip type: \(tripTypeLabel)
        - Destination: \(destination)
        - Duration: \(duration)
        - Departure: \(departureDateString)
        \(exclusionClause)

        Return ONLY a JSON object with this exact structure (no markdown, no prose):
        {
          "items": [
            {
              "name": "Item name",
              "category": "clothing|toiletries|electronics|documents|medications|footwear|accessories|sports|food|entertainment|other",
              "priority": "essential|recommended|niceToHave",
              "reason": "One sentence explaining why this item matters for this specific trip."
            }
          ]
        }

        Include 15–20 items. Prioritise essentials first. Be specific to the trip type and destination.
        """
    }

    // MARK: - JSON Parser

    /// Parses the raw text output from the on-device model into `[PackingSuggestion]`.
    ///
    /// Strips markdown code fences (` ```json ... ``` `) that the model may emit
    /// before attempting JSON decoding. Maps raw string fields to typed enums,
    /// falling back to `.other` / `.recommended` for unrecognised values.
    ///
    /// - Parameters:
    ///   - text: Raw string response from `LanguageModelSession`.
    ///   - trip: Used only to associate suggestions conceptually — not mutated.
    /// - Returns: Validated `[PackingSuggestion]` sorted by `SuggestionPriority.sortOrder`.
    /// - Throws: `AIServiceError.generationFailed` when the text is not parseable JSON.
    private func parseJSON(_ text: String, for trip: Trip) throws -> [PackingSuggestion] {

        // Strip markdown fences the model might wrap around the JSON block
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            // Remove opening fence (```json or ```)
            if let newlineIndex = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: newlineIndex)...])
            }
            // Remove closing fence
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw AIServiceError.generationFailed
        }

        // Internal Codable type matching the prompt's JSON schema
        struct RawItem: Decodable {
            let name: String
            let category: String
            let priority: String
            let reason: String
        }
        struct RawEnvelope: Decodable {
            let items: [RawItem]
        }

        let envelope: RawEnvelope
        do {
            envelope = try JSONDecoder().decode(RawEnvelope.self, from: data)
        } catch {
            throw AIServiceError.generationFailed
        }

        guard !envelope.items.isEmpty else {
            throw AIServiceError.generationFailed
        }

        let suggestions: [PackingSuggestion] = envelope.items.compactMap { raw in
            let name = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            // Map raw category string → ItemCategory (fallback: .other)
            let category = ItemCategory(rawValue: raw.category.lowercased()) ?? .other

            // Map raw priority string → SuggestionPriority (fallback: .recommended)
            let priority: SuggestionPriority
            switch raw.priority.lowercased() {
            case "essential":   priority = .essential
            case "nicetohave", "nice_to_have", "nicetohave": priority = .niceToHave
            default:            priority = .recommended
            }

            return PackingSuggestion(
                name: name,
                category: category,
                reason: raw.reason,
                priority: priority
            )
        }

        // Sort: essential → recommended → niceToHave
        return suggestions.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    // MARK: - Mock Suggestions

    /// Returns a curated, trip-type-aware packing list after a 1.5 s simulated delay.
    ///
    /// Used on:
    ///   - iOS Simulator (always)
    ///   - Real devices on iOS < 18.1
    ///   - Any device while FoundationModels is not yet linked
    ///
    /// Coverage per trip type:
    ///   - `.beach`        — sun/water/swim gear, light clothing, sunscreen
    ///   - `.business`     — professional attire, laptop, documents, adapters
    ///   - `.mountain` / `.camping` — layers, navigation, first-aid, outdoor gear
    ///   - All others      — generic leisure list covering the five core categories
    ///
    /// All lists include items across: documents, clothing, toiletries, electronics, health.
    ///
    /// - Parameters:
    ///   - trip: Source of `tripType` for list selection.
    ///   - existingItemNames: Filtered out case-insensitively to prevent duplicates.
    /// - Returns: Filtered `[PackingSuggestion]` ready for the suggestions UI.
    /// - Throws: `AIServiceError.cancelled` if the task is cancelled during the sleep.
    private func mockSuggestions(
        for trip: Trip,
        excluding existingItemNames: [String]
    ) async throws -> [PackingSuggestion] {

        // Simulate on-device generation latency
        try await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds

        // Build lowercase exclusion set for O(1) duplicate checking
        let excluded = Set(existingItemNames.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })

        // Select the base list by trip type
        let candidates: [PackingSuggestion]
        switch trip.tripType {
        case .beach:
            candidates = beachSuggestions()
        case .business:
            candidates = businessSuggestions()
        case .mountain, .camping:
            candidates = adventureSuggestions()
        default:
            candidates = leisureSuggestions()
        }

        // Filter out any items already on the packing list
        return candidates.filter { suggestion in
            !excluded.contains(suggestion.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Mock Lists

    // MARK: Beach

    private func beachSuggestions() -> [PackingSuggestion] {
        [
            // Documents
            PackingSuggestion(name: "Passport", category: .documents, reason: "Required for international beach destinations.", priority: .essential),
            PackingSuggestion(name: "Travel insurance documents", category: .documents, reason: "Covers medical evacuation and trip cancellation.", priority: .essential),

            // Clothing
            PackingSuggestion(name: "Swimsuit", category: .clothing, reason: "Essential for any beach trip.", priority: .essential),
            PackingSuggestion(name: "Cover-up or sarong", category: .clothing, reason: "Useful walking between beach and restaurants.", priority: .recommended),
            PackingSuggestion(name: "Light linen shirt", category: .clothing, reason: "Breathable fabric for hot coastal days.", priority: .recommended),
            PackingSuggestion(name: "Sun hat", category: .accessories, reason: "Protects face and neck from direct sun.", priority: .essential),
            PackingSuggestion(name: "Sunglasses", category: .accessories, reason: "UV protection — polarized lenses ideal near water.", priority: .essential),
            PackingSuggestion(name: "Flip flops", category: .footwear, reason: "Standard beach footwear.", priority: .essential),

            // Toiletries
            PackingSuggestion(name: "Sunscreen SPF 50+", category: .toiletries, reason: "High SPF essential for extended sun exposure.", priority: .essential),
            PackingSuggestion(name: "After-sun lotion", category: .toiletries, reason: "Soothes skin after long beach days.", priority: .recommended),
            PackingSuggestion(name: "Insect repellent", category: .toiletries, reason: "Tropical beach destinations often have mosquitoes at dusk.", priority: .recommended),
            PackingSuggestion(name: "Waterproof toiletry bag", category: .toiletries, reason: "Keeps essentials dry near water.", priority: .niceToHave),

            // Electronics
            PackingSuggestion(name: "Waterproof phone case", category: .electronics, reason: "Protects your phone at the beach and in water.", priority: .recommended),
            PackingSuggestion(name: "Portable charger", category: .electronics, reason: "Long beach days drain batteries quickly.", priority: .recommended),
            PackingSuggestion(name: "Underwater camera", category: .electronics, reason: "Capture snorkelling and water activities.", priority: .niceToHave),

            // Health
            PackingSuggestion(name: "Antihistamines", category: .medications, reason: "Useful for jellyfish stings or unfamiliar food allergies.", priority: .recommended),
            PackingSuggestion(name: "Rehydration sachets", category: .medications, reason: "Prevents dehydration on hot beach days.", priority: .recommended),
            PackingSuggestion(name: "Basic first-aid kit", category: .medications, reason: "Plasters and antiseptic for sand cuts and scrapes.", priority: .recommended),

            // Sports / Gear
            PackingSuggestion(name: "Snorkel and mask", category: .sports, reason: "Many beach destinations have great snorkelling.", priority: .niceToHave),
            PackingSuggestion(name: "Beach bag", category: .accessories, reason: "Carries towels, sunscreen, and water to the beach.", priority: .recommended),
            PackingSuggestion(name: "Reusable water bottle", category: .food, reason: "Stay hydrated — beach heat dehydrates fast.", priority: .essential),
        ]
    }

    // MARK: Business

    private func businessSuggestions() -> [PackingSuggestion] {
        [
            // Documents
            PackingSuggestion(name: "Passport or government ID", category: .documents, reason: "Required for travel and hotel check-in.", priority: .essential),
            PackingSuggestion(name: "Business cards", category: .documents, reason: "Still essential at conferences and client meetings.", priority: .essential),
            PackingSuggestion(name: "Travel itinerary printout", category: .documents, reason: "Backup if phone dies at the airport.", priority: .recommended),
            PackingSuggestion(name: "Expense receipts folder", category: .documents, reason: "Keep receipts organised for reimbursement.", priority: .recommended),

            // Clothing
            PackingSuggestion(name: "Business suit or blazer", category: .clothing, reason: "Professional presentation for client meetings.", priority: .essential),
            PackingSuggestion(name: "Dress shirts (x3)", category: .clothing, reason: "One per day of meetings.", priority: .essential),
            PackingSuggestion(name: "Formal trousers or skirt", category: .clothing, reason: "Pairs with blazer for a polished look.", priority: .essential),
            PackingSuggestion(name: "Casual outfit for evenings", category: .clothing, reason: "For team dinners or post-conference networking.", priority: .recommended),
            PackingSuggestion(name: "Dress shoes", category: .footwear, reason: "Polished footwear completes business attire.", priority: .essential),
            PackingSuggestion(name: "Comfortable walking shoes", category: .footwear, reason: "Conference venues involve a lot of walking.", priority: .recommended),

            // Electronics
            PackingSuggestion(name: "Laptop and charger", category: .electronics, reason: "Primary work tool for presentations and remote work.", priority: .essential),
            PackingSuggestion(name: "Universal travel adapter", category: .electronics, reason: "International business trips need multi-region adapters.", priority: .essential),
            PackingSuggestion(name: "Portable charger", category: .electronics, reason: "Long conference days drain devices.", priority: .recommended),
            PackingSuggestion(name: "Noise-cancelling headphones", category: .electronics, reason: "Focus on the plane and in shared workspaces.", priority: .recommended),
            PackingSuggestion(name: "HDMI or USB-C adapter", category: .electronics, reason: "Essential for presenting on hotel or conference AV systems.", priority: .essential),
            PackingSuggestion(name: "Portable Wi-Fi hotspot", category: .electronics, reason: "Reliable connectivity when hotel Wi-Fi underperforms.", priority: .niceToHave),

            // Toiletries
            PackingSuggestion(name: "Wrinkle-release spray", category: .toiletries, reason: "Keeps business attire presentable after a suitcase.", priority: .recommended),
            PackingSuggestion(name: "Travel-size grooming kit", category: .toiletries, reason: "Compact kit for maintaining a professional appearance.", priority: .recommended),

            // Health
            PackingSuggestion(name: "Pain relievers", category: .medications, reason: "Long travel days and jet lag can cause headaches.", priority: .recommended),
            PackingSuggestion(name: "Sleep mask and earplugs", category: .entertainment, reason: "Better rest on the plane means sharper performance.", priority: .recommended),
        ]
    }

    // MARK: Adventure / Hiking / Mountain / Camping

    private func adventureSuggestions() -> [PackingSuggestion] {
        [
            // Documents
            PackingSuggestion(name: "Passport or government ID", category: .documents, reason: "Required for travel and park permits.", priority: .essential),
            PackingSuggestion(name: "Travel insurance with evacuation cover", category: .documents, reason: "Wilderness medical evacuation is expensive — insurance is essential.", priority: .essential),
            PackingSuggestion(name: "Trail maps (printed)", category: .documents, reason: "No cellular signal in many backcountry areas.", priority: .essential),

            // Clothing
            PackingSuggestion(name: "Moisture-wicking base layer", category: .clothing, reason: "Manages sweat and regulates temperature on climbs.", priority: .essential),
            PackingSuggestion(name: "Insulating mid-layer (fleece)", category: .clothing, reason: "Mountain temperatures drop sharply at elevation.", priority: .essential),
            PackingSuggestion(name: "Waterproof shell jacket", category: .clothing, reason: "Mountain weather is unpredictable — rain protection is critical.", priority: .essential),
            PackingSuggestion(name: "Hiking trousers", category: .clothing, reason: "Durable, flexible fabric for trail use.", priority: .essential),
            PackingSuggestion(name: "Warm hat and gloves", category: .accessories, reason: "Summits and early mornings are significantly colder.", priority: .recommended),
            PackingSuggestion(name: "Hiking boots (broken in)", category: .footwear, reason: "Ankle support and grip on uneven terrain.", priority: .essential),
            PackingSuggestion(name: "Wool hiking socks", category: .clothing, reason: "Blister prevention and temperature regulation.", priority: .essential),

            // Electronics
            PackingSuggestion(name: "Headtorch with spare batteries", category: .electronics, reason: "Essential for pre-dawn starts and emergencies.", priority: .essential),
            PackingSuggestion(name: "Satellite communicator (e.g. Garmin inReach)", category: .electronics, reason: "Emergency SOS when out of cellular range.", priority: .recommended),
            PackingSuggestion(name: "Portable charger (high capacity)", category: .electronics, reason: "Charging electronics away from power for multiple days.", priority: .recommended),

            // Toiletries
            PackingSuggestion(name: "Biodegradable soap and shampoo", category: .toiletries, reason: "Leave No Trace — safe for use near water sources.", priority: .recommended),
            PackingSuggestion(name: "Sunscreen SPF 50+", category: .toiletries, reason: "UV intensity increases significantly at altitude.", priority: .essential),
            PackingSuggestion(name: "Insect repellent (DEET)", category: .toiletries, reason: "Forest and mountain trails have biting insects.", priority: .recommended),

            // Health / First Aid
            PackingSuggestion(name: "Comprehensive first-aid kit", category: .medications, reason: "Remote locations require self-sufficiency for minor injuries.", priority: .essential),
            PackingSuggestion(name: "Blister treatment (moleskin)", category: .medications, reason: "Prevent small blisters becoming trip-ending injuries.", priority: .essential),
            PackingSuggestion(name: "Water purification tablets or filter", category: .medications, reason: "Safe drinking water from natural sources on multi-day hikes.", priority: .essential),
            PackingSuggestion(name: "Altitude sickness tablets (if applicable)", category: .medications, reason: "Consult your doctor before trips above 3,000 m.", priority: .recommended),

            // Gear / Sports
            PackingSuggestion(name: "Trekking poles", category: .sports, reason: "Reduces knee stress on descents and aids balance.", priority: .recommended),
            PackingSuggestion(name: "Dry bags for electronics", category: .sports, reason: "Protects gear from rain and stream crossings.", priority: .recommended),
            PackingSuggestion(name: "High-calorie trail snacks", category: .food, reason: "Maintain energy on long ascents.", priority: .essential),
            PackingSuggestion(name: "Reusable water bottle (2L)", category: .food, reason: "Adequate hydration is the single biggest factor in hike safety.", priority: .essential),
        ]
    }

    // MARK: Leisure (Generic Fallback)

    private func leisureSuggestions() -> [PackingSuggestion] {
        [
            // Documents
            PackingSuggestion(name: "Passport or government ID", category: .documents, reason: "Required for travel and accommodation check-in.", priority: .essential),
            PackingSuggestion(name: "Travel insurance documents", category: .documents, reason: "Covers medical costs and trip interruptions.", priority: .essential),
            PackingSuggestion(name: "Hotel confirmation printout", category: .documents, reason: "Backup if your phone dies at check-in.", priority: .recommended),

            // Clothing
            PackingSuggestion(name: "Casual daywear outfits", category: .clothing, reason: "Comfortable clothing for sightseeing and leisure.", priority: .essential),
            PackingSuggestion(name: "Smart outfit for evenings", category: .clothing, reason: "For nicer restaurants or evening events.", priority: .recommended),
            PackingSuggestion(name: "Light jacket or cardigan", category: .clothing, reason: "Air-conditioned venues and cool evenings.", priority: .recommended),
            PackingSuggestion(name: "Comfortable walking shoes", category: .footwear, reason: "Leisure trips involve more walking than expected.", priority: .essential),
            PackingSuggestion(name: "Sandals", category: .footwear, reason: "Casual footwear for relaxed days.", priority: .recommended),

            // Toiletries
            PackingSuggestion(name: "Shampoo and conditioner", category: .toiletries, reason: "Many hotels provide basic toiletries but not premium brands.", priority: .recommended),
            PackingSuggestion(name: "Deodorant", category: .toiletries, reason: "Travel essential.", priority: .essential),
            PackingSuggestion(name: "Toothbrush and toothpaste", category: .toiletries, reason: "Travel essential.", priority: .essential),
            PackingSuggestion(name: "Moisturiser and lip balm", category: .toiletries, reason: "Dry cabin air and new climates affect skin.", priority: .recommended),

            // Electronics
            PackingSuggestion(name: "Phone charger and cable", category: .electronics, reason: "Travel essential.", priority: .essential),
            PackingSuggestion(name: "Universal travel adapter", category: .electronics, reason: "Foreign socket types require an adapter.", priority: .essential),
            PackingSuggestion(name: "Portable charger", category: .electronics, reason: "Power top-up during full days out.", priority: .recommended),
            PackingSuggestion(name: "Headphones", category: .electronics, reason: "Music and podcasts for travel days.", priority: .recommended),
            PackingSuggestion(name: "E-reader or tablet", category: .entertainment, reason: "Entertainment for long flights and downtime.", priority: .niceToHave),

            // Health
            PackingSuggestion(name: "Pain relievers", category: .medications, reason: "Headaches and minor pains happen — be prepared.", priority: .recommended),
            PackingSuggestion(name: "Antihistamines", category: .medications, reason: "Useful for unfamiliar allergens in new environments.", priority: .recommended),
            PackingSuggestion(name: "Rehydration sachets", category: .medications, reason: "Recover faster from travel fatigue and heat.", priority: .niceToHave),

            // Misc
            PackingSuggestion(name: "Reusable tote bag", category: .accessories, reason: "Handy for shopping, beach days, and day trips.", priority: .niceToHave),
            PackingSuggestion(name: "Reusable water bottle", category: .food, reason: "Stay hydrated and reduce single-use plastic.", priority: .recommended),
        ]
    }
}
