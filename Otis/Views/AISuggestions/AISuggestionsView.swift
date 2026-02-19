// AISuggestionsView.swift
// Otis — Views/AISuggestions/AISuggestionsView.swift
//
// Full-screen sheet presenting AI packing suggestions for a trip.
// This is the moment users experience Otis's intelligence — every
// transition, animation, and micro-interaction is crafted to feel
// magical rather than transactional.
//
// State machine:
//   .idle     — never shown (loading starts immediately on appear)
//   .loading  — Otis bouncing + typewriter message cycle
//   .success  — filter tabs + staggered card list + sticky action bar
//   .error    — Otis napping + error message + retry / manual fallback
//
// No-key state: shows 5 mock suggestions + Settings prompt overlay.
//
// iOS 26: action bar uses .glassEffect(.regular, in: .rect)
// iOS 17+: action bar uses .ultraThinMaterial background
//
// Usage:
//   .sheet(isPresented: $showAISuggestions) {
//       AISuggestionsView(trip: trip, existingItemNames: existingNames)
//           .onSuggestionsAdded { count in ... }
//   }

import SwiftUI
import SwiftData

// MARK: - AISuggestionsView

struct AISuggestionsView: View {

    // MARK: - Parameters

    let trip: Trip
    /// Names already on the packing list — passed to the AI to prevent duplicates.
    var existingItemNames: [String] = []
    /// Called when items are successfully added; passes the count.
    var onSuggestionsAdded: ((Int) -> Void)? = nil

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - ViewModel

    @State private var viewModel: AISuggestionsViewModel

    // MARK: - Local State

    /// Controls card stagger animation trigger.
    @State private var cardsAppeared: Bool = false
    /// Controls the dismiss-after-add flow.
    @State private var showSuccessOverlay: Bool = false

    // MARK: - Init

