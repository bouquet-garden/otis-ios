// OpenAIService.swift
// Otis — Services/OpenAIService.swift
//
// Pure URLSession-based OpenAI client. No external SDK dependencies.
// Uses Swift concurrency (async/await) throughout and actor isolation
// for thread safety. Automatically falls back to mock suggestions when
// AppConfig.openAIAPIKey is empty (development without credentials).
//
// Model: gpt-4o-mini   — fast, cost-efficient, JSON-mode capable
// Endpoint: POST https://api.openai.com/v1/chat/completions
//
// Retry policy: 1 automatic retry on network errors only.
//               4xx errors (auth, quota) are never retried.
//
// Logging: #if DEBUG only — request/response bodies are printed to console
//          and never reach production builds.

import Foundation
import OSLog

// MARK: - OpenAI Error

/// Typed errors surfaced from the OpenAI integration layer.
/// All cases provide a user-facing localizedDescription suitable for display
/// in the AI suggestion UI — no raw HTTP jargon exposed to the user.
enum OpenAIError: LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case quotaExceeded
    case serverError(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Otis isn't connected yet. Add your OpenAI key in Secrets.xcconfig to enable AI suggestions."
        case .networkError(let underlying):
            return "Couldn't reach Otis's brain — check your connection. (\(underlying.localizedDescription))"
        case .invalidResponse:
            return "Otis got confused by the response. Try again in a moment."
        case .rateLimited:
            return "Otis is taking a quick breath — you've been busy! Try again in a moment."
        case .quotaExceeded:
            return "Otis has hit his thinking limit for today. Check your OpenAI usage dashboard."
        case .serverError(let code):
            return "OpenAI returned an error (HTTP \(code)). Try again shortly."
        case .decodingError(let detail):
            return "Otis couldn't read the suggestions. (\(detail))"
        }
    }

    /// True when a retry could plausibly succeed. 4xx errors are never retried.
    var isRetryable: Bool {
        switch self {
        case .networkError:   return true
        case .serverError:    return true
        default:              return false
        }
    }
}

// MARK: - Request / Response Codable Types

/// A single message in the OpenAI chat messages array.
struct ChatMessage: Codable {
    let role: String    // "system" | "user" | "assistant"
    let content: String
}

/// The top-level request body sent to /v1/chat/completions.
struct OpenAIRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens     = "max_tokens"
        case responseFormat = "response_format"
    }
}

/// Instructs the model to return pure JSON (json_object mode).
/// This eliminates markdown fences and prose wrappers from the response.
struct ResponseFormat: Codable {
    let type: String  // "json_object"
}

/// Top-level decoded response from /v1/chat/completions.
struct OpenAIResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

struct OpenAIChoice: Codable {
    let index: Int
    let message: ChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens     = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens      = "total_tokens"
    }
}

/// The AI-generated suggestion wrapper returned by the API in JSON mode.
/// The model is instructed to always return `{ "suggestions": [...] }`.
private struct SuggestionsEnvelope: Codable {
    let suggestions: [RawSuggestion]
}

/// Raw suggestion as decoded from the model's JSON output before we
/// validate and convert to the public-facing PackingSuggestion type.
private struct RawSuggestion: Codable {
    let name: String
    let category: String
    let reason: String
    let priority: String
}

// MARK: - PackingSuggestion (Public Output Type)

/// Priority tier for an AI packing suggestion. Influences how Otis presents
/// it in the suggestion card UI — essential items appear first with a
/// distinct visual treatment.
enum SuggestionPriority: String, Codable, CaseIterable {
    case essential      // Must bring — safety, legal, trip-critical
    case recommended    // Strong suggestion for this specific trip
    case niceToHave     // Comfort/convenience item worth considering

    var displayName: String {
        switch self {
        case .essential:   return "Essential"
        case .recommended: return "Recommended"
        case .niceToHave:  return "Nice to Have"
        }
    }

