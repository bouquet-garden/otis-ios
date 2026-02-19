// PackingListViewModel.swift
// Otis — ViewModels/PackingList/
//
// @Observable ViewModel for TripDetailView. Owns all packing list business
// logic: item CRUD, grouping/sorting, Otis state transitions, trip completion.
//
// Threading: All mutations run on MainActor (SwiftData requirement).
// Haptics: Fired directly here so callers don't need UIKit imports.

import SwiftUI
import SwiftData

// MARK: - PackingListViewModel

@Observable
@MainActor
final class PackingListViewModel {

    // MARK: - Public State

    /// The trip this ViewModel manages. Observed directly for SwiftData reactivity.
    var trip: Trip

    /// Tracks which category sections are manually collapsed by the user.
    var collapsedCategories: Set<ItemCategory> = []

    /// Whether the "Mark Trip Complete" confirmation alert is showing.
    var showCompleteConfirmation: Bool = false

    /// Which category section is currently showing its inline add-item field.
    var addingItemInCategory: ItemCategory? = nil

    /// The in-progress text for the inline add field.
    var newItemName: String = ""

    /// Controls the "Otis Suggests" sheet presentation.
    var showAISuggestionsSheet: Bool = false

    /// Drives Otis header celebration pulse.
    var otisJumped: Bool = false

    // MARK: - Private

    private let subscriptionManager: SubscriptionManager
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    // MARK: - Init

    init(trip: Trip, subscriptionManager: SubscriptionManager) {
        self.trip = trip
        self.subscriptionManager = subscriptionManager
        impactLight.prepare()
        impactMedium.prepare()
        notificationGenerator.prepare()
    }

    // MARK: - Derived State

    /// Otis mascot state derived from packing progress.
    var otisState: OtisState {
        let pct = trip.packingPercentage
        if pct == 0 { return .calm }
        if pct == 1.0 { return .celebration }
        return .active
    }

    /// Items grouped by category, categories ordered by sortPriority.
    /// Within each category: unpacked items first (by sortOrder), then packed.
    var groupedItems: [(category: ItemCategory, items: [PackingItem])] {
        let grouped = Dictionary(grouping: trip.items) { $0.category }
        return ItemCategory.allCases
            .compactMap { category -> (ItemCategory, [PackingItem])? in
                guard let raw = grouped[category], !raw.isEmpty else { return nil }
                let unpacked = raw.filter { !$0.isPacked }.sorted { $0.sortOrder < $1.sortOrder }
                let packed   = raw.filter {  $0.isPacked }.sorted { $0.sortOrder < $1.sortOrder }
                return (category, unpacked + packed)
            }
            .sorted { $0.0.sortPriority < $1.0.sortPriority }
    }

    /// Categories present in this trip's items (for add-item category picker).
    var activeCategories: [ItemCategory] {
        groupedItems.map(\.category)
    }

    var packedCount: Int  { trip.packedItemCount }
    var totalCount: Int   { trip.totalItemCount }
    var isFullyPacked: Bool { trip.isFullyPacked }

    /// "Mark Trip Complete" button only appears when everything is packed and
    /// the trip hasn't already been marked complete.
    var showCompleteButton: Bool {
        isFullyPacked && !trip.isCompleted
    }

    /// Otis Suggests banner: visible for Pro users who have no AI-suggested
    /// items on this trip yet (suggestions haven't been fetched).
    var showOtisSuggestsBanner: Bool {
        guard subscriptionManager.canAccess(.aiSuggestions) else { return false }
        return !trip.items.contains { $0.isAISuggested }
    }

    /// Whether the trip list is empty (no items at all).
    var isEmpty: Bool { trip.items.isEmpty }

    /// Progress ratio as 0.0–1.0, safe for the ring component.
    var packingProgress: Double { trip.packingPercentage }

    /// Countdown string for the header. Returns "Today!" on departure day.
    var countdownText: String {
        if trip.isDepartingToday { return "Today!" }
        let days = Calendar.current.dateComponents(
            [.day], from: .now, to: trip.departureDate
        ).day ?? 0
        if days < 0 { return "In progress" }
        if days == 1 { return "1 day away" }
        return "\(days) days away"
    }

    /// True when departure is today (drives coral highlight).
    var isDepartureToday: Bool { trip.isDepartingToday }

    // MARK: - Item CRUD

