// SupabaseService.swift
// Otis Travel App
//
// Complete network/data layer — Supabase Swift SDK.
// Singleton accessed via SupabaseService.shared.
//
// Architecture notes:
//   - @Observable for SwiftUI binding (iOS 17+)
//   - All queries are RLS-scoped: Supabase client passes the session
//     JWT automatically; auth.uid() filtering is enforced server-side.
//   - Trips are resolved via user_profiles.id (the PK), not auth.uid()
//     directly, because trips.user_id → user_profiles.id (not auth.users.id).
//     Every mutating trips/items/stamps call resolves profileID first and
//     caches it in `cachedProfileID`.
//   - Supabase URL + anon key are read from Info.plist (xcconfig-injected).
//     Fall back to compile-time literals so the Simulator build works even
//     without xcconfig wired up yet.
//
// Tables used (see code/otis-schema.sql):
//   user_profiles, trips, packing_items, stamps,
//   packing_profiles, template_items
//
// Views used:
//   trip_summaries, passport_stamps

import Foundation
import Supabase
import Combine

// ---------------------------------------------------------------------------
// MARK: - OtisError
// ---------------------------------------------------------------------------

/// Typed errors surfaced to SwiftUI views via `.otisMessage`.
enum OtisError: LocalizedError {
    case notAuthenticated
    case profileNotFound
    case tripNotFound
    case itemNotFound
    case duplicateStamp
    case networkError(String)
    case decodingError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You need to be signed in. Please sign in and try again."
        case .profileNotFound:
            return "Could not find your Otis profile. Try signing out and back in."
        case .tripNotFound:
            return "That trip no longer exists."
        case .itemNotFound:
            return "That packing item no longer exists."
        case .duplicateStamp:
            return "You already earned that stamp — nice try!"
        case .networkError(let msg):
            return "Connection problem: \(msg)"
        case .decodingError(let msg):
            return "Data error: \(msg)"
        case .unknown(let msg):
            return "Something went wrong: \(msg)"
        }
    }

    /// Short string safe for analytics/logging (no PII).
    var analyticsKey: String {
        switch self {
        case .notAuthenticated:    return "not_authenticated"
        case .profileNotFound:     return "profile_not_found"
        case .tripNotFound:        return "trip_not_found"
        case .itemNotFound:        return "item_not_found"
        case .duplicateStamp:      return "duplicate_stamp"
        case .networkError:        return "network_error"
        case .decodingError:       return "decoding_error"
        case .unknown:             return "unknown"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Row models (Codable, mirror schema exactly)
// ---------------------------------------------------------------------------
// Naming: snake_case properties match Supabase column names so the default
// JSONDecoder (no key-decoding strategy needed — Supabase SDK handles it)
// works out of the box.

/// Maps to public.user_profiles
struct UserProfileRow: Codable, Identifiable {
    let id: UUID
    let authUserId: UUID?
    var subscriptionStatus: String          // subscription_status enum raw value
    var isFirstTripComplete: Bool
    var totalTripsCompleted: Int
    var isFirstTripFreeActive: Bool
    var proTrialUsed: Bool
    var revenuecatCustomerId: String?
    var displayName: String?
    let createdAt: Date
    var lastOpenedAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId              = "auth_user_id"
        case subscriptionStatus      = "subscription_status"
        case isFirstTripComplete     = "is_first_trip_complete"
        case totalTripsCompleted     = "total_trips_completed"
        case isFirstTripFreeActive   = "is_first_trip_free_active"
        case proTrialUsed            = "pro_trial_used"
        case revenuecatCustomerId    = "revenuecat_customer_id"
        case displayName             = "display_name"
        case createdAt               = "created_at"
        case lastOpenedAt            = "last_opened_at"
        case updatedAt               = "updated_at"
    }
}

/// Maps to public.trips (and the trip_summaries view extras)
struct TripRow: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var name: String
    var destination: String
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var tripType: String                    // trip_type enum raw value
    var departureDate: String               // ISO date "YYYY-MM-DD"
    var returnDate: String?
    var isCompleted: Bool
    var completedAt: Date?
    var isFirstTrip: Bool
    let createdAt: Date
    var updatedAt: Date

    // trip_summaries view extras (nil when querying trips table directly)
    var totalItems: Int?
    var packedItems: Int?
    var packingPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case userId              = "user_id"
        case name
        case destination
        case destinationLatitude = "destination_latitude"
        case destinationLongitude = "destination_longitude"
        case tripType            = "trip_type"
        case departureDate       = "departure_date"
        case returnDate          = "return_date"
        case isCompleted         = "is_completed"
        case completedAt         = "completed_at"
        case isFirstTrip         = "is_first_trip"
        case createdAt           = "created_at"
        case updatedAt           = "updated_at"
        case totalItems          = "total_items"
        case packedItems         = "packed_items"
        case packingPercentage   = "packing_percentage"
    }
}

