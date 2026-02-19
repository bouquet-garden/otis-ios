// TripDetailView.swift
// Otis — Views/PackingList/
//
// Primary daily-use screen. Users spend 80% of their time here.
// Architecture: NavigationStack child view, receives a Trip from TripListView.
//
// Sections:
//   1. Header — trip name, destination, countdown, progress ring, Otis mascot
//   2. "Otis Suggests" banner (Pro only, first-time fetch)
//   3. Packing list — grouped by ItemCategory, collapsible sections
//   4. Inline add-item field per section
//   5. FAB "+" for quick add with category picker
//   6. "Mark Trip Complete" slide-up CTA (100% only)
//
// Dependencies:
//   - PackingListViewModel (@Observable, created here)
//   - SubscriptionManager (@EnvironmentObject)
//   - ModelContext from SwiftData environment
//   - PackingProgressRing, CategorySectionHeader, PackingItemRow (sibling files)

import SwiftUI
import SwiftData

// MARK: - TripDetailView

struct TripDetailView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - ViewModel

    @State private var vm: PackingListViewModel

    // MARK: - Local UI State

    /// FAB category picker sheet.
    @State private var showCategoryPicker: Bool = false
    /// Sheet: AI suggestions (P1-D).
    @State private var showAISuggestions: Bool = false
    /// Drives the complete-button slide-up.
    @State private var completeButtonVisible: Bool = false
    /// Edit mode for reordering.
    @State private var editMode: EditMode = .inactive
    /// Scroll position for keyboard avoidance.
    @State private var scrollProxy: ScrollViewProxy? = nil
    /// Tracks when to focus the inline add field.
    @FocusState private var addFieldFocused: Bool

    // MARK: - Init

    init(trip: Trip, subscriptionManager: SubscriptionManager) {
        _vm = State(initialValue: PackingListViewModel(
            trip: trip,
            subscriptionManager: subscriptionManager
        ))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Color.otisCreame.ignoresSafeArea()

            // Main scroll content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // ── 1. Hero Header ──
                        headerSection
                            .id("top")

                        // ── 2. Otis Suggests Banner ──
                        if vm.showOtisSuggestsBanner {
                            otisSuggestsBanner
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        // ── 3. Empty state ──
                        if vm.isEmpty {
                            emptyState
                                .padding(.top, 40)
                        } else {
                            // ── 4. Grouped Packing List ──
                            packingListSections
                        }

                        // Bottom padding so CTA button doesn't obscure last row
                        Spacer().frame(height: vm.showCompleteButton ? 100 : 32)
                    }
                }
                .onAppear { scrollProxy = proxy }
                .scrollDismissesKeyboard(.interactively)
            }

            // ── 5. Floating Action Button ──
            fabButton

            // ── 6. Complete Trip CTA ──
            if vm.showCompleteButton {
                completeTripButton
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                    .padding(.bottom, 16)
                    .padding(.horizontal, 16)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: vm.showCompleteButton)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet { category in
                vm.beginAddingItem(in: category)
                showCategoryPicker = false
            }
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
        // AI Suggestions sheet (wired to P1-D: AISuggestionsView)
        .sheet(isPresented: $showAISuggestions) {
            // Placeholder — replaced by AISuggestionsView in P1-D
            AISuggestionsPlaceholderView(trip: vm.trip)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Mark \"\(vm.trip.name)\" as complete?",
            isPresented: $vm.showCompleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Complete Trip — Get My Stamp", role: .none) {
                vm.completeTrip(modelContext: modelContext)
            }
            Button("Not Yet", role: .cancel) {}
        } message: {
            Text("You'll earn a passport stamp for this adventure.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            // Main header content
            VStack(alignment: .leading, spacing: 0) {
                // Top row: title + progress ring
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Trip name
                        Text(vm.trip.name)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.otisSlate)
                            .lineLimit(2)

                        // Destination
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.otisTeal)
                            Text(vm.trip.destination)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.otisSlateLight)
                        }

                        // Countdown
                        Text(vm.countdownText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(vm.isDepartureToday ? .otisCoral : .otisSlateLight)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    vm.isDepartureToday
                                        ? Color.otisCoral.opacity(0.12)
                                        : Color.otisSlate.opacity(0.07)
                                )
                            )
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.isDepartureToday)
                    }

                    Spacer()

                    // Progress ring (right side)
                    VStack(spacing: 6) {
                        PackingProgressRing(
                            progress: vm.packingProgress,
                            size: 64,
                            lineWidth: 5.5
                        )

                        Text("\(vm.packedCount) of \(vm.totalCount)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.otisSlateLight)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .background(Color.otisCreame)

            // Otis mascot — top-right, state-reactive
            OtisMascotView(state: vm.otisState, jumped: vm.otisJumped)
                .frame(width: 56, height: 56)
                .offset(x: -16, y: 8)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Otis Suggests Banner

    private var otisSuggestsBanner: some View {
        Button {
            showAISuggestions = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.otisTeal.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.otisTeal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Otis has packing ideas")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.otisSlate)
                    Text("Tap to get AI suggestions for \(vm.trip.destination)")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.otisSlateLight)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.otisTeal.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.otisTeal.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.otisTeal.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get packing suggestions from Otis for \(vm.trip.destination)")
    }

    // MARK: - Packing List Sections

    private var packingListSections: some View {
        LazyVStack(spacing: 0, pinnedViews: []) {
            ForEach(vm.groupedItems, id: \.category) { group in
                let category = group.category
                let items = group.items
                let packedInSection = items.filter(\.isPacked).count

                // Section header
                CategorySectionHeader(
                    category: category,
                    totalCount: items.count,
                    packedCount: packedInSection,
                    isCollapsed: vm.isCollapsed(category),
                    onTap: { vm.toggleCollapse(category) }
                )
                .background(Color.otisCreame)
                .id("header-\(category.rawValue)")

                // Section items (hidden when collapsed)
                if !vm.isCollapsed(category) {
                    ForEach(items) { item in
                        PackingItemRow(
                            item: item,
                            onToggle: { vm.toggleItem(item) },
                            onDelete: { vm.deleteItem(item, modelContext: modelContext) },
                            onRename: { vm.renameItem(item, newName: $0) },
                            onMoveCategory: { vm.moveItem(item, to: $0) }
                        )
                        .id(item.id)

                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                    .onDelete { offsets in
                        vm.deleteItems(at: offsets, in: items, modelContext: modelContext)
                    }
                    .onMove { source, dest in
                        vm.moveItems(from: source, to: dest, in: items)
                    }

                    // Inline add-item row
                    inlineAddRow(for: category)
                }

                // Section divider
                Divider()
                    .padding(.bottom, 4)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Inline Add Row

    @ViewBuilder
    private func inlineAddRow(for category: ItemCategory) -> some View {
        if vm.addingItemInCategory == category {
            // Expanded text field
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.otisTeal)

                TextField("Item name", text: $vm.newItemName)
                    .font(.system(size: 16, design: .rounded))
                    .focused($addFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        vm.commitAddItem(modelContext: modelContext)
                    }

                // Cancel button
                Button {
                    vm.cancelAddingItem()
                    addFieldFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.otisSlateLight.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.otisTeal.opacity(0.05))
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear { addFieldFocused = true }

        } else {
            // Collapsed "Add item" tap row
            Button {
                vm.beginAddingItem(in: category)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.otisTeal.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.otisTeal.opacity(0.08)))

                    Text("Add item")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.otisSlateLight)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add item to \(category.displayName)")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            // Otis illustration placeholder (asset: otis_empty_state)
            ZStack {
                Circle()
                    .fill(Color.otisTeal.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "bag.badge.plus")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.otisTeal)
            }

            VStack(spacing: 8) {
                Text("Ready to pack!")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.otisSlate)

                Text("Add your first item, or let Otis\nsuggest a list for \(vm.trip.destination).")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
            }

            // Quick-add CTA
            Button {
                showCategoryPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add First Item")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color.otisTeal))
            }
            .buttonStyle(.plain)

            if subscriptionManager.canAccess(.aiSuggestions) {
                Button {
                    showAISuggestions = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Let Otis Suggest Items")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.otisTeal)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - FAB Button

    private var fabButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    // If there are categories, show picker; else show category picker directly
                    showCategoryPicker = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.otisTeal)
                            .frame(width: 54, height: 54)
                            .shadow(color: Color.otisTeal.opacity(0.35), radius: 12, x: 0, y: 6)

                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add packing item")
                .padding(.trailing, 20)
                .padding(.bottom, vm.showCompleteButton ? 96 : 20)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.showCompleteButton)
            }
        }
    }

    // MARK: - Complete Trip Button

    private var completeTripButton: some View {
        Button {
            vm.showCompleteConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Mark Trip Complete \u{2014} Get Your Stamp")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.otisTeal)
                    .shadow(color: Color.otisTeal.opacity(0.4), radius: 16, x: 0, y: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mark trip complete and earn your passport stamp")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            EditButton()
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.otisTeal)
        }
    }
}