    /// Toggle packed state. Fires light haptic; success haptic + Otis jump if
    /// this check completes the entire list.
    func toggleItem(_ item: PackingItem) {
        let wasFullyPacked = isFullyPacked

        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            item.isPacked.toggle()
        }

        if item.isPacked {
            if isFullyPacked && !wasFullyPacked {
                // Final item — big celebration feedback
                notificationGenerator.notificationOccurred(.success)
                triggerOtisJump()
            } else {
                impactLight.impactOccurred()
            }
        } else {
            impactLight.impactOccurred()
        }
    }

    /// Add a new item to the specified category. Validates name, assigns sortOrder,
    /// inserts into SwiftData context.
    func addItem(
        name: String,
        category: ItemCategory,
        modelContext: ModelContext
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Next sortOrder = max existing + 1 within this category.
        let existing = trip.items.filter { $0.category == category }
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1

        let item = PackingItem(
            name: trimmed,
            category: category,
            isPacked: false,
            isAISuggested: false,
            sortOrder: nextOrder,
            trip: trip
        )

        modelContext.insert(item)
        trip.items.append(item)

        impactLight.impactOccurred(intensity: 0.6)

        // Reset inline add state
        newItemName = ""
        addingItemInCategory = nil
    }

    /// Delete a single item. Removes from SwiftData context.
    func deleteItem(_ item: PackingItem, modelContext: ModelContext) {
        if let idx = trip.items.firstIndex(where: { $0.id == item.id }) {
            trip.items.remove(at: idx)
        }
        modelContext.delete(item)
        impactMedium.impactOccurred()
    }

    /// Delete items at given offsets within a specific category's items array.
    func deleteItems(
        at offsets: IndexSet,
        in categoryItems: [PackingItem],
        modelContext: ModelContext
    ) {
        for idx in offsets {
            deleteItem(categoryItems[idx], modelContext: modelContext)
        }
    }

    /// Rename an item in-place. No new SwiftData insert needed.
    func renameItem(_ item: PackingItem, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.name = trimmed
    }

    /// Move an item to a different category.
    func moveItem(_ item: PackingItem, to newCategory: ItemCategory) {
        item.category = newCategory
        impactLight.impactOccurred(intensity: 0.4)
    }

    /// Reorder items within a category using .onMove offset sets.
    func moveItems(
        from source: IndexSet,
        to destination: Int,
        in categoryItems: [PackingItem]
    ) {
        var reordered = categoryItems
        reordered.move(fromOffsets: source, toOffset: destination)
        for (idx, item) in reordered.enumerated() {
            item.sortOrder = idx
        }
        impactLight.impactOccurred(intensity: 0.4)
    }

    // MARK: - Category Collapse

    func toggleCollapse(_ category: ItemCategory) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if collapsedCategories.contains(category) {
                collapsedCategories.remove(category)
            } else {
                collapsedCategories.insert(category)
            }
        }
        impactLight.impactOccurred(intensity: 0.3)
    }

    func isCollapsed(_ category: ItemCategory) -> Bool {
        collapsedCategories.contains(category)
    }

    // MARK: - Inline Add Field

    /// Open the inline add field for a specific category.
    func beginAddingItem(in category: ItemCategory) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            addingItemInCategory = category
            newItemName = ""
        }
    }

    /// Cancel inline add without saving.
    func cancelAddingItem() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            addingItemInCategory = nil
            newItemName = ""
        }
    }

    /// Commit the inline add field (called on Return key or "Add" button tap).
    func commitAddItem(modelContext: ModelContext) {
        guard let category = addingItemInCategory else { return }
        addItem(name: newItemName, category: category, modelContext: modelContext)
    }

    // MARK: - Trip Completion

    /// Mark the trip as complete. Triggers stamp unlock flow via notification.
    /// Called after the user taps "Mark Trip Complete — Get Your Stamp".
    func completeTrip(modelContext: ModelContext) {
        guard isFullyPacked, !trip.isCompleted else { return }

        notificationGenerator.notificationOccurred(.success)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            trip.isCompleted = true
            trip.completedAt = Date()
        }

        subscriptionManager.recordTripCompletion()

        // Post notification — StampService listens and creates the stamp.
        NotificationCenter.default.post(
            name: .tripDidComplete,
            object: trip
        )
    }

    // MARK: - Otis Animation

    private func triggerOtisJump() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
            otisJumped = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                self?.otisJumped = false
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let tripDidComplete = Notification.Name("OtrisTripDidComplete")
}