    init(
        trip: Trip,
        existingItemNames: [String] = [],
        onSuggestionsAdded: ((Int) -> Void)? = nil
    ) {
        self.trip = trip
        self.existingItemNames = existingItemNames
        self.onSuggestionsAdded = onSuggestionsAdded
        self._viewModel = State(initialValue: AISuggestionsViewModel(trip: trip))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            sheetBackground
                .ignoresSafeArea()

            // Content
            VStack(spacing: 0) {
                // Navigation bar area
                sheetHeader

                // State router
                ZStack {
                    switch viewModel.loadingState {
                    case .idle:
                        Color.clear
                    case .loading:
                        loadingView
                            .transition(.opacity)
                    case .success:
                        successView
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    case .error(let error):
                        errorView(error: error)
                            .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: viewModel.loadingState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom action bar spacer (avoids content hiding under bar)
                if case .success = viewModel.loadingState {
                    Spacer().frame(height: 96)
                }
            }

            // Sticky bottom action bar — only in success state
            if case .success = viewModel.loadingState {
                actionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // No-key overlay banner
            if viewModel.isNoKeyState, case .success = viewModel.loadingState {
                noKeyBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            // Start fetch immediately on appear
            if viewModel.loadingState == .idle {
                // Show mock suggestions instantly for no-key state
                if viewModel.isNoKeyState {
                    viewModel.suggestions = AISuggestionsViewModel.mockSuggestionsForDisplay()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                        viewModel.loadingState = .success
                    }
                } else {
                    await viewModel.loadSuggestions(existingItems: existingItemNames)
                }
            }
        }
        .onChange(of: viewModel.loadingState) { _, newState in
            if case .success = newState {
                // Trigger stagger animation after a short settle delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        cardsAppeared = true
                    }
                }
            } else {
                cardsAppeared = false
            }
        }
        .onChange(of: viewModel.didAddItems) { _, added in
            if added {
                onSuggestionsAdded?(viewModel.lastAddedCount)
                // Brief success feedback then dismiss
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                showSuccessOverlay = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Background

    private var sheetBackground: some View {
        Group {
            if colorScheme == .dark {
                Color.otisSlate.opacity(0.95)
            } else {
                Color.otisCreame
            }
        }
    }

    // MARK: - Sheet Header

    private var sheetHeader: some View {
        HStack(alignment: .center) {
            // Leading: dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.otisSlate.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.otisSlate.opacity(0.08))
                    )
            }
            .accessibilityLabel("Close")

            Spacer()

            // Center: title (shown in success state)
            if case .success = viewModel.loadingState {
                VStack(spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.otisTeal)
                        Text("Otis packed \(viewModel.suggestions.count) ideas")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.otisSlate)
                    }
                    if !trip.destination.isEmpty {
                        Text("for \(trip.destination)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.otisSlate.opacity(0.55))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            Spacer()

            // Trailing: placeholder to balance layout
            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - LOADING STATE

    private var loadingView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Otis mascot with bounce + spinner
            ZStack {
                // Teal circular progress ring behind Otis
                Circle()
                    .stroke(Color.otisTeal.opacity(0.12), lineWidth: 3)
                    .frame(width: 110, height: 110)

                SpinningArc()
                    .frame(width: 110, height: 110)

                // Otis otter emoji / mascot
                OtisMascot(state: .active, size: 72)
                    .modifier(BounceModifier())
            }

            // Typewriter message
            Text(viewModel.currentLoadingMessage)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.otisSlate.opacity(0.75))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentLoadingMessage)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - SUCCESS STATE

    private var successView: some View {
        VStack(spacing: 0) {
            // Filter tabs
            filterTabRow
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Suggestion list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    let filtered = viewModel.filteredSuggestions
                    if filtered.isEmpty {
                        emptyFilterState
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, suggestion in
                            SuggestionCard(
                                suggestion: suggestion,
                                onToggle: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        viewModel.toggleSuggestion(suggestion)
                                    }
                                }
                            )
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.78)
                                    .delay(Double(index) * 0.04),
                                value: cardsAppeared
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Filter Tab Row

    private var filterTabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AISuggestionsViewModel.SuggestionFilter.allCases) { filter in
                    FilterTab(
                        filter: filter,
                        count: viewModel.count(for: filter),
                        isSelected: viewModel.selectedFilter == filter,
                        onTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                viewModel.selectedFilter = filter
                                // Reset stagger so newly visible cards animate in
                                cardsAppeared = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                                    cardsAppeared = true
                                }
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Empty Filter State

    private var emptyFilterState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(Color.otisSlate.opacity(0.3))
            Text("No \(viewModel.selectedFilter.displayName.lowercased()) items")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.otisSlate.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - BOTTOM ACTION BAR

    @ViewBuilder
    private var actionBar: some View {
        Group {
            if #available(iOS 26, *) {
                actionBarContent
                    .background(
                        Rectangle()
                            .fill(.clear)
                            .glassEffect(.regular, in: .rect(cornerRadius: 0))
                    )
            } else {
                actionBarContent
                    .background(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var actionBarContent: some View {
        HStack(spacing: 12) {
            // Left: selected count
            selectedCountLabel

            Spacer()

            // Center: Add Selected (primary)
            addSelectedButton

            // Right: Add All Essentials (ghost)
            if viewModel.hasUnacceptedEssentials {
                addAllEssentialsButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .padding(.bottom, 4) // extra for home indicator
    }

    private var selectedCountLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.selectedCount > 0 ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(viewModel.selectedCount > 0 ? Color.otisTeal : Color.otisSlate.opacity(0.4))

            Text("\(viewModel.selectedCount) selected")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.otisSlate.opacity(0.7))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: viewModel.selectedCount)
        }
        .frame(minWidth: 80, alignment: .leading)
    }

    private var addSelectedButton: some View {
        Button {
            guard viewModel.selectedCount > 0 else { return }
            let count = viewModel.addSelectedToTrip(modelContext: modelContext)
            _ = count
        } label: {
            Text("Add Selected")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(viewModel.selectedCount > 0
                              ? Color.otisTeal
                              : Color.otisSlate.opacity(0.2))
                )
        }
        .disabled(viewModel.selectedCount == 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: viewModel.selectedCount)
        .accessibilityLabel("Add \(viewModel.selectedCount) selected items to packing list")
    }

    private var addAllEssentialsButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                _ = viewModel.addAllEssentials(modelContext: modelContext)
            }
        } label: {
            Text("Add Essentials")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.otisTeal)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .strokeBorder(Color.otisTeal.opacity(0.5), lineWidth: 1.5)
                )
        }
        .accessibilityLabel("Add all essential items to packing list")
    }

    // MARK: - ERROR STATE

    private func errorView(error: OpenAIError) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Otis napping
            ZStack(alignment: .topTrailing) {
                OtisMascot(state: .napping, size: 80)
                // Zzz bubble
                VStack(spacing: -4) {
                    Text("z")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.otisSlate.opacity(0.4))
                    Text("Z")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.otisSlate.opacity(0.5))
                    Text("Z")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.otisSlate.opacity(0.6))
                }
                .offset(x: 28, y: -16)
            }

            // Error message
            VStack(spacing: 8) {
                Text("Otis hit a snag")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.otisSlate)

                Text(error.localizedDescription)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.otisSlate.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(3)
            }

            // Action buttons
            VStack(spacing: 12) {
                // Try Again — primary
                Button {
                    viewModel.reset()
                    Task {
                        await viewModel.loadSuggestions(existingItems: existingItemNames)
                    }
                } label: {
                    Text("Try Again")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.otisTeal))
                }
                .padding(.horizontal, 40)

                // Add Manually — ghost
                Button {
                    dismiss()
                } label: {
                    Text("Add Items Manually")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.otisSlate.opacity(0.6))
                }
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - NO KEY BANNER

    private var noKeyBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.otisGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Otis to unlock personalized suggestions")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.otisSlate)
                    Text("Add your OpenAI API key in Settings")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.otisSlate.opacity(0.6))
                }

                Spacer()

                // Settings deep-link
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Settings")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.otisTeal)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .strokeBorder(Color.otisTeal.opacity(0.5), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.otisGold.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.otisGold.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 104) // above action bar
        }
    }
}

