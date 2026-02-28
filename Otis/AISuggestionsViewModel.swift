// AISuggestionsViewModel.swift
// Otis — ViewModels/AISuggestionsViewModel.swift
//
// @Observable ViewModel driving the AI suggestions sheet.
// Owns the full lifecycle: idle → loading → success / error.
//
// Responsibilities:
//   - Calls AppleIntelligenceService.generatePackingSuggestions (on-device, no API key needed)
//   - Cycles typewriter loading messages on a 1.8s timer
//   - Manages per-suggestion selection state (multi-select via Set<UUID>)
//   - Exposes dynamic category filter tabs (only categories present in results)
//   - Persists accepted items to SwiftData ModelContext via PackingItemMapper
//   - Gates feature access via SubscriptionManager.shared.canAccess(.aiSuggestions)
//
// Threading:
//   All @Observable mutations happen on MainActor.
//   OpenAIService is an actor — bridged via await.
//   Timer callbacks hop back to MainActor via Task { @MainActor in }.

import Foundation
import SwiftData
import Observation

// MARK: - AISuggestionsViewModel

@Observable
@MainActor
final class AISuggestionsViewModel {

    // MARK: - Nested Types

    /// Full lifecycle state of the suggestion fetch.
    enum LoadingState: Equatable {
        case idle
        case loading
        case success
        case error(AIServiceError)