    var sortOrder: Int {
        switch self {
        case .essential:   return 0
        case .recommended: return 1
        case .niceToHave:  return 2
        }
    }
}

/// A single AI-generated packing suggestion, ready for display in the
/// suggestion card UI and conversion to a PackingItem via PackingItemMapper.
struct PackingSuggestion: Codable, Identifiable {
    let id: UUID
    let name: String
    let category: ItemCategory
    let reason: String           // Short, specific rationale — the "magic" text
    let priority: SuggestionPriority
    var isAccepted: Bool         // User tapped "Add to list"

    init(
        id: UUID = UUID(),
        name: String,
        category: ItemCategory,
        reason: String,
        priority: SuggestionPriority,
        isAccepted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.reason = reason
        self.priority = priority
        self.isAccepted = isAccepted
    }
}

// MARK: - OpenAIService

/// Thread-safe actor that owns all communication with the OpenAI API.
/// Call from any async context — actor isolation prevents concurrent
/// mutations to internal state.
///
/// Usage:
/// ```swift
/// let suggestions = try await OpenAIService.shared.generatePackingSuggestions(for: trip)
/// ```
actor OpenAIService {

    // MARK: Singleton

    static let shared = OpenAIService()
    private init() {}

    // MARK: Private State

    private let logger = Logger(subsystem: "com.bouquetgarden.otis", category: "OpenAIService")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    // MARK: - Public API

    /// Generates a ranked list of personalized packing suggestions for the
    /// given trip. Calls GPT-4o-mini with Strategy C contextual prompts.
    ///
    /// - Parameter trip: The trip whose destination, type, duration, and
    ///   season inform the AI context.
    /// - Parameter existingItemNames: Names of items already on the list —
    ///   passed to the prompt to prevent duplicates.
    /// - Returns: An array of `PackingSuggestion` sorted by priority
    ///   (essential first), typically 15–25 items.
    /// - Throws: `OpenAIError` for any failure scenario.
    func generatePackingSuggestions(
        for trip: Trip,
        existingItemNames: [String] = []
    ) async throws -> [PackingSuggestion] {

        // --- Mock mode: no API key configured ---
        guard !AppConfig.openAIAPIKey.isEmpty else {
            logger.warning("OpenAI API key not set — returning mock suggestions for development.")
            return mockSuggestions(for: trip)
        }

        let messages = buildMessages(for: trip, existingItems: existingItemNames)
        return try await performRequestWithRetry(messages: messages, trip: trip)
    }

    // MARK: - Private: Request Builder

    /// Assembles the full [ChatMessage] array (system + user) from the prompt builder.
    private func buildMessages(for trip: Trip, existingItems: [String]) -> [ChatMessage] {
        [
            ChatMessage(role: "system", content: PackingPromptBuilder.systemPrompt()),
            ChatMessage(role: "user",   content: PackingPromptBuilder.userPrompt(for: trip, existingItems: existingItems))
        ]
    }

    /// Builds a URLRequest with the Authorization header, Content-Type,
    /// and a serialized OpenAIRequest body.
    private func makeRequest(messages: [ChatMessage]) throws -> URLRequest {
        guard let url = URL(string: AppConfig.openAIChatEndpoint) else {
            throw OpenAIError.invalidResponse
        }

        let body = OpenAIRequest(
            model: AppConfig.openAIModel,
            messages: messages,
            temperature: AppConfig.openAITemperature,
            maxTokens: AppConfig.openAIMaxTokens,
            responseFormat: ResponseFormat(type: "json_object")
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AppConfig.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        #if DEBUG
        logger.debug("OpenAI request → model: \(AppConfig.openAIModel), messages: \(messages.count), maxTokens: \(AppConfig.openAIMaxTokens)")
        #endif

        return request
    }

    // MARK: - Private: Retry Logic

    /// Performs the API call with one automatic retry on retryable errors.
    /// 4xx responses (auth failures, quota, validation) are never retried.
    private func performRequestWithRetry(messages: [ChatMessage], trip: Trip) async throws -> [PackingSuggestion] {
        do {
            return try await performRequest(messages: messages)
        } catch let error as OpenAIError where error.isRetryable {
            logger.info("OpenAI request failed with retryable error — retrying once. Error: \(error.localizedDescription ?? "")")
            // Brief back-off before retry
            try await Task.sleep(for: .seconds(1.5))
            return try await performRequest(messages: messages)
        }
        // Non-retryable errors propagate immediately
    }

    /// Executes one HTTP call to the OpenAI API, validates the response,
    /// and parses the JSON content into [PackingSuggestion].
    private func performRequest(messages: [ChatMessage]) async throws -> [PackingSuggestion] {
        let request: URLRequest
        do {
            request = try makeRequest(messages: messages)
        } catch {
            throw OpenAIError.networkError(error)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        #if DEBUG
        logger.debug("OpenAI response ← HTTP \(httpResponse.statusCode), bytes: \(data.count)")
        if let raw = String(data: data, encoding: .utf8) {
            logger.debug("OpenAI raw response body:\n\(raw)")
        }
        #endif

        // --- HTTP status handling ---
        switch httpResponse.statusCode {
        case 200...299:
            break // Success — continue to parse
        case 429:
            // Distinguish rate-limit vs quota-exceeded via error body if possible
            if let body = try? decoder.decode(OpenAIErrorBody.self, from: data),
               body.error.type == "insufficient_quota" {
                throw OpenAIError.quotaExceeded
            }
            throw OpenAIError.rateLimited
        case 401, 403:
            throw OpenAIError.missingAPIKey
        case 400...499:
            throw OpenAIError.serverError(httpResponse.statusCode)
        case 500...599:
            throw OpenAIError.serverError(httpResponse.statusCode)
        default:
            throw OpenAIError.serverError(httpResponse.statusCode)
        }

        return try parseResponse(data)
    }

    // MARK: - Private: Response Parser

    /// Decodes the OpenAI response body and extracts the structured
    /// suggestions from the model's JSON-mode content string.
    ///
    /// Handles the two-level decode:
    ///   1. Outer: OpenAIResponse (choices[0].message.content is a JSON string)
    ///   2. Inner: SuggestionsEnvelope → [RawSuggestion] → [PackingSuggestion]
    private func parseResponse(_ data: Data) throws -> [PackingSuggestion] {

        // Step 1: Decode the outer OpenAI response envelope
        let openAIResponse: OpenAIResponse
        do {
            openAIResponse = try decoder.decode(OpenAIResponse.self, from: data)
        } catch {
            logger.error("Failed to decode OpenAI outer response: \(error.localizedDescription)")
            throw OpenAIError.decodingError("outer envelope: \(error.localizedDescription)")
        }

        guard let choice = openAIResponse.choices.first else {
            throw OpenAIError.invalidResponse
        }

        #if DEBUG
        if let usage = openAIResponse.usage {
            logger.debug("OpenAI token usage — prompt: \(usage.promptTokens), completion: \(usage.completionTokens), total: \(usage.totalTokens)")
        }
        #endif

        // Step 2: The model's text content IS the JSON string in json_object mode
        let contentString = choice.message.content
        guard let contentData = contentString.data(using: .utf8) else {
            throw OpenAIError.decodingError("could not encode content string as UTF-8")
        }

        // Step 3: Decode the inner suggestions envelope
        let envelope: SuggestionsEnvelope
        do {
            envelope = try decoder.decode(SuggestionsEnvelope.self, from: contentData)
        } catch {
            logger.error("Failed to decode suggestions envelope: \(error.localizedDescription)")
            logger.error("Content was: \(contentString)")
            throw OpenAIError.decodingError("suggestions envelope: \(error.localizedDescription)")
        }

        // Step 4: Map raw suggestions → PackingSuggestion, filtering invalids
        let suggestions = envelope.suggestions.compactMap { raw -> PackingSuggestion? in
            let trimmedName = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedReason = raw.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !trimmedReason.isEmpty else {
                logger.warning("Skipping suggestion with empty name or reason: \(raw.name)")
                return nil
            }

            let category = PackingPromptBuilder.mapCategory(raw.category)
            let priority = SuggestionPriority(rawValue: raw.priority) ?? .recommended

            return PackingSuggestion(
                name: trimmedName,
                category: category,
                reason: trimmedReason,
                priority: priority
            )
        }

        // Sort by priority before returning
        let sorted = suggestions.sorted { $0.priority.sortOrder < $1.priority.sortOrder }

        #if DEBUG
        logger.debug("Parsed \(sorted.count) suggestions from OpenAI response.")
        #endif

        return sorted
    }

    // MARK: - Mock Mode

    /// Returns realistic mock suggestions when no API key is configured.
    /// Varies content by TripType so the UI is demonstrably contextual even
    /// without live credentials. Used in development and UI previews.
    func mockSuggestions(for trip: Trip) -> [PackingSuggestion] {
        switch trip.tripType {
        case .beach:
            return beachMockSuggestions()
        case .business:
            return businessMockSuggestions()
        case .mountain:
            return mountainMockSuggestions()
        case .ski:
            return skiMockSuggestions()
        case .city:
            return cityMockSuggestions()
        case .international:
            return internationalMockSuggestions()
        case .weekend:
            return weekendMockSuggestions()
        }
    }

    private func beachMockSuggestions() -> [PackingSuggestion] {
        [
            PackingSuggestion(name: "Reef-safe sunscreen SPF 50+", category: .toiletries, reason: "Many tropical destinations legally require reef-safe formulas. Regular sunscreen can damage coral.", priority: .essential),
            PackingSuggestion(name: "Rash guard (long sleeve)", category: .clothing, reason: "Snorkeling and extended water time cause bad sunburns even with sunscreen applied.", priority: .essential),
            PackingSuggestion(name: "Dry bag (10L)", category: .accessories, reason: "Keeps your phone, cash, and documents dry on boat trips and water activities.", priority: .recommended),
            PackingSuggestion(name: "After-sun aloe gel", category: .toiletries, reason: "Almost every beach trip ends with at least one sunburn day. You'll be glad it's there.", priority: .recommended),
            PackingSuggestion(name: "Waterproof phone case", category: .electronics, reason: "Snorkeling photos are worth it. Losing your phone to a wave is not.", priority: .recommended),
            PackingSuggestion(name: "Microfiber beach towel", category: .accessories, reason: "Lighter than hotel towels, dries in 30 minutes, and doesn't use up your luggage weight.", priority: .recommended),
            PackingSuggestion(name: "Portable Bluetooth speaker", category: .entertainment, reason: "Beach days are better with music. Waterproof model ideal.", priority: .niceToHave),
            PackingSuggestion(name: "Flip flops + water sandals", category: .footwear, reason: "You'll want both — flip flops for walking, water sandals for rocky beaches and reef walks.", priority: .recommended),
            PackingSuggestion(name: "Motion sickness tablets", category: .medications, reason: "Boat transfers and snorkel tours catch many people off guard.", priority: .recommended),
            PackingSuggestion(name: "Insect repellent (DEET-free)", category: .toiletries, reason: "Evening beach areas often have sandflies and mosquitoes. DEET-free is gentler on skin.", priority: .recommended),
        ]
    }

    private func businessMockSuggestions() -> [PackingSuggestion] {
        [
            PackingSuggestion(name: "Portable laptop stand", category: .electronics, reason: "Hotel desks are rarely ergonomic. A foldable stand prevents neck strain on long work days.", priority: .recommended),
            PackingSuggestion(name: "Business cards", category: .documents, reason: "Conferences and networking events still exchange physical cards — don't show up empty-handed.", priority: .essential),
            PackingSuggestion(name: "Noise-cancelling earbuds", category: .electronics, reason: "Conference calls from airports and hotel lobbies are far more bearable with proper isolation.", priority: .recommended),
            PackingSuggestion(name: "Wrinkle-release spray", category: .toiletries, reason: "Packed dress shirts and blazers almost always need a quick refresh before meetings.", priority: .recommended),
            PackingSuggestion(name: "Portable charger (20,000mAh)", category: .electronics, reason: "Long conference days drain phones fast with all-day hotspot use and navigation.", priority: .essential),
            PackingSuggestion(name: "Extra dress socks (3 pairs)", category: .clothing, reason: "Always the item you run out of first on business trips. Pack one more than you think you need.", priority: .recommended),
            PackingSuggestion(name: "Tide-to-Go pen", category: .accessories, reason: "Conference lunches are a wardrobe hazard. A stain pen before a client presentation is invaluable.", priority: .recommended),
            PackingSuggestion(name: "Sleep mask + earplugs", category: .accessories, reason: "Hotel room curtains are rarely sufficient. City noise disrupts sleep before big presentations.", priority: .niceToHave),
            PackingSuggestion(name: "Collapsible water bottle", category: .accessories, reason: "Convention centers rarely have good hydration options. Pack your own.", priority: .niceToHave),
            PackingSuggestion(name: "Melatonin (low dose)", category: .medications, reason: "Crossing time zones before important meetings? Melatonin helps reset your sleep schedule fast.", priority: .recommended),
        ]
    }

    private func mountainMockSuggestions() -> [PackingSuggestion] {
        [
            PackingSuggestion(name: "Trekking poles (collapsible)", category: .sports, reason: "Significantly reduce knee stress on descents. Worth the packing space for any serious hiking.", priority: .recommended),
            PackingSuggestion(name: "Blister prevention balm", category: .toiletries, reason: "Apply before you feel hotspots. By the time you feel a blister forming, it's too late.", priority: .essential),
            PackingSuggestion(name: "Emergency mylar blanket", category: .medications, reason: "Weather in the mountains changes fast. A mylar blanket is 50g and could save your life.", priority: .essential),
            PackingSuggestion(name: "Electrolyte tablets", category: .medications, reason: "Altitude increases dehydration risk dramatically. Water alone won't keep your electrolytes balanced.", priority: .recommended),
            PackingSuggestion(name: "Headlamp (with spare batteries)", category: .sports, reason: "Headlamp lets your hands be free on trail. Don't rely on your phone — it drains fast in the cold.", priority: .essential),
            PackingSuggestion(name: "Gaiters (low profile)", category: .footwear, reason: "Keeps debris and moisture out of boots on off-trail terrain. Game changer on scree.", priority: .recommended),
            PackingSuggestion(name: "Diamox (altitude sickness)", category: .medications, reason: "If heading above 10,000 ft, ask your doctor about Diamox. Altitude sickness ruins trips.", priority: .recommended),
            PackingSuggestion(name: "Ultralight down jacket", category: .clothing, reason: "Compresses to fist-sized, adds 15°F of warmth. Summit temperatures can drop 30°F from trailhead.", priority: .essential),
            PackingSuggestion(name: "Water filtration (Sawyer Squeeze)", category: .sports, reason: "Lightweight water filter means you can refill from streams without carrying 3L all day.", priority: .recommended),
            PackingSuggestion(name: "Bear canister or hang bag", category: .food, reason: "Required in many wilderness areas. Check your park's specific regulations before you go.", priority: .essential),
        ]
    }

    private func skiMockSuggestions() -> [PackingSuggestion] {
        [
            PackingSuggestion(name: "Hand warmers (12-pack)", category: .accessories, reason: "Lifts, gondolas, and chair rides get brutal. Stuffable in any pocket and gloves.", priority: .recommended),
            PackingSuggestion(name: "Ski boot bag", category: .sports, reason: "Protects your boots in transit and keeps the rest of your bag dry and clean.", priority: .recommended),
            PackingSuggestion(name: "Goggle anti-fog spray", category: .sports, reason: "Goggles fog constantly during exertion. Anti-fog treatment lasts the whole trip.", priority: .recommended),
            PackingSuggestion(name: "Lip balm with SPF 30+", category: .toiletries, reason: "Snow reflects 80% of UV rays. Chapped, sunburned lips are the most common ski injury.", priority: .essential),
            PackingSuggestion(name: "Neck gaiter / balaclava", category: .clothing, reason: "At speed in sub-zero wind, exposed skin loses heat fast. A gaiter is lighter than a helmet cover.", priority: .essential),
            PackingSuggestion(name: "Wrist guards (under gloves)", category: .sports, reason: "Wrist fractures are the #1 ski/snowboard injury from falls. Slim guards fit under any glove.", priority: .recommended),
            PackingSuggestion(name: "Resort ski map (paper backup)", category: .documents, reason: "Cell service on mountains is patchy. A paper piste map means you never get lost mid-run.", priority: .recommended),
            PackingSuggestion(name: "Après-ski boots (warm, waterproof)", category: .footwear, reason: "You'll be in ski boots all day. Comfortable, warm boots for the evening are a serious quality-of-life item.", priority: .recommended),
            PackingSuggestion(name: "Ibuprofen (200mg)", category: .medications, reason: "Skiing works muscles you forgot you had. Ibuprofen the evening after day one helps day two significantly.", priority: .recommended),
            PackingSuggestion(name: "GoPro mount for helmet", category: .electronics, reason: "The runs look amazing on video. A helmet mount is the safest and most stable setup.", priority: .niceToHave),
        ]
    }

    private func cityMockSuggestions() -> [PackingSuggestion] {
        [
            PackingSuggestion(name: "Comfortable walking shoes (broken in)", category: .footwear, reason: "City trips involve far more walking than expected. New shoes = blisters by day two.", priority: .essential),
            PackingSuggestion(name: "Packable day bag", category: .accessories, reason: "A foldable tote or small backpack for daily carry keeps your main luggage secure at the hotel.", priority: .recommended),
            PackingSuggestion(name: "Portable door alarm", category: .accessories, reason: "Adds a layer of security in urban hotels and Airbnbs. Compact and under $15.", priority: .niceToHave),
            PackingSuggestion(name: "Offline maps downloaded (Maps.me or Google)", category: .electronics, reason: "City navigation when roaming is off. Download before you fly.", priority: .recommended),
            PackingSuggestion(name: "Transit card (city-specific)", category: .documents, reason: "Many cities have rechargeable transit cards that save time over single-ticket queues.", priority: .recommended),
            PackingSuggestion(name: "Smart casual outfit (1 elevated)", category: .clothing, reason: "City trips often include a nice dinner or show. One elevated outfit covers all eventualities.", priority: .recommended),
            PackingSuggestion(name: "Collapsible umbrella", category: .accessories, reason: "Urban weather is unpredictable. A compact umbrella fits in any day bag.", priority: .recommended),
            PackingSuggestion(name: "Blister bandages (Compeed)", category: .medications, reason: "Walking all day on city streets is brutal. Compeed bandages work far better than regular plasters.", priority: .recommended),
            PackingSuggestion(name: "Restaurant reservation confirmations", category: .documents, reason: "Popular spots in major cities book out weeks ahead. Print or screenshot reservations.", priority: .recommended),
            PackingSuggestion(name: "Laundry bag (small)", category: .accessories, reason: "Keeping worn and clean clothes separate is a tiny detail that makes a big difference on 5+ night trips.", priority: .niceToHave),
        ]
    }

    private func internationalMockSuggestions() -> [PackingSuggestion] {
        [
            PackingSuggestion(name: "Passport (valid 6+ months)", category: .documents, reason: "Many countries require 6 months validity beyond your travel dates. Check now — not at check-in.", priority: .essential),
            PackingSuggestion(name: "Visa + entry documents (printed)", category: .documents, reason: "Some border crossings require physical copies. Don't rely solely on your phone.", priority: .essential),
            PackingSuggestion(name: "Universal power adapter", category: .electronics, reason: "Plug types vary by region. A universal adapter prevents hunting for adaptors on arrival.", priority: .essential),
            PackingSuggestion(name: "Travel insurance documents", category: .documents, reason: "Carry your policy number and 24h emergency contact. Medical emergencies abroad get expensive fast.", priority: .essential),
            PackingSuggestion(name: "Local SIM or eSIM pre-loaded", category: .electronics, reason: "Data roaming is expensive. Buy an eSIM before you land via Airalo or similar service.", priority: .recommended),
            PackingSuggestion(name: "Small bills in local currency", category: .documents, reason: "Airport ATMs have bad rates. Airports, taxis, and street vendors often need exact cash.", priority: .recommended),
            PackingSuggestion(name: "Prescription medications (2x supply)", category: .medications, reason: "International delays happen. Carry double your needed supply and keep half in carry-on.", priority: .essential),
            PackingSuggestion(name: "Doctor's letter for medications", category: .documents, reason: "Controlled substances and some injectables require documentation at customs.", priority: .recommended),
            PackingSuggestion(name: "RFID-blocking wallet", category: .accessories, reason: "RFID skimming is rare but trivial to prevent. Modern slim wallets include blocking as standard.", priority: .niceToHave),
            PackingSuggestion(name: "Stomach medication (Imodium + Pepto)", category: .medications, reason: "Food adjustments when traveling internationally catch almost everyone at some point.", priority: .recommended),
        ]
    }

    private func weekendMockSuggestions() -> [PackingSuggestion] {
        [
            PackingSuggestion(name: "Reusable bag (shopping/beach/farmers market)", category: .accessories, reason: "Weekend getaways often include local markets. A foldable bag weighs nothing and earns constant use.", priority: .niceToHave),
            PackingSuggestion(name: "Power bank (compact)", category: .electronics, reason: "Even a short weekend involves a lot of phone use for navigation and photos.", priority: .recommended),
            PackingSuggestion(name: "One nice outfit", category: .clothing, reason: "Weekend trips often include a dinner out. One elevated option means you never feel underdressed.", priority: .recommended),
            PackingSuggestion(name: "Snacks for the drive", category: .food, reason: "Road-trip snacks are almost always forgotten until you're passing gas stations at $6 a bag.", priority: .niceToHave),
            PackingSuggestion(name: "Offline playlist downloaded", category: .entertainment, reason: "Rural getaways and road trips often have patchy signal. Download your weekend playlist before leaving.", priority: .niceToHave),
            PackingSuggestion(name: "Ibuprofen + antihistamine", category: .medications, reason: "Weekend trips are when you forget your medicine. A mini supply covers both headaches and allergies.", priority: .recommended),
            PackingSuggestion(name: "Phone car mount", category: .electronics, reason: "Navigation while driving requires hands-free. A decent mount costs $10 and prevents accidents.", priority: .recommended),
            PackingSuggestion(name: "Microfiber travel towel", category: .accessories, reason: "B&Bs and Airbnbs don't always have great towel supply. A compact backup gives peace of mind.", priority: .niceToHave),
            PackingSuggestion(name: "Earplugs", category: .accessories, reason: "Unfamiliar environments and thin walls affect sleep. A weekend of bad sleep ruins Monday.", priority: .niceToHave),
            PackingSuggestion(name: "Reusable water bottle", category: .accessories, reason: "Staying hydrated on weekend adventures is easy to forget. Filling up beats buying plastic.", priority: .recommended),
        ]
    }
}

// MARK: - Error Body Decoding (for quota vs rate-limit distinction)

/// Minimal decode of the OpenAI error response body.
/// Used only to distinguish quota-exceeded from rate-limited (both return 429).
private struct OpenAIErrorBody: Codable {
    let error: OpenAIErrorDetail
}

private struct OpenAIErrorDetail: Codable {
    let type: String?
    let message: String?
    let code: String?
}