// MARK: - FilterTab

private struct FilterTab: View {

    let filter: AISuggestionsViewModel.SuggestionFilter
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Text(filter.shortName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.otisSlate.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.25) : Color.otisSlate.opacity(0.1))
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.otisSlate.opacity(0.65))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.otisTeal : Color.otisSlate.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.displayName), \(count) items")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - OtisMascot

/// Emoji-based Otis mascot with different states.
/// Replace with actual otter asset once design delivers the asset pack.
struct OtisMascot: View {

    enum OtisDisplayState {
        case active     // Thinking / working
        case idle       // Default
        case napping    // Error / resting
        case celebrating // Success
    }

    let state: OtisDisplayState
    var size: CGFloat = 60

    var body: some View {
        Text(emoji)
            .font(.system(size: size))
            .accessibilityHidden(true) // decorative
    }

    private var emoji: String {
        switch state {
        case .active:       return "🦦"
        case .idle:         return "🦦"
        case .napping:      return "😴"
        case .celebrating:  return "🎉"
        }
    }
}

// MARK: - BounceModifier

/// Continuous vertical bounce animation for the loading state mascot.
private struct BounceModifier: ViewModifier {
    @State private var bouncing: Bool = false

    func body(content: Content) -> some View {
        content
            .offset(y: bouncing ? -10 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    bouncing = true
                }
            }
    }
}

// MARK: - SpinningArc

/// Teal arc that rotates continuously — progress indicator behind Otis.
private struct SpinningArc: View {
    @State private var isAnimating: Bool = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [Color.otisTeal, Color.otisTeal.opacity(0.1)]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(
                    .linear(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - View Extension for Callback Chaining

extension AISuggestionsView {
    /// Chainable modifier for the add callback.
    func onSuggestionsAdded(_ handler: @escaping (Int) -> Void) -> AISuggestionsView {
        var copy = self
        copy.onSuggestionsAdded = handler
        return copy
    }
}

// MARK: - Preview

#Preview("Loading State") {
    // Simulate loading state
    struct LoadingPreview: View {
        var body: some View {
            let trip = Trip(
                destination: "Bali, Indonesia",
                startDate: Date(),
                endDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())!,
                tripType: .beach
            )
            AISuggestionsView(trip: trip)
        }
    }
    return LoadingPreview()
}

#Preview("Success State — Light") {
    struct SuccessPreview: View {
        @State private var vm: AISuggestionsViewModel

        init() {
            let trip = Trip(
                destination: "Bali, Indonesia",
                startDate: Date(),
                endDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())!,
                tripType: .beach
            )
            let viewModel = AISuggestionsViewModel(trip: trip)
            viewModel.suggestions = [
                PackingSuggestion(name: "Passport", category: .documents, reason: "Required for international entry — always keep in carry-on.", priority: .essential, isAccepted: true),
                PackingSuggestion(name: "Universal power adapter", category: .electronics, reason: "Bali uses Type C/F outlets — most hotels don't provide adapters.", priority: .essential),
                PackingSuggestion(name: "Reef-safe sunscreen SPF 50", category: .toiletries, reason: "Required by Balinese law to protect coral reefs. Regular sunscreen can incur fines.", priority: .recommended),
                PackingSuggestion(name: "Lightweight scarf/sarong", category: .clothing, reason: "Bali temples require covered knees and shoulders for entry.", priority: .recommended),
                PackingSuggestion(name: "Portable mosquito repellent", category: .health, reason: "Dengue fever risk is elevated in Ubud during rainy season.", priority: .recommended),
                PackingSuggestion(name: "Offline maps download", category: .essentials, reason: "Rural Ubud roads have spotty signal — download before you go.", priority: .niceToHave),
            ]
            viewModel.loadingState = .success
            self._vm = State(initialValue: viewModel)
        }

        var body: some View {
            // Preview just shows the card list portion
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(vm.suggestions) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            onToggle: { vm.toggleSuggestion(suggestion) }
                        )
                    }
                }
                .padding()
            }
            .background(Color.otisCreame)
        }
    }
    return SuccessPreview()
}