        static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.success, .success):
                return true
            case (.error(let a), .error(let b)):
                return a.localizedDescription == b.localizedDescription
            default:
                return false
            }
        }
    }

    /// Category-based filter tab. "All" is always first; remaining tabs are
    /// dynamically generated from whatever categories appear in suggestions.
    enum CategoryFilter: Hashable, Identifiable {
        case all
        case category(ItemCategory)

        var id: String {
            switch self {
            case .all:              return "all"
            case .category(let c):  return c.rawValue
            }
        }

        var displayName: String {
            switch self {
            case .all:              return "All"
            case .category(let c):  return c.displayName
            }
        }

        var shortName: String {
            switch self {
            case .all:              return "All"
            case .category(let c):  return c.displayName
            }
        }

        var icon: String {
            switch self {
            case .all:              return "sparkles"
            case .category(let c):  return c.icon
            }
        }
    }

    // MARK: - Observed State

    /// The trip being packed for.
    var trip: Trip

    /// All suggestions returned by the AI (or mock fallback).
    var suggestions: [PackingSuggestion] = []

    /// IDs of suggestions the user has selected (tapped Add).
    var selectedIDs: Set<UUID> = []

    /// Current async state of the fetch.
    var loadingState: LoadingState = .idle

    /// Currently selected category filter tab.
    var selectedFilter: CategoryFilter = .all

    /// Which loading message is currently showing (index into loadingMessages).
    var currentLoadingMessageIndex: Int = 0

    /// Set to true after a successful bulk-add — triggers dismiss + success overlay.
    var didAddItems: Bool = false

    /// Count of items added in the last addSelectedToTrip call — for toast display.
    var lastAddedCount: Int = 0

    // MARK: - Derived State

    /// The unique category filters to show in the tab bar.
    /// "All" first, then one tab per category that appears in suggestions,
    /// sorted by ItemCategory.sortPriority so critical categories lead.
    var availableFilters: [CategoryFilter] {
        let categories = suggestions
            .map(\.category)
            .uniqued()
            .sorted { $0.sortPriority < $1.sortPriority }
        return [.all] + categories.map { .category($0) }
    }

    /// Suggestions visible under the current filter tab.
    var filteredSuggestions: [PackingSuggestion] {
        switch selectedFilter {
        case .all:
            return suggestions
        case .category(let cat):
            return suggestions.filter { $0.category == cat }
        }
    }

    /// Count for a given filter tab — shown as badge.
    func count(for filter: CategoryFilter) -> Int {
        switch filter {
        case .all:              return suggestions.count
        case .category(let c):  return suggestions.filter { $0.category == c }.count
        }
    }

    /// Number of currently selected suggestions.
    var selectedCount: Int { selectedIDs.count }

    /// True when at least one essential suggestion is not yet selected.
    var hasUnselectedEssentials: Bool {
        suggestions.contains { $0.priority == .essential && !selectedIDs.contains($0.id) }
    }

    /// True when the on-device model is unavailable (old device / iOS < 18.1).
    var isNoKeyState: Bool { !AppleIntelligenceService.shared.isAvailable }

    /// True when the user is not Pro and First Trip Free is not active.
    var isProGated: Bool {
        !SubscriptionManager.shared.canAccess(.aiSuggestions)
    }

    // MARK: - Loading Messages

    var loadingMessages: [String] {
        let dest = trip.destination.isEmpty ? "your destination" : trip.destination
        let type = trip.tripType.displayName.lowercased()
        return [
            "Thinking about \(dest)...",
            "Checking the weather in \(dest)...",
            "Packing for \(type)...",
            "Almost ready..."
        ]
    }

    var currentLoadingMessage: String {
        let msgs = loadingMessages
        guard !msgs.isEmpty else { return "Loading..." }
        return msgs[currentLoadingMessageIndex % msgs.count]
    }

    // MARK: - Private

    private var messageTimer: Timer?

    // MARK: - Init

    init(trip: Trip) {
        self.trip = trip
    }

    deinit {
        messageTimer?.invalidate()
    }

    // MARK: - Public API

    /// Kicks off the OpenAI fetch (or mock fallback for no-key state).
    /// Safe to call multiple times — guards against concurrent fetches.
    func loadSuggestions(existingItems: [String] = []) async {
        guard loadingState != .loading else { return }

        loadingState = .loading
        currentLoadingMessageIndex = 0
        selectedIDs = []
        startLoadingMessageCycle()

        do {
            let fetched = try await AppleIntelligenceService.shared.generatePackingSuggestions(
                for: trip,
                existingItemNames: existingItems
            )
            stopLoadingMessageCycle()

            // Sort: priority tier first (essential → recommended → niceToHave),
            // then by category sort priority, then alpha within tier.
            suggestions = fetched.sorted {
                if $0.priority.sortOrder != $1.priority.sortOrder {
                    return $0.priority.sortOrder < $1.priority.sortOrder
                }
                if $0.category.sortPriority != $1.category.sortPriority {
                    return $0.category.sortPriority < $1.category.sortPriority
                }
                return $0.name < $1.name
            }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                loadingState = .success
            }
        } catch let error as AIServiceError {
            stopLoadingMessageCycle()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                loadingState = .error(error)
            }
        } catch {
            stopLoadingMessageCycle()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                loadingState = .error(.unavailable)
            }
        }
    }

    /// Toggles the selected state for a single suggestion (multi-select).
    func toggleSelection(id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }

    /// Selects all suggestions currently visible in the active filter tab.
    func selectAll() {
        let ids = filteredSuggestions.map(\.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedIDs.formUnion(ids)
        }
    }

    /// Deselects all suggestions.
    func deselectAll() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedIDs = []
        }
    }

    /// Inserts all selected suggestions as PackingItems into the ModelContext.
    /// Marks isAISuggested = true on each item.
    /// - Returns: Count of items actually inserted.
    @discardableResult
    func addSelectedToTrip(modelContext: ModelContext) -> Int {
        let selected = suggestions.filter { selectedIDs.contains($0.id) }
        let newItems = PackingItemMapper.toPackingItems(selected, for: trip)
        for item in newItems {
            modelContext.insert(item)
        }
        lastAddedCount = newItems.count
        if newItems.count > 0 {
            didAddItems = true
        }
        return newItems.count
    }

    /// Selects all suggestions then immediately calls addSelectedToTrip.
    @discardableResult
    func addAll(modelContext: ModelContext) -> Int {
        selectAll()
        return addSelectedToTrip(modelContext: modelContext)
    }

    /// Resets back to idle so the user can retry.
    func reset() {
        suggestions = []
        selectedIDs = []
        loadingState = .idle
        selectedFilter = .all
        currentLoadingMessageIndex = 0
        didAddItems = false
        lastAddedCount = 0
        stopLoadingMessageCycle()
    }

    // MARK: - Loading Message Timer

    private func startLoadingMessageCycle() {
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.currentLoadingMessageIndex += 1
                }
            }
        }
    }

    private func stopLoadingMessageCycle() {
        messageTimer?.invalidate()
        messageTimer = nil
    }
}

// MARK: - Mock Suggestions (no-key / Pro gate preview)

extension AISuggestionsViewModel {

    /// Five representative suggestions shown when no API key is configured
    /// or when the Pro gate overlay is active. These are intentionally vague
    /// and not trip-specific — the point is to show the UI shape, not real data.
    static func mockSuggestionsForDisplay() -> [PackingSuggestion] {
        [
            PackingSuggestion(
                name: "Passport",
                category: .documents,
                reason: "Required for international travel — keep it in your carry-on.",
                priority: .essential
            ),
            PackingSuggestion(
                name: "Travel insurance card",
                category: .documents,
                reason: "Quick access to your policy number and emergency contact.",
                priority: .essential
            ),
            PackingSuggestion(
                name: "Universal power adapter",
                category: .electronics,
                reason: "Keeps all your devices charged regardless of socket type.",
                priority: .recommended
            ),
            PackingSuggestion(
                name: "Sunscreen SPF 50",
                category: .toiletries,
                reason: "Protect your skin — especially near the equator.",
                priority: .recommended
            ),
            PackingSuggestion(
                name: "Reusable water bottle",
                category: .other,
                reason: "Stay hydrated and reduce plastic waste at your destination.",
                priority: .niceToHave
            )
        ]
    }
}

// MARK: - Array+Uniqued Helper

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