/// Maps to public.packing_items
struct PackingItemRow: Codable, Identifiable {
    let id: UUID
    let tripId: UUID
    let userId: UUID
    var name: String
    var category: String                    // item_category enum raw value
    var isPacked: Bool
    var isAiSuggested: Bool
    var packedAt: Date?
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case tripId          = "trip_id"
        case userId          = "user_id"
        case name
        case category
        case isPacked        = "is_packed"
        case isAiSuggested   = "is_ai_suggested"
        case packedAt        = "packed_at"
        case sortOrder       = "sort_order"
        case createdAt       = "created_at"
        case updatedAt       = "updated_at"
    }
}

/// Maps to public.stamps (and passport_stamps view extras)
struct StampRow: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var tripId: UUID?
    var tripNumber: Int
    var stampType: String                   // stamp_type enum raw value
    var destination: String
    var destinationType: String             // trip_type enum raw value
    var season: String                      // season enum raw value
    var earnedAt: Date
    var isMilestone: Bool
    var milestoneNumber: Int?
    let createdAt: Date

    // passport_stamps view extra
    var tripName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId          = "user_id"
        case tripId          = "trip_id"
        case tripNumber      = "trip_number"
        case stampType       = "stamp_type"
        case destination
        case destinationType = "destination_type"
        case season
        case earnedAt        = "earned_at"
        case isMilestone     = "is_milestone"
        case milestoneNumber = "milestone_number"
        case createdAt       = "created_at"
        case tripName        = "trip_name"
    }
}

/// Maps to public.packing_profiles
struct PackingProfileRow: Codable, Identifiable {
    let id: UUID
    var userId: UUID?                       // nil = system default profile
    var name: String
    var tripType: String                    // trip_type enum raw value
    var icon: String                        // SF Symbol name
    var isDefault: Bool
    var usageCount: Int
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId      = "user_id"
        case name
        case tripType    = "trip_type"
        case icon
        case isDefault   = "is_default"
        case usageCount  = "usage_count"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}

/// Maps to public.template_items
struct TemplateItemRow: Codable, Identifiable {
    let id: UUID
    let profileId: UUID
    var name: String
    var category: String                    // item_category enum raw value
    var sortOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case profileId   = "profile_id"
        case name
        case category
        case sortOrder   = "sort_order"
        case createdAt   = "created_at"
    }
}

// ---------------------------------------------------------------------------
// MARK: - Input DTOs (what callers pass in)
// ---------------------------------------------------------------------------

struct NewTripInput {
    let name: String
    let destination: String
    let destinationLatitude: Double?
    let destinationLongitude: Double?
    let tripType: String                    // trip_type raw value
    let departureDate: String               // "YYYY-MM-DD"
    let returnDate: String?
}

struct NewPackingItemInput {
    let name: String
    let category: String                    // item_category raw value
    let isAiSuggested: Bool
    let sortOrder: Int
}

struct UpdateTripInput {
    var name: String?
    var destination: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var tripType: String?
    var departureDate: String?
    var returnDate: String?
}

// Milestone trip counts that earn milestone stamps
private let milestoneNumbers: Set<Int> = [1, 5, 10, 25, 50]

// ---------------------------------------------------------------------------
// MARK: - SupabaseService
// ---------------------------------------------------------------------------

/// Singleton data/network layer. Access via `SupabaseService.shared`.
///
/// Usage in a SwiftUI view:
/// ```swift
/// @Environment(SupabaseService.self) var supabase
/// ```
/// Register at app entry point:
/// ```swift
/// ContentView().environment(SupabaseService.shared)
/// ```
@Observable
@MainActor
final class SupabaseService {

    // MARK: Singleton

    static let shared = SupabaseService()

    // MARK: Public observable state

    /// The currently authenticated Supabase user (nil = signed out / anonymous).
    private(set) var currentUser: User?

    /// True while any async operation is in flight.
    private(set) var isLoading: Bool = false

    /// Last error surfaced to UI. Cleared at the start of each operation.
    private(set) var lastError: OtisError?

