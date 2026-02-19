// PackingPromptBuilder.swift
// Otis — Services/PackingPromptBuilder.swift
//
// Strategy C: Contextual reasoning prompts that make Otis feel like a
// knowledgeable friend who has BEEN to your destination — not a generic
// packing checklist generator.
//
// The "magic" comes from three layers:
//   1. Otis persona — warm, specific, never condescending
//   2. Destination-aware context — climate, culture, practical realities
//   3. Duplicate prevention — explicit existing items list so Otis never
//      suggests what you already have
//
// Prompt architecture:
//   System prompt  — Otis's persona + rigid JSON output contract
//   User prompt    — full trip context + destination-specific injection
//
// Output contract (json_object mode):
//   {
//     "suggestions": [
//       {
//         "name": "Reef-safe sunscreen SPF 50+",
//         "category": "toiletries",
//         "reason": "Bali's beaches legally require reef-safe products to protect coral",
//         "priority": "essential"
//       }
//     ]
//   }

import Foundation

// MARK: - PackingPromptBuilder

struct PackingPromptBuilder {

    // MARK: - System Prompt

    /// The system prompt establishes Otis's persona and the rigid output
    /// contract the model must follow. This is constant across all trips —
    /// all trip-specific context goes in the user prompt.
    static func systemPrompt() -> String {
        """
        You are Otis, a thoughtful and well-traveled otter who helps people pack for trips. \
        You have been to most major destinations and know their practical realities — not just \
        tourist highlights. You give specific, honest, and sometimes surprising packing advice \
        that feels like it comes from a well-traveled friend, not a generic checklist.

        Your suggestions are always:
        - Specific to the actual destination and trip type (never generic)
        - Actionable and concrete (product types, not vague categories)
        - Honest about WHY each item matters for THIS trip
        - Occasionally surprising — you notice things guidebooks miss

        You NEVER suggest:
        - Basic toiletries that any traveler already owns (toothbrush, shampoo, deodorant)
          UNLESS the destination has specific requirements (reef-safe sunscreen for coral reefs,
          altitude-specific lip balm, etc.)
        - Items already in the user's existing packing list
        - Vague items like "appropriate clothing" or "comfortable shoes" — be specific

        OUTPUT CONTRACT — you must ALWAYS return valid JSON in exactly this schema:
        {
          "suggestions": [
            {
              "name": "string — specific item name, 2–6 words",
              "category": "string — exactly one of: clothing, toiletries, electronics, documents, medications, footwear, accessories, sports, food, entertainment, other",
              "reason": "string — 1–2 sentences max explaining WHY this item matters for THIS specific trip. Be specific. Reference the destination, season, or trip type.",
              "priority": "string — exactly one of: essential, recommended, niceToHave"
            }
          ]
        }

        Rules:
        - Return 15–25 suggestions total
        - At most 4 items with priority "essential" — reserve for genuinely critical items
        - At least 5 items with priority "recommended"
        - Remaining items are "niceToHave"
        - No duplicate names
        - No items from the user's existing list
        - The JSON must be valid and parseable — no trailing commas, no comments, no markdown
        - Return ONLY the JSON object. No preamble, no explanation, no markdown code fences.
        """
    }

    // MARK: - User Prompt

    /// Builds the user-facing prompt with full trip context.
    /// This is the heart of Strategy C — each piece of context narrows the
    /// model's output from generic to genuinely trip-specific.
    ///
    /// - Parameters:
    ///   - trip: The trip to generate suggestions for.
    ///   - existingItems: Names of items already on the list (prevents duplicates).
    static func userPrompt(for trip: Trip, existingItems: [String]) -> String {
        let destination = trip.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let nights = nightsDescription(for: trip)
        let monthAndSeason = monthSeasonDescription(for: trip)
        let existingList = existingItems.isEmpty
            ? "None yet — this is a fresh list."
            : existingItems.joined(separator: ", ")
        let tripContext = tripTypeContext(for: trip)
        let destinationHints = destinationContextHints(for: trip)

        return """
        Destination: \(destination)
        Trip type: \(trip.tripType.displayName)
        Duration: \(nights)
        When: \(monthAndSeason)
        Already packing: \(existingList)

        Context:
        \(tripContext)
        \(destinationHints)

        Suggest \(targetSuggestionCount(for: trip)) packing items specific to this trip. \
        Focus on items I might forget, or that are uniquely relevant to \(destination). \
        Skip obvious generic toiletries unless they are location-specific (e.g. reef-safe \
        sunscreen for coral reef areas, altitude sickness medication for high-elevation destinations). \
        Reference the destination by name in your reasons where relevant.
        """
    }

