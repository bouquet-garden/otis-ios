// PackingItemMapper.swift
// Otis — Services/PackingItemMapper.swift
//
// Converts [PackingSuggestion] → [PackingItem] for insertion into SwiftData.
// This is the bridge between the AI layer and the persistence layer.
//
// Responsibilities:
//   - Map each accepted PackingSuggestion to a fully initialized PackingItem
//   - Set isAISuggested = true so the UI can render the sparkle badge
//   - Assign sortOrder starting after the last existing item (no collisions)
//   - Filter out suggestions whose names duplicate existing items (case-insensitive)
//   - Optionally convert all suggestions OR only accepted ones
//
// Usage (in PackingListViewModel):
//   let newItems = PackingItemMapper.toPackingItems(
//       suggestions.filter(\.isAccepted),
//       for: trip
//   )
//   for item in newItems { modelContext.insert(item) }

import Foundation

// MARK: - PackingItemMapper

struct PackingItemMapper {

    // MARK: - Primary Conversion

    /// Converts an array of PackingSuggestion into PackingItem instances
    /// ready for SwiftData insertion.
    ///
    /// - Parameters:
    ///   - suggestions: The suggestions to convert. Pass only accepted
    ///     suggestions (`suggestions.filter(\.isAccepted)`) for the standard
    ///     "add selected items" flow, or pass all suggestions if bulk-accepting.
    ///   - trip: The trip the items will belong to. Used to:
    ///       1. Assign the `trip` relationship on each PackingItem.
    ///       2. Determine the starting sortOrder (appended after existing items).
    ///       3. Filter out names that duplicate items already on the trip.
    /// - Returns: An array of new PackingItem instances, not yet inserted into
    ///   any ModelContext. The caller is responsible for insertion.
    static func toPackingItems(
        _ suggestions: [PackingSuggestion],
        for trip: Trip
    ) -> [PackingItem] {

        // Build a lowercase set of existing item names for O(1) duplicate checks
        let existingNames = Set(
            trip.items.map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        )

        // Starting sortOrder: place AI items after all current items
        let baseOrder = (trip.items.map(\.sortOrder).max() ?? -1) + 1

        var results: [PackingItem] = []
        var orderOffset = 0

        for suggestion in suggestions {
            let trimmedName = suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty names (defensive guard — should never happen post-parse)
            guard !trimmedName.isEmpty else { continue }

            // Skip duplicates (case-insensitive)
            let lowerName = trimmedName.lowercased()
            guard !existingNames.contains(lowerName) else {
                continue
            }

            let item = PackingItem(
                id: UUID(),
                name: trimmedName,
                category: suggestion.category,
                isPacked: false,
                isAISuggested: true,
                packedAt: nil,
                sortOrder: baseOrder + orderOffset,
                trip: trip
            )

            results.append(item)
            orderOffset += 1
        }

        return results
    }

    // MARK: - Bulk Accept Conversion

    /// Convenience method: converts ALL suggestions regardless of isAccepted state.
    /// Use this for "Add All" functionality in the suggestion UI.
    ///
    /// - Parameters:
    ///   - suggestions: All suggestions from the AI response.
    ///   - trip: The owning trip.
    /// - Returns: New PackingItem instances for all suggestions not already on the list.
    static func toPackingItemsAcceptingAll(
        _ suggestions: [PackingSuggestion],
        for trip: Trip
    ) -> [PackingItem] {
        toPackingItems(suggestions, for: trip)
    }

    // MARK: - Priority-Filtered Conversion

    /// Converts only suggestions matching the given priority tier.
    /// Useful for "Add Essentials Only" quick-action in the suggestion UI.
    ///
    /// - Parameters:
    ///   - suggestions: Full list of suggestions from the AI response.
    ///   - priority: The priority tier to filter to (e.g. `.essential`).
    ///   - trip: The owning trip.
    /// - Returns: New PackingItem instances for matching, non-duplicate suggestions.
    static func toPackingItems(
        _ suggestions: [PackingSuggestion],
        withPriority priority: SuggestionPriority,
        for trip: Trip
    ) -> [PackingItem] {
        let filtered = suggestions.filter { $0.priority == priority }
        return toPackingItems(filtered, for: trip)
    }

    // MARK: - Reverse: PackingItem Names for Duplicate Prevention

    /// Extracts item names from a trip's existing list for injection into
    /// the AI prompt. Call this before generating suggestions so the model
    /// knows what not to suggest.
    ///
    /// - Parameter trip: The trip whose items to extract.
    /// - Returns: Sorted array of item name strings.
    static func existingItemNames(for trip: Trip) -> [String] {
        trip.items
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    // MARK: - Suggestion Grouping Helpers

    /// Groups suggestions by priority tier for the suggestion card UI.
    /// Returns a dictionary keyed by SuggestionPriority, ordered for display.
    ///
    /// - Parameter suggestions: The full suggestions array from the AI.
    /// - Returns: Dictionary of priority → suggestions, with each group sorted
    ///   alphabetically by name within the tier.
    static func groupedByPriority(
        _ suggestions: [PackingSuggestion]
    ) -> [(priority: SuggestionPriority, suggestions: [PackingSuggestion])] {
        let grouped = Dictionary(grouping: suggestions) { $0.priority }
        return SuggestionPriority.allCases.compactMap { priority in
            guard let items = grouped[priority], !items.isEmpty else { return nil }
            let sorted = items.sorted { $0.name < $1.name }
            return (priority, sorted)
        }
    }

    /// Groups suggestions by ItemCategory for an alternative UI layout
    /// (e.g. category-tabs in the suggestion sheet).
    ///
    /// - Parameter suggestions: The full suggestions array from the AI.
    /// - Returns: Array of (category, suggestions) tuples sorted by
    ///   ItemCategory.sortPriority, matching the main list's ordering.
    static func groupedByCategory(
        _ suggestions: [PackingSuggestion]
    ) -> [(category: ItemCategory, suggestions: [PackingSuggestion])] {
        let grouped = Dictionary(grouping: suggestions) { $0.category }
        return ItemCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            let sorted = items.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
            return (category, sorted)
        }.sorted { $0.category.sortPriority < $1.category.sortPriority }
    }

    // MARK: - Stats

    /// Returns a summary count struct for display in the suggestion UI header.
    static func suggestionStats(_ suggestions: [PackingSuggestion]) -> SuggestionStats {
        SuggestionStats(
            total: suggestions.count,
            essential: suggestions.filter { $0.priority == .essential }.count,
            recommended: suggestions.filter { $0.priority == .recommended }.count,
            niceToHave: suggestions.filter { $0.priority == .niceToHave }.count,
            accepted: suggestions.filter { $0.isAccepted }.count
        )
    }
}

// MARK: - SuggestionStats

/// A lightweight value type used to populate the suggestion card's header
/// (e.g. "18 suggestions — 4 essential, 10 recommended, 4 nice-to-have").
struct SuggestionStats: Equatable {
    let total: Int
    let essential: Int
    let recommended: Int
    let niceToHave: Int
    let accepted: Int

    var headerString: String {
        "\(total) suggestion\(total == 1 ? "" : "s")"
    }

    var breakdownString: String {
        var parts: [String] = []
        if essential > 0 { parts.append("\(essential) essential") }
        if recommended > 0 { parts.append("\(recommended) recommended") }
        if niceToHave > 0 { parts.append("\(niceToHave) nice-to-have") }
        return parts.joined(separator: " · ")
    }

    var acceptedString: String {
        accepted == 0
            ? "None selected"
            : "\(accepted) selected"
    }
}