    // MARK: Private

    /// Underlying Supabase client.
    private let client: SupabaseClient

    /// Cached user_profiles.id for the current session to avoid repeated lookups.
    /// Invalidated on sign-out.
    private var cachedProfileID: UUID?

    // MARK: Init

    private init() {
        // Read from Info.plist (xcconfig-injected). Fall back to literals so
        // Simulator builds work before xcconfig is wired.
        let url = Self.resolveURL()
        let anonKey = Self.resolveAnonKey()

        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey
        )

        // Restore persisted session if one exists (Supabase SDK handles keychain)
        Task {
            await self.restoreSession()
        }
    }

    // MARK: - Config resolution

    private static func resolveURL() -> URL {
        if let raw = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        // Compile-time fallback (xcconfig not yet wired for this target)
        return URL(string: "https://zjskchgdlaspvzuwghaf.supabase.co")!
    }

    private static func resolveAnonKey() -> String {
        if let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        // Compile-time fallback — publishable key is safe in source for
        // development; production uses xcconfig injection.
        return "sb_publishable_YpMc_zdcPE3jRsuBzwjgDQ_5IpMA_v7"
    }
}

// ---------------------------------------------------------------------------
// MARK: - Session Restoration
// ---------------------------------------------------------------------------

extension SupabaseService {