    // MARK: - Category Mapper

    /// Maps an AI-returned category string to the app's ItemCategory enum.
    /// Case-insensitive and handles common synonyms the model might use.
    static func mapCategory(_ string: String) -> ItemCategory {
        let normalized = string
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip any surrounding punctuation or quotes the model might add
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        switch normalized {
        case "clothing", "clothes", "apparel", "garments", "wear":
            return .clothing
        case "toiletries", "toiletry", "hygiene", "grooming", "personal care", "beauty":
            return .toiletries
        case "electronics", "electronic", "tech", "technology", "gadgets", "devices":
            return .electronics
        case "documents", "document", "paperwork", "papers", "ids", "identification":
            return .documents
        case "medications", "medication", "medicine", "medicines", "health", "medical", "pharmacy":
            return .medications
        case "footwear", "shoes", "shoe", "boots", "sandals":
            return .footwear
        case "accessories", "accessory", "gear", "extras":
            return .accessories
        case "sports", "sport", "outdoors", "outdoor", "fitness", "exercise", "recreation":
            return .sports
        case "food", "snacks", "snack", "food & snacks", "drinks", "nutrition":
            return .food
        case "entertainment", "media", "books", "reading", "fun":
            return .entertainment
        default:
            return .other
        }
    }

    // MARK: - Private Helpers

    /// Returns a human-readable duration string for the user prompt.
    private static func nightsDescription(for trip: Trip) -> String {
        if let days = trip.durationInDays {
            let nights = max(days, 1)
            return "\(nights) night\(nights == 1 ? "" : "s")"
        }
        // Fallback: use a rough estimate if no return date is set
        return "open-ended trip"
    }