// MARK: - Otis Mascot View

/// Renders the Otis otter mascot. State drives which asset/expression is shown.
/// In the real build, replace SF Symbol with asset catalog images per OtisState.
private struct OtisMascotView: View {

    let state: OtisState
    let jumped: Bool

    private var systemImage: String {
        switch state {
        case .calm:        return "otter"          // Replace with asset: otis_calm
        case .active:      return "otter"          // Replace with asset: otis_active
        case .celebration: return "star.circle.fill" // Replace with asset: otis_celebration
        case .thinking:    return "ellipsis.bubble"
        case .suggesting:  return "sparkles"
        }
    }

    private var tint: Color {
        switch state {
        case .calm:        return .otisTeal
        case .active:      return .otisTeal
        case .celebration: return .otisCoral
        case .thinking:    return .otisSlateLight
        case .suggesting:  return .otisTeal
        }
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 30))
            .foregroundStyle(tint)
            .offset(y: jumped ? -10 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: jumped)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state)
            .accessibilityHidden(true)
    }
}

// MARK: - Category Picker Sheet

private struct CategoryPickerSheet: View {
    let onSelect: (ItemCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    // Sorted by sortPriority for a logical order
    private var categories: [ItemCategory] {
        ItemCategory.allCases.sorted { $0.sortPriority < $1.sortPriority }
    }

    var body: some View {
        NavigationStack {
            List(categories) { category in
                Button {
                    onSelect(category)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.otisTeal.opacity(0.1))
                                .frame(width: 34, height: 34)
                            Image(systemName: category.icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.otisTeal)
                        }
                        Text(category.displayName)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(.otisSlate)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.otisSlateLight.opacity(0.5))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Choose Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.otisTeal)
                }
            }
        }
        .background(Color.otisCreame)
    }
}