    /// Restores a persisted Supabase session on app launch.
    private func restoreSession() async {
        do {
            let session = try await client.auth.session
            currentUser = session.user
            cachedProfileID = nil // will be resolved lazily on first use
        } catch {
            // No persisted session — that is fine, user is signed out.
            currentUser = nil
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Auth
// ---------------------------------------------------------------------------

extension SupabaseService {

    // MARK: Auth state stream

    /// AsyncStream of auth state changes. Observe in a `.task` modifier.
    ///
    /// ```swift
    /// .task {
    ///     for await (event, session) in supabase.authStateStream {
    ///         // react to sign-in / sign-out
    ///     }
    /// }
    /// ```
    var authStateStream: AsyncStream<(AuthChangeEvent, Session?)> {
        AsyncStream { continuation in
            let handle = client.auth.onAuthStateChange { event, session in
                continuation.yield((event, session))
            }
            continuation.onTermination = { _ in
                handle.remove()
            }
        }
    }

    // MARK: Sign in with Apple

    /// Completes Sign in with Apple using an identity token returned by
    /// `ASAuthorizationAppleIDCredential`.
    ///
    /// - Parameter identityToken: JWT string from `credential.identityToken`.
    @discardableResult
    func signInWithApple(identityToken: String) async throws -> User {
        clearError()
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: identityToken
                )
            )
            currentUser = session.user
            cachedProfileID = nil
            try await upsertUserProfile(for: session.user)
            return session.user
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Sign in anonymously

    /// Creates an anonymous Supabase session. Used for first-launch
    /// "try before you sign up" flow.
    @discardableResult
    func signInAnonymously() async throws -> User {
        clearError()
        do {
            let session = try await client.auth.signInAnonymously()
            currentUser = session.user
            cachedProfileID = nil
            try await upsertUserProfile(for: session.user)
            return session.user
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Sign out

    func signOut() async throws {
        clearError()
        do {
            try await client.auth.signOut()
            currentUser = nil
            cachedProfileID = nil
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Current session user (synchronous convenience)

    /// Returns the current user without hitting the network.
    /// Returns nil if no active session.
    func requireUser() throws -> User {
        guard let user = currentUser else {
            throw OtisError.notAuthenticated
        }
        return user
    }
}

// ---------------------------------------------------------------------------
// MARK: - User Profile
// ---------------------------------------------------------------------------

extension SupabaseService {

    // MARK: Fetch

    func fetchUserProfile() async throws -> UserProfileRow {
        clearError()
        let user = try requireUser()
        do {
            let row: UserProfileRow = try await client
                .from("user_profiles")
                .select()
                .eq("auth_user_id", value: user.id.uuidString)
                .single()
                .execute()
                .value
            cachedProfileID = row.id
            return row
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Update subscription tier

    func updateSubscriptionTier(_ tier: String) async throws {
        clearError()
        let profileID = try await resolveProfileID()
        do {
            try await client
                .from("user_profiles")
                .update(["subscription_status": tier])
                .eq("id", value: profileID.uuidString)
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Update display name

    func updateDisplayName(_ name: String) async throws {
        clearError()
        let profileID = try await resolveProfileID()
        do {
            try await client
                .from("user_profiles")
                .update(["display_name": name])
                .eq("id", value: profileID.uuidString)
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Touch last_opened_at

    func touchLastOpened() async {
        guard let profileID = cachedProfileID else { return }
        try? await client
            .from("user_profiles")
            .update(["last_opened_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: profileID.uuidString)
            .execute()
    }

    // MARK: Upsert on first auth

    /// Creates or updates the user_profiles row after authentication.
    /// Safe to call on every sign-in (upsert on auth_user_id conflict).
    private func upsertUserProfile(for user: User) async throws {
        let payload: [String: AnyJSON] = [
            "auth_user_id": .string(user.id.uuidString),
            "last_opened_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        do {
            let row: UserProfileRow = try await client
                .from("user_profiles")
                .upsert(payload, onConflict: "auth_user_id")
                .select()
                .single()
                .execute()
                .value
            cachedProfileID = row.id
        } catch {
            // Non-fatal: profile may already exist; log and continue.
            print("Otis [SupabaseService]: upsertUserProfile error — \(error)")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Trips CRUD
// ---------------------------------------------------------------------------

extension SupabaseService {

    // MARK: Fetch all trips (from trip_summaries view)

    /// Returns all trips for the current user, sorted by departure date desc.
    /// Uses the `trip_summaries` view so packing progress is included.
    func fetchTrips() async throws -> [TripRow] {
        clearError()
        let profileID = try await resolveProfileID()
        do {
            let rows: [TripRow] = try await client
                .from("trip_summaries")
                .select()
                .eq("user_id", value: profileID.uuidString)
                .order("departure_date", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Fetch single trip

    func fetchTrip(id: UUID) async throws -> TripRow {
        clearError()
        do {
            let row: TripRow = try await client
                .from("trip_summaries")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value
            return row
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Create trip

    /// Creates a new trip and returns the inserted row.
    /// Automatically marks `is_first_trip` if this is the user's first trip.
    @discardableResult
    func createTrip(_ input: NewTripInput) async throws -> TripRow {
        clearError()
        let profileID = try await resolveProfileID()

        // Determine if this is the first trip
        let existingCount = try await tripsCount(profileID: profileID)
        let isFirstTrip = existingCount == 0

        var payload: [String: AnyJSON] = [
            "user_id":       .string(profileID.uuidString),
            "name":          .string(input.name),
            "destination":   .string(input.destination),
            "trip_type":     .string(input.tripType),
            "departure_date":.string(input.departureDate),
            "is_first_trip": .bool(isFirstTrip)
        ]
        if let lat = input.destinationLatitude  { payload["destination_latitude"]  = .double(lat) }
        if let lng = input.destinationLongitude { payload["destination_longitude"] = .double(lng) }
        if let ret = input.returnDate           { payload["return_date"] = .string(ret) }

        do {
            let row: TripRow = try await client
                .from("trips")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Update trip

    func updateTrip(id: UUID, input: UpdateTripInput) async throws -> TripRow {
        clearError()
        var payload: [String: AnyJSON] = [:]
        if let v = input.name               { payload["name"]                  = .string(v) }
        if let v = input.destination        { payload["destination"]            = .string(v) }
        if let v = input.tripType           { payload["trip_type"]              = .string(v) }
        if let v = input.departureDate      { payload["departure_date"]         = .string(v) }
        if let v = input.returnDate         { payload["return_date"]            = .string(v) }
        if let v = input.destinationLatitude  { payload["destination_latitude"]  = .double(v) }
        if let v = input.destinationLongitude { payload["destination_longitude"] = .double(v) }

        guard !payload.isEmpty else {
            return try await fetchTrip(id: id)
        }

        do {
            let row: TripRow = try await client
                .from("trips")
                .update(payload)
                .eq("id", value: id.uuidString)
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Delete trip

    func deleteTrip(id: UUID) async throws {
        clearError()
        do {
            try await client
                .from("trips")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Mark trip complete

    /// Marks a trip complete, awards a destination stamp, and updates
    /// `user_profiles.total_trips_completed`. Returns the awarded stamp.
    @discardableResult
    func markTripComplete(tripId: UUID) async throws -> StampRow {
        clearError()
        let profileID = try await resolveProfileID()

        // Fetch the trip for stamp metadata
        let trip = try await fetchTrip(id: tripId)

        // 1. Update trip
        let now = ISO8601DateFormatter().string(from: Date())
        let tripUpdate: [String: AnyJSON] = [
            "is_completed": .bool(true),
            "completed_at": .string(now)
        ]
        try await client
            .from("trips")
            .update(tripUpdate)
            .eq("id", value: tripId.uuidString)
            .execute()

        // 2. Increment profile counter
        // Hoist the async fetch before building the payload — Swift does not
        // allow try/await expressions inside enum-case argument position.
        let currentCount = try await currentTripsCompleted(profileID: profileID)
        let profileUpdate: [String: AnyJSON] = [
            "total_trips_completed": .integer(currentCount + 1)
        ]
        let updatedProfile: UserProfileRow = try await client
            .from("user_profiles")
            .update(profileUpdate)
            .eq("id", value: profileID.uuidString)
            .select()
            .single()
            .execute()
            .value

        // 3. Award stamp (also handles milestone detection)
        let stamp = try await awardStamp(
            stampType: trip.tripType,
            destination: trip.destination,
            destinationType: trip.tripType,
            tripId: tripId,
            tripNumber: updatedProfile.totalTripsCompleted
        )

        return stamp
    }

    // MARK: Private helpers

    private func tripsCount(profileID: UUID) async throws -> Int {
        struct CountResponse: Decodable {
            let count: Int
        }
        // Use .count on the query instead of fetching all rows
        let response = try await client
            .from("trips")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: profileID.uuidString)
            .execute()
        return response.count ?? 0
    }

    private func currentTripsCompleted(profileID: UUID) async throws -> Int {
        struct Partial: Decodable {
            let totalTripsCompleted: Int
            enum CodingKeys: String, CodingKey {
                case totalTripsCompleted = "total_trips_completed"
            }
        }
        let row: Partial = try await client
            .from("user_profiles")
            .select("total_trips_completed")
            .eq("id", value: profileID.uuidString)
            .single()
            .execute()
            .value
        return row.totalTripsCompleted
    }
}

// ---------------------------------------------------------------------------
// MARK: - Packing Items CRUD
// ---------------------------------------------------------------------------

extension SupabaseService {

    // MARK: Fetch items for a trip

    func fetchItems(tripId: UUID) async throws -> [PackingItemRow] {
        clearError()
        do {
            let rows: [PackingItemRow] = try await client
                .from("packing_items")
                .select()
                .eq("trip_id", value: tripId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Add single item

    @discardableResult
    func addItem(_ input: NewPackingItemInput, tripId: UUID) async throws -> PackingItemRow {
        clearError()
        let profileID = try await resolveProfileID()
        let payload: [String: AnyJSON] = [
            "trip_id":        .string(tripId.uuidString),
            "user_id":        .string(profileID.uuidString),
            "name":           .string(input.name),
            "category":       .string(input.category),
            "is_ai_suggested":.bool(input.isAiSuggested),
            "sort_order":     .integer(input.sortOrder)
        ]
        do {
            let row: PackingItemRow = try await client
                .from("packing_items")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Bulk add items (from AI suggestions or template)

    /// Inserts multiple items in a single Supabase call. Returns inserted rows.
    @discardableResult
    func bulkAddItems(_ inputs: [NewPackingItemInput], tripId: UUID) async throws -> [PackingItemRow] {
        guard !inputs.isEmpty else { return [] }
        clearError()
        let profileID = try await resolveProfileID()

        let payloads: [[String: AnyJSON]] = inputs.map { input in
            [
                "trip_id":        .string(tripId.uuidString),
                "user_id":        .string(profileID.uuidString),
                "name":           .string(input.name),
                "category":       .string(input.category),
                "is_ai_suggested":.bool(input.isAiSuggested),
                "sort_order":     .integer(input.sortOrder)
            ]
        }
        do {
            let rows: [PackingItemRow] = try await client
                .from("packing_items")
                .insert(payloads)
                .select()
                .execute()
                .value
            return rows
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Toggle packed state

    /// Flips `is_packed` for an item and records or clears `packed_at`.
    @discardableResult
    func toggleItem(id: UUID) async throws -> PackingItemRow {
        clearError()
        // Fetch current state
        do {
            let current: PackingItemRow = try await client
                .from("packing_items")
                .select()
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value

            let nowString = ISO8601DateFormatter().string(from: Date())
            let newPacked = !current.isPacked

            var update: [String: AnyJSON] = [
                "is_packed": .bool(newPacked)
            ]
            update["packed_at"] = newPacked ? .string(nowString) : .null

            let updated: PackingItemRow = try await client
                .from("packing_items")
                .update(update)
                .eq("id", value: id.uuidString)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Rename item

    @discardableResult
    func renameItem(id: UUID, name: String) async throws -> PackingItemRow {
        clearError()
        do {
            let row: PackingItemRow = try await client
                .from("packing_items")
                .update(["name": AnyJSON.string(name)])
                .eq("id", value: id.uuidString)
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Delete item

    func deleteItem(id: UUID) async throws {
        clearError()
        do {
            try await client
                .from("packing_items")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Reorder items

    /// Updates sort_order for a batch of items. Pass the full ordered list.
    func reorderItems(_ orderedIDs: [UUID]) async throws {
        clearError()
        // Perform individual updates concurrently via task group.
        // Each update dict is explicitly typed so the compiler can infer
        // the AnyJSON enum cases from dot-shorthand.
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, itemID) in orderedIDs.enumerated() {
                    let update: [String: AnyJSON] = ["sort_order": .integer(index)]
                    group.addTask {
                        try await self.client
                            .from("packing_items")
                            .update(update)
                            .eq("id", value: itemID.uuidString)
                            .execute()
                    }
                }
                try await group.waitForAll()
            }
        } catch {
            throw mapError(error)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Stamps
// ---------------------------------------------------------------------------

extension SupabaseService {

    // MARK: Fetch all stamps (passport view)

    /// Returns all stamps for the current user, sorted by earned_at asc.
    /// Uses the `passport_stamps` view which includes `trip_name`.
    func fetchStamps() async throws -> [StampRow] {
        clearError()
        let profileID = try await resolveProfileID()
        do {
            let rows: [StampRow] = try await client
                .from("passport_stamps")
                .select()
                .eq("user_id", value: profileID.uuidString)
                .order("earned_at", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Award stamp

    /// Awards a stamp for the completed trip. Automatically detects if this
    /// is a milestone stamp (1st, 5th, 10th, 25th, 50th trip).
    ///
    /// Called internally by `markTripComplete()`. Can also be called directly
    /// for manual stamp awards (e.g., onboarding demo).
    @discardableResult
    func awardStamp(
        stampType: String,
        destination: String,
        destinationType: String,
        tripId: UUID?,
        tripNumber: Int
    ) async throws -> StampRow {
        clearError()
        let profileID = try await resolveProfileID()

        let isMilestone = milestoneNumbers.contains(tripNumber)
        let resolvedStampType: String
        if tripNumber == 1 {
            resolvedStampType = "firstTrip"
        } else if isMilestone {
            resolvedStampType = "milestone"
        } else {
            resolvedStampType = stampType
        }

        let season = currentSeason()

        var payload: [String: AnyJSON] = [
            "user_id":          .string(profileID.uuidString),
            "trip_number":      .integer(tripNumber),
            "stamp_type":       .string(resolvedStampType),
            "destination":      .string(destination),
            "destination_type": .string(destinationType),
            "season":           .string(season),
            "is_milestone":     .bool(isMilestone),
            "earned_at":        .string(ISO8601DateFormatter().string(from: Date()))
        ]
        if let tid = tripId {
            payload["trip_id"] = .string(tid.uuidString)
        }
        if isMilestone {
            payload["milestone_number"] = .integer(tripNumber)
        }

        do {
            let row: StampRow = try await client
                .from("stamps")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Private helpers

    private func currentSeason() -> String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3...5:  return "spring"
        case 6...8:  return "summer"
        case 9...11: return "autumn"
        default:     return "winter"
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Packing Profiles
// ---------------------------------------------------------------------------

extension SupabaseService {

    // MARK: Fetch profiles (system defaults + user's own)

    /// Returns system default profiles and the user's own custom profiles,
    /// sorted by usage_count desc.
    func fetchProfiles() async throws -> [PackingProfileRow] {
        clearError()
        let profileID = try await resolveProfileID()
        do {
            // The RLS policy on packing_profiles handles visibility:
            //   is_default = true OR user_id = current user's profile
            // We filter here client-side for user_id match + is_default.
            let rows: [PackingProfileRow] = try await client
                .from("packing_profiles")
                .select()
                .or("is_default.eq.true,user_id.eq.\(profileID.uuidString)")
                .order("usage_count", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Create custom profile

    @discardableResult
    func createProfile(name: String, tripType: String, icon: String) async throws -> PackingProfileRow {
        clearError()
        let profileID = try await resolveProfileID()
        let payload: [String: AnyJSON] = [
            "user_id":  .string(profileID.uuidString),
            "name":     .string(name),
            "trip_type":.string(tripType),
            "icon":     .string(icon),
            "is_default":.bool(false)
        ]
        do {
            let row: PackingProfileRow = try await client
                .from("packing_profiles")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Delete custom profile

    /// Deletes a user-created packing profile. System defaults (is_default=true)
    /// cannot be deleted.
    func deleteProfile(id: UUID) async throws {
        clearError()
        let profileID = try await resolveProfileID()
        do {
            try await client
                .from("packing_profiles")
                .delete()
                .eq("id", value: id.uuidString)
                .eq("user_id", value: profileID.uuidString)   // guard: only own profiles
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Fetch template items for a profile

    func fetchTemplateItems(profileId: UUID) async throws -> [TemplateItemRow] {
        clearError()
        do {
            let rows: [TemplateItemRow] = try await client
                .from("template_items")
                .select()
                .eq("profile_id", value: profileId.uuidString)
                .order("sort_order", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw mapError(error)
        }
    }

    // MARK: Increment usage count

    /// Call when a user applies a profile to a new trip.
    func incrementProfileUsage(id: UUID) async {
        // Best-effort, non-throwing
        do {
            // Fetch current count then increment
            struct Partial: Decodable {
                let usageCount: Int
                enum CodingKeys: String, CodingKey {
                    case usageCount = "usage_count"
                }
            }
            let current: Partial = try await client
                .from("packing_profiles")
                .select("usage_count")
                .eq("id", value: id.uuidString)
                .single()
                .execute()
                .value

            let usageUpdate: [String: AnyJSON] = [
                "usage_count": .integer(current.usageCount + 1)
            ]
            try await client
                .from("packing_profiles")
                .update(usageUpdate)
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            print("Otis [SupabaseService]: incrementProfileUsage non-fatal error — \(error)")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Profile ID Resolution
// ---------------------------------------------------------------------------

extension SupabaseService {

    /// Resolves the `user_profiles.id` (UUID PK) for the current auth user.
    /// Result is cached for the session lifetime to avoid repeated DB round-trips.
    /// Throws `OtisError.notAuthenticated` if no session and
    /// `OtisError.profileNotFound` if no matching row exists.
    func resolveProfileID() async throws -> UUID {
        if let cached = cachedProfileID {
            return cached
        }

        let user = try requireUser()

        struct Partial: Decodable {
            let id: UUID
        }
        do {
            let row: Partial = try await client
                .from("user_profiles")
                .select("id")
                .eq("auth_user_id", value: user.id.uuidString)
                .single()
                .execute()
                .value
            cachedProfileID = row.id
            return row.id
        } catch {
            // Profile may not exist yet — try upserting then resolve again
            try await upsertUserProfile(for: user)
            if let cached = cachedProfileID {
                return cached
            }
            throw OtisError.profileNotFound
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Error Mapping
// ---------------------------------------------------------------------------

extension SupabaseService {

    private func clearError() {
        lastError = nil
    }

    /// Maps raw Supabase/URLSession/Decoding errors to OtisError.
    private func mapError(_ error: Error) -> OtisError {
        let otisError: OtisError

        if let otis = error as? OtisError {
            otisError = otis
        } else if let postgrest = error as? PostgrestError {
            // PGRST116 = "JSON object requested, multiple (or no) rows returned"
            // Typically means .single() found no row
            if postgrest.code == "PGRST116" {
                otisError = .profileNotFound
            } else {
                otisError = .networkError(postgrest.message)
            }
        } else if let authError = error as? AuthError {
            // AuthError.sessionNotFound is the canonical "no active session" case
            // in Supabase Swift SDK v2. Use localizedDescription pattern matching
            // as a safe fallback for any SDK version variations.
            let desc = authError.localizedDescription.lowercased()
            if desc.contains("session") || desc.contains("not authenticated") || desc.contains("no user") {
                otisError = .notAuthenticated
            } else {
                otisError = .networkError(authError.localizedDescription)
            }
        } else {
            let desc = error.localizedDescription
            if desc.contains("decode") || desc.contains("Decod") {
                otisError = .decodingError(desc)
            } else if desc.contains("network") || desc.contains("connection") || desc.contains("offline") {
                otisError = .networkError(desc)
            } else {
                otisError = .unknown(desc)
            }
        }

        lastError = otisError
        print("Otis [SupabaseService]: \(otisError.analyticsKey) — \(otisError.errorDescription ?? "")")
        return otisError
    }
}

// ---------------------------------------------------------------------------
// MARK: - Loading State Helpers
// ---------------------------------------------------------------------------

extension SupabaseService {

    /// Wraps an async throwing operation, automatically managing `isLoading`
    /// and surfacing errors to `lastError`. Returns `nil` on failure.
    ///
    /// Usage in a ViewModel:
    /// ```swift
    /// let trips = await SupabaseService.shared.perform { try await $0.fetchTrips() }
    /// ```
    func perform<T>(_ operation: (SupabaseService) async throws -> T) async -> T? {
        isLoading = true
        defer { isLoading = false }
        do {
            return try await operation(self)
        } catch let otis as OtisError {
            lastError = otis
            return nil
        } catch {
            lastError = mapError(error)
            return nil
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Realtime (optional subscription helpers)
// ---------------------------------------------------------------------------

extension SupabaseService {

    /// Returns an AsyncStream of packing item changes for a given trip.
    /// Useful for multi-device sync — subscribe in a `.task` modifier.
    ///
    /// ```swift
    /// .task {
    ///     for await change in supabase.packingItemChanges(tripId: trip.id) {
    ///         await viewModel.handleRealtimeChange(change)
    ///     }
    /// }
    /// ```
    ///
    /// - Note: Uses the Supabase Swift SDK realtime channel API.
    ///   Separate `onPostgresChange` listeners are registered for each
    ///   action type (INSERT, UPDATE, DELETE) since the SDK does not expose
    ///   a combined `AnyAction` stream.
    func packingItemChanges(tripId: UUID) -> AsyncStream<RealtimeChangeEvent<PackingItemRow>> {
        AsyncStream { continuation in
            let channel = client.channel("packing_items:\(tripId.uuidString)")
            let filter = "trip_id=eq.\(tripId.uuidString)"

            // INSERT
            let inserts = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "packing_items",
                filter: filter
            )
            // UPDATE
            let updates = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "packing_items",
                filter: filter
            )
            // DELETE
            let deletes = channel.postgresChange(
                DeleteAction.self,
                schema: "public",
                table: "packing_items",
                filter: filter
            )

            // JSONDecoder configured to match Supabase's ISO8601 + fractional
            // seconds format used in all timestamp columns.
            // NOTE: keyDecodingStrategy is left as .useDefaultKeys because all
            // row models declare explicit CodingKeys with snake_case strings —
            // applying .convertFromSnakeCase on top would double-convert them.
            let decoder: JSONDecoder = {
                let d = JSONDecoder()
                d.keyDecodingStrategy = .useDefaultKeys
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                d.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let str = try container.decode(String.self)
                    if let date = formatter.date(from: str) { return date }
                    // Fallback: without fractional seconds
                    let f2 = ISO8601DateFormatter()
                    f2.formatOptions = [.withInternetDateTime]
                    if let date = f2.date(from: str) { return date }
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Cannot decode date string: \(str)"
                    )
                }
                return d
            }()

            Task {
                await channel.subscribe()
                // Fan out to three concurrent consumers
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await action in inserts {
                            if let row = try? action.decodeRecord(as: PackingItemRow.self,
                                                                  decoder: decoder) {
                                continuation.yield(.inserted(row))
                            }
                        }
                    }
                    group.addTask {
                        for await action in updates {
                            if let row = try? action.decodeRecord(as: PackingItemRow.self,
                                                                  decoder: decoder) {
                                continuation.yield(.updated(row))
                            }
                        }
                    }
                    group.addTask {
                        for await action in deletes {
                            if let row = try? action.decodeRecord(as: PackingItemRow.self,
                                                                  decoder: decoder) {
                                continuation.yield(.deleted(row))
                            }
                        }
                    }
                }
            }

            continuation.onTermination = { _ in
                Task { await channel.unsubscribe() }
            }
        }
    }
}

/// Typed realtime change event.
enum RealtimeChangeEvent<T> {
    case inserted(T)
    case updated(T)
    case deleted(T)
}

// ---------------------------------------------------------------------------
// MARK: - AnyJSON usage note
// ---------------------------------------------------------------------------
// The Supabase Swift SDK's AnyJSON is an enum with cases:
//   .string(String), .bool(Bool), .integer(Int), .double(Double), .null
// All payload dictionaries in this file use Swift dot-shorthand inference
// (e.g. ["key": .string("value")]) — no extension needed.