    /// Returns a contextual month + season description for the user prompt.
    /// Provides hemisphere-correct season and approximate temperature context.
    private static func monthSeasonDescription(for trip: Trip) -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: trip.departureDate)
        let season = trip.season

        let monthName: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM"
            return formatter.string(from: trip.departureDate)
        }()

        let seasonHint = seasonTemperatureHint(season: season, tripType: trip.tripType)
        return "\(monthName) (\(season.displayName.lowercased())\(seasonHint))"
    }

    /// Returns an approximate temperature/weather hint for the given season
    /// and trip type, to give the model better climate context.
    private static func seasonTemperatureHint(season: Season, tripType: TripType) -> String {
        switch (tripType, season) {
        case (.beach, .summer):
            return ", hot and humid, 28-35°C / 82-95°F"
        case (.beach, .winter):
            return ", warm, 22-28°C / 72-82°F — ideal beach weather"
        case (.beach, .spring), (.beach, .autumn):
            return ", warm with occasional rain, 24-30°C / 75-86°F"
        case (.ski, .winter):
            return ", sub-zero on mountain, -15 to -5°C / 5-23°F"
        case (.mountain, .summer):
            return ", cool at altitude, variable weather — layer up"
        case (.mountain, .winter):
            return ", cold, snow likely above treeline"
        case (.business, _):
            return " — indoor/outdoor mix, business dress code applies"
        case (_, .summer):
            return ", warm, 20-28°C / 68-82°F"
        case (_, .winter):
            return ", cold, 0-10°C / 32-50°F"
        case (_, .spring):
            return ", mild and changeable, 12-20°C / 54-68°F"
        case (_, .autumn):
            return ", cooling down, 10-18°C / 50-64°F, layers recommended"
        }
    }

    /// Returns trip-type-specific context that primes the model to think about
    /// the practical realities of this kind of trip.
    private static func tripTypeContext(for trip: Trip) -> String {
        switch trip.tripType {
        case .beach:
            return """
            This is a beach trip. Key considerations: sun protection, water activities, \
            beach access, evening dining (often smart-casual), and any water sports planned. \
            Many tropical beach destinations have coral reef protection laws (reef-safe sunscreen \
            required). Consider whether the beach is rocky or sandy — affects footwear choice.
            """
        case .business:
            return """
            This is a business trip. Key considerations: professional presentation (wrinkle-free \
            clothing, dress shoes), productivity tools (chargers, adapters, noise cancellation), \
            networking events, and back-to-back meetings. Dress code matters — pack one level \
            above what you expect to need. Hotels are often better equipped than Airbnbs for \
            business travel.
            """
        case .mountain:
            return """
            This is a mountain trip. Key considerations: rapid weather changes at altitude, \
            physical exertion (blisters, muscle fatigue, hydration), potential altitude sickness \
            above 8,000 ft / 2,400 m, wildlife and environmental regulations, and the 10 essentials \
            of hiking safety. Layer systems are critical — conditions change fast.
            """
        case .ski:
            return """
            This is a ski trip. Key considerations: cold and wind protection on lifts and runs, \
            UV protection at altitude (snow reflects 80% of UV), après-ski comfort and style, \
            equipment rental vs. bringing your own, and ski resort-specific logistics (lift passes, \
            lockers, boot warmers). Prevent blisters — ski boots are unforgiving.
            """
        case .city:
            return """
            This is a city break. Key considerations: extensive walking on varied terrain, mix of \
            casual and smart-casual settings, transit navigation, keeping valuables safe in crowds, \
            and restaurant reservations. Cities have everything available to buy — focus on comfort \
            and security items that make the trip smoother, not things easily purchased on arrival.
            """
        case .international:
            return """
            This is an international trip. Key considerations: documentation (visa, passport validity, \
            health requirements), currency and payment methods, power adapters, communication (SIM card, \
            roaming plan), health precautions (vaccines, travel insurance), and cultural dress codes. \
            Always carry physical copies of critical documents. Check entry requirements — they change.
            """
        case .weekend:
            return """
            This is a weekend getaway. Key considerations: packing light for 2-3 days, having a \
            flexible wardrobe that works for casual daytime and a nicer evening out, road trip \
            comfort if driving, and the tendency to forget small basics when packing quickly. \
            The goal is to not have to think about what you're missing once you arrive.
            """
        }
    }

    /// Returns destination-specific hints by extracting keyword signals from
    /// the destination string. This is a lightweight heuristic — the model
    /// handles the heavy lifting of destination knowledge.
    ///
    /// Pattern: looks for known city/country/region keywords and injects
    /// practical context the model can build on.
    private static func destinationContextHints(for trip: Trip) -> String {
        let destination = trip.destination.lowercased()

        // Build a composite hint based on destination keywords
        var hints: [String] = []

        // Southeast Asia
        if containsAny(destination, ["bali", "thailand", "bangkok", "vietnam", "cambodia", "indonesia", "malaysia", "philippines", "singapore"]) {
            hints.append("Southeast Asian destinations: temple visits require covered shoulders and knees, cash-heavy economies (ATMs often unreliable), scooter/moped culture, tropical humidity affects electronics and clothing, street food is excellent but traveler's stomach is real.")
        }

        // Japan
        if containsAny(destination, ["japan", "tokyo", "kyoto", "osaka", "hiroshima", "sapporo"]) {
            hints.append("Japan: shoes that slip on/off easily (frequent removal at temples and traditional restaurants), IC card for transit (Suica/Pasmo), cash is still widely preferred over cards, modest clothing for shrine visits, yen in small denominations for vending machines and small shops.")
        }

        // Europe
        if containsAny(destination, ["paris", "france", "italy", "rome", "florence", "spain", "barcelona", "madrid", "amsterdam", "netherlands", "london", "uk", "germany", "berlin", "prague", "portugal", "lisbon", "greece", "athens", "croatia"]) {
            hints.append("European cities: cobblestone streets are tough on wheeled luggage and thin-soled shoes, many restaurants don't seat until 8pm+, pickpocketing in tourist areas (keep passport copy separate from original), Schengen entry rules if visiting multiple countries, tap water is generally safe.")
        }

        // Latin America
        if containsAny(destination, ["mexico", "tulum", "cancun", "colombia", "bogota", "peru", "lima", "machu picchu", "brazil", "rio", "argentina", "buenos aires", "costa rica", "cuba", "dominican republic"]) {
            hints.append("Latin American destinations: altitude considerations for Andean locations, water safety varies widely (check local advice), cash economy in many areas, sun protection critical at equatorial latitudes, mosquito prevention especially important at dusk.")
        }

        // India
        if containsAny(destination, ["india", "mumbai", "delhi", "jaipur", "goa", "bangalore", "chennai", "kerala"]) {
            hints.append("India: conservative dress for temples and rural areas (both men and women), water from bottles only (never tap), stomach medications are strongly advised, mosquito protection essential, carry toilet paper/tissues as not universal, bargaining is expected in markets.")
        }

        // Africa / Safari
        if containsAny(destination, ["kenya", "tanzania", "safari", "serengeti", "masai mara", "south africa", "cape town", "morocco", "egypt", "ethiopia", "rwanda"]) {
            hints.append("African safari/travel destinations: neutral/khaki colors for wildlife viewing (avoid bright colors that disturb animals), layers essential as mornings are cold even in summer, yellow fever vaccination certificate required for many crossings, cash USD widely accepted, power adapters for Type G or Type D depending on country.")
        }

        // Middle East
        if containsAny(destination, ["dubai", "uae", "abu dhabi", "qatar", "doha", "saudi", "jordan", "petra", "israel", "tel aviv"]) {
            hints.append("Middle Eastern destinations: modest dress required especially in religious sites and public spaces, Friday-Saturday weekend (businesses closed), extreme heat in summer months (40°C+), alcohol laws vary significantly by country.")
        }

        // Australia / New Zealand
        if containsAny(destination, ["australia", "sydney", "melbourne", "brisbane", "new zealand", "auckland", "queenstown"]) {
            hints.append("Australia/NZ: Southern hemisphere reverses seasons (December = summer), strict biosecurity laws (declare all food, wood, and outdoor gear at customs), UV radiation is extreme year-round (SPF 50+ standard), wildlife encounters are real outside cities.")
        }

        // Cold / Arctic destinations
        if containsAny(destination, ["iceland", "norway", "finland", "sweden", "alaska", "canada", "scandinavia", "reykjavik", "oslo", "helsinki", "stockholm", "lapland"]) {
            hints.append("Nordic/cold destinations: layering system essential (base, mid, shell), waterproof outer layer non-negotiable, merino wool base layers worth packing, extended daylight (summer) or near-darkness (winter) affects sleep — bring eye mask, frostbite risk if not properly layered.")
        }

        // High altitude
        if containsAny(destination, ["tibet", "nepal", "kathmandu", "la paz", "bolivia", "quito", "ecuador", "cusco", "peru", "colorado", "denver"]) {
            hints.append("High altitude destination: altitude sickness is real above 2,500m / 8,200ft — ascend slowly if possible, Diamox (consult doctor), stay hydrated, avoid alcohol first 24h at altitude, sun protection is stronger at altitude (UV increases ~10% per 1,000m).")
        }

        // Beach / Tropical generic fallback
        if hints.isEmpty && trip.tripType == .beach {
            hints.append("Tropical beach destination: reef-safe sunscreen, water activity gear, formal dress code for nice restaurants, mosquito protection for evenings, hydration critical in humid heat.")
        }

        if hints.isEmpty {
            // No specific hints — let the model use its own knowledge
            return "Use your knowledge of \(trip.destination) to suggest locally relevant items."
        }

        return "Destination notes:\n" + hints.joined(separator: "\n")
    }

    /// Returns the ideal number of suggestions to request for this trip length.
    private static func targetSuggestionCount(for trip: Trip) -> Int {
        guard let days = trip.durationInDays else { return 20 }
        switch days {
        case 0...2: return 15
        case 3...5: return 18
        case 6...10: return 22
        default:    return 25
        }
    }

    /// Checks if a string contains any of the provided substrings.
    private static func containsAny(_ string: String, _ substrings: [String]) -> Bool {
        substrings.contains { string.contains($0) }
    }
}

// MARK: - TripType Prompt Context Extension

extension TripType {
    /// A brief sentence injected into the AI prompt describing this trip type's
    /// packing priorities. Used by PackingPromptBuilder.tripTypeContext().
    var packingPromptContext: String {
        switch self {
        case .beach:
            return "Sun, water, sand — protect skin, keep electronics dry, dress smart-casual for evenings."
        case .business:
            return "Presentations, meetings, networking — professional appearance and productivity tools."
        case .mountain:
            return "Physical exertion, altitude, weather changes — layers, safety, endurance."
        case .city:
            return "Walking, culture, dining — comfort, security, smart-casual versatility."
        case .international:
            return "Borders, customs, foreign systems — documentation, adapters, health preparedness."
        case .weekend:
            return "Short trip, quick pack — essentials, one nice outfit, travel comfort."
        case .ski:
            return "Cold, speed, altitude — warmth, protection, après-ski comfort."
        }
    }
}