// MARK: - AI Suggestions Placeholder

/// Temporary placeholder — replaced by the full AISuggestionsView in P1-D.
private struct AISuggestionsPlaceholderView: View {
    let trip: Trip

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.otisTeal)

                Text("Otis is thinking...")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.otisSlate)

                Text("AI Suggestions for \(trip.destination) coming in P1-D.")
                    .font(.system(size: 15))
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Otis Suggests")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Preview

#Preview("Trip Detail") {
    // Build a sample trip for preview
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Trip.self, PackingItem.self,
        configurations: config
    )
    let ctx = container.mainContext

    let trip = Trip(
        name: "Cabo with Sarah",
        destination: "Cabo San Lucas, Mexico",
        tripType: .beach,
        departureDate: Calendar.current.date(byAdding: .day, value: 3, to: .now)!
    )
    ctx.insert(trip)

    let items: [(String, ItemCategory, Bool, Bool)] = [
        ("Passport",        .documents,  false, false),
        ("Travel insurance",.documents,  true,  false),
        ("Sunscreen SPF 50",.toiletries, false, true),
        ("After-sun lotion",.toiletries, false, true),
        ("Swimsuit x2",     .clothing,   true,  false),
        ("Linen shirt",     .clothing,   false, false),
        ("AirPods",         .electronics,false, true),
        ("Power bank",      .electronics,false, false),
    ]
    for (idx, (name, cat, packed, ai)) in items.enumerated() {
        let item = PackingItem(
            name: name, category: cat, isPacked: packed,
            isAISuggested: ai, sortOrder: idx, trip: trip
        )
        ctx.insert(item)
        trip.items.append(item)
    }

    let subManager = SubscriptionManager()

    return NavigationStack {
        TripDetailView(trip: trip, subscriptionManager: subManager)
            .navigationBarBackButtonHidden(false)
    }
    .modelContainer(container)
    .environmentObject(subManager)
}
