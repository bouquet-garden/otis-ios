// AISuggestionsViewModel.swift
// Otis — ViewModels/AISuggestionsViewModel.swift
//
// Observable ViewModel driving the AI suggestions sheet.
// Owns the full lifecycle: idle → loading → success/error.
// Handles filter selection, individual toggles, bulk accept,
// and final insertion into the SwiftData ModelContext.
//
// Threading:
//   - loadSuggestions() is async; OpenAIService is an actor so
//     all OpenAI calls are already actor-isolated.
//   - UI state is mutated on the MainActor via @MainActor annotations.
//   - The message-cycling Timer is invalidated on success/error to
//     prevent retain cycles.
//
// Usage (from TripDetailView):
//   @State private var showAI = false
//   .sheet(isPresented: $showAI) {
//       AISuggestionsView(trip: trip)
//   }

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
        case error(OpenAIError)

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

    /// Tabs in the suggestion filter control.
    enum SuggestionFilter: String, CaseIterable, Identifiable {
        case all
        case essential
        case recommended
        case niceToHave

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all:         return "All"
            case .essential:   return "Essential"
            case .recommended: return "Recommended"
            case .niceToHave:  return "Nice to Have"
            }
        }

        var shortName: String {
            switch self {
            case .all:         return "All"
            case .essential:   return "Essential"
            case .recommended: return "Recommended"
            case .niceToHave:  return "Nice"
            }
        }

        /// The corresponding SuggestionPriority, or nil for .all.
        var priority: SuggestionPriority? {
            switch self {
            case .all:         return nil
            case .essential:   return .essential
            case .recommended: return .recommended
            case .niceToHave:  return .niceToHave
            }
        }
    }

    // MARK: - Observed State

    /// The trip being packed for.
    var trip: Trip

    /// All suggestions returned by the AI (or mock fallback).
    var suggestions: [PackingSuggestion] = []

    /// Current async state of the fetch.
    var loadingState: LoadingState = .idle

    /// Currently selected tab filter.
    var selectedFilter: SuggestionFilter = .all

    /// Which message index is currently showing in the typewriter loader.
    var currentLoadingMessageIndex: Int = 0

    /// Set to true after a successful add — triggers dismiss + success haptic in the View.
    var didAddItems: Bool = false

    /// Number of items added in the last addSelectedToTrip call — for toast display.
    var lastAddedCount: Int = 0

    // MARK: - Derived State

    /// Count of accepted (selected) suggestions.
    var selectedCount: Int {
        suggestions.filter(\.isAccepted).count
    }

    /// Suggestions filtered by the current tab selection.
    var filteredSuggestions: [PackingSuggestion] {
        guard let priority = selectedFilter.priority else {
            return suggestions
        }
        return suggestions.filter { $0.priority == priority }
    }

    /// True if there is at least one .essential suggestion not yet accepted.
    var hasUnacceptedEssentials: Bool {
        suggestions.contains { $0.priority == .essential && !$0.isAccepted }
    }

    /// True when no OpenAI key is configured (will show mock suggestions + prompt).
    var isNoKeyState: Bool {
        AppConfig.openAIAPIKey.isEmpty
    }

    /// Count per filter tab — drives badge labels.
    func count(for filter: SuggestionFilter) -> Int {
        guard let priority = filter.priority else { return suggestions.count }
        return suggestions.filter { $0.priority == priority }.count
    }

    // MARK: - Loading Messages

    /// Typewriter messages that cycle during the loading state.
    var loadingMessages: [String] {
        let dest = trip.destination.isEmpty ? "your destination" : trip.destination
        return [
            "Otis is thinking about \(dest)...",
            "Checking the weather in \(dest)...",
            "Remembering what frequent travelers pack...",
            "Almost ready..."
        ]
    }

    var currentLoadingMessage: String {
        let messages = loadingMessages
        guard !messages.isEmpty else { return "Loading..." }
        return messages[currentLoadingMessageIndex % messages.count]
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

    /// Triggers the OpenAI call (or mock fallback). Updates loadingState throughout.
    func loadSuggestions(existingItems: [String] = []) async {
        guard loadingState != .loading else { return }

        loadingState = .loading
        currentLoadingMessageIndex = 0
        startLoadingMessageCycle()

        do {
            let fetched = try await OpenAIService.shared.generatePackingSuggestions(
                for: trip,
                existingItemNames: existingItems
            )
            stopLoadingMessageCycle()
            // Sort: essential first, then recommended, then niceToHave; alpha within tier
            suggestions = fetched.sorted {
                if $0.priority.sortOrder != $1.priority.sortOrder {
                    return $0.priority.sortOrder < $1.priority.sortOrder
                }
                return $0.name < $1.name
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                loadingState = .success
            }
        } catch let error as OpenAIError {
            stopLoadingMessageCycle()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                loadingState = .error(error)
            }
        } catch {
            stopLoadingMessageCycle()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                loadingState = .error(.networkError(error))
            }
        }
    }

    /// Toggles the isAccepted state of a single suggestion.
    func toggleSuggestion(_ suggestion: PackingSuggestion) {
        guard let idx = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        suggestions[idx].isAccepted.toggle()
    }

    /// Marks all .essential suggestions as accepted.
    func acceptAllEssentials() {
        for idx in suggestions.indices where suggestions[idx].priority == .essential {
            suggestions[idx].isAccepted = true
        }
    }

    /// Inserts all accepted suggestions as PackingItems into the ModelContext.
    /// - Returns: Count of items actually inserted (duplicates excluded by mapper).
    @discardableResult
    func addSelectedToTrip(modelContext: ModelContext) -> Int {
        let accepted = suggestions.filter(\.isAccepted)
        let newItems = PackingItemMapper.toPackingItems(accepted, for: trip)
        for item in newItems {
            modelContext.insert(item)
        }
        lastAddedCount = newItems.count
        didAddItems = true
        return newItems.count
    }

    /// Inserts ALL essential suggestions regardless of isAccepted state.
    /// Convenience for "Add All Essentials" action.
    @discardableResult
    func addAllEssentials(modelContext: ModelContext) -> Int {
        // First accept them all so the UI reflects selection
        acceptAllEssentials()
        let essentials = suggestions.filter { $0.priority == .essential }
        let newItems = PackingItemMapper.toPackingItems(essentials, for: trip)
        for item in newItems {
            modelContext.insert(item)
        }
        lastAddedCount = newItems.count
        didAddItems = true
        return newItems.count
    }

    /// Resets back to idle so the user can retry.
    func reset() {
        suggestions = []
        loadingState = .idle
        selectedFilter = .all
        currentLoadingMessageIndex = 0
        didAddItems = false
        lastAddedCount = 0
    }

    // MARK: - Loading Message Cycle

    /// Starts a repeating 1.5s timer that steps through loadingMessages.
    /// Must be called on MainActor (already satisfied by @MainActor class).
    func startLoadingMessageCycle() {
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
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

// MARK: - Mock Suggestions for No-Key State

extension AISuggestionsViewModel {

    /// Returns 5 generic suggestions shown when no API key is set,
    /// so the UI is never blank and users understand what to expect.
    static func mockSuggestionsForDisplay() -> [PackingSuggestion] {
        [
            PackingSuggestion(
                name: "Universal power adapter",
                category: .electronics,
                reason: "Keeps all your devices charged regardless of socket type.",
                priority: .essential
            ),
            PackingSuggestion(
                name: "Passport",
                category: .documents,
                reason: "Required for international travel — keep it in your carry-on.",
                priority: .essential
            ),
            PackingSuggestion(
                name: "Sunscreen SPF 50",
                category: .toiletries,
                reason: "Protect your skin, especially near the equator.",
                priority: .recommended
            ),
            PackingSuggestion(
                name: "Reusable water bottle",
                category: .essentials,
                reason: "Stay hydrated and reduce plastic waste at your destination.",
                priority: .recommended
            ),
            PackingSuggestion(
                name: "Portable first-aid kit",
                category: .health,
                reason: "Minor ailments shouldn't derail your adventure.",
                priority: .niceToHave
            )
        ]
    }
}
