// TripListView.swift
// Otis — Trip list screen (Phase 0 scaffold)
//
// Phase 0: Compiles, navigates, shows empty state with Otis.
// Phase 1 (P1-A): Full TripCreationView sheet, trip cards, swipe-to-delete.
//
// Architecture: View is intentionally thin — all state lives in TripListViewModel.

import SwiftUI
import SwiftData

struct TripListView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    // MARK: - SwiftData Query

    @Query(sort: \Trip.departureDate, order: .forward)
    private var trips: [Trip]

    // MARK: - Navigation & Sheet State

    @State private var showingTripCreation = false
    @State private var selectedTrip: Trip? = nil
    @State private var fabScale: CGFloat = 1.0

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // MARK: Content
                Group {
                    if trips.isEmpty {
                        emptyStateView
                    } else {
                        tripListContent
                    }
                }
                .otisBackground()

                // MARK: Floating Action Button
                fabButton
                    .padding(.trailing, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingTripCreation) {
                // P1-A: TripCreationView will be implemented here
                TripCreationPlaceholderView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // Otis calm illustration
            VStack(spacing: Theme.Spacing.md) {
                Image("otis-calm")
                    .resizable()
                    .interpolation(.none) // preserve pixel art crispness
                    .scaledToFit()
                    .frame(width: Theme.IconSize.otisHero, height: Theme.IconSize.otisHero)
                    // Fallback while assets aren't in catalog yet
                    .overlay {
                        if UIImage(named: "otis-calm") == nil {
                            OtisPlaceholderIllustration(state: .calm)
                        }
                    }

                Text("Otis is ready to help you pack.")
                    .font(.otisSubheadline)
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
            }

            // CTA
            VStack(spacing: Theme.Spacing.sm) {
                Text("Create your first trip")
                    .font(.otisTitle)
                    .foregroundStyle(.otisSlate)
                    .multilineTextAlignment(.center)

                Text("Tell Otis where you're headed and he'll help you pack smarter.")
                    .font(.otisBody)
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Button("Create Trip") {
                showingTripCreation = true
            }
            .buttonStyle(.otisPrimary)
            .padding(.horizontal, Theme.Spacing.xl)
            .accessibilityIdentifier("createFirstTripButton")

            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Trip List Content

    private var tripListContent: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                // Active / Planning trips
                let activeTripsList = trips.filter { $0.status == .planning || $0.status == .active }
                let completedTripsList = visibleCompletedTrips

                if !activeTripsList.isEmpty {
                    tripSection(title: "Upcoming", trips: activeTripsList)
                }

                if !completedTripsList.isEmpty {
                    tripSection(title: "Completed", trips: completedTripsList)
                }

                // Free tier history limit nudge
                if !subscriptionManager.isPro && completedTripsCount > AppConfig.freeTierMaxTripHistory {
                    freeHistoryLimitRow
                }
            }
            .padding(Theme.Spacing.md)
            .padding(.bottom, 100) // FAB clearance
        }
    }

    private func tripSection(title: String, trips: [Trip]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(.otisOverline)
                .foregroundStyle(.otisSlateLight)
                .padding(.horizontal, Theme.Spacing.xs)

            ForEach(trips) { trip in
                TripRowCard(trip: trip)
                    .onTapGesture { selectedTrip = trip }
            }
        }
    }

    private var visibleCompletedTrips: [Trip] {
        let completed = trips.filter { $0.status == .completed || $0.status == .archived }
        if subscriptionManager.isPro {
            return completed
        } else {
            return Array(completed.prefix(AppConfig.freeTierMaxTripHistory))
        }
    }

    private var completedTripsCount: Int {
        trips.filter { $0.status == .completed || $0.status == .archived }.count
    }

    private var freeHistoryLimitRow: some View {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundStyle(.otisTeal)
            Text("Unlock full history with Otis Pro")
                .font(.otisCaption)
                .foregroundStyle(.otisSlateLight)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.otisCaption)
                .foregroundStyle(.otisSlateLight)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Color.otisMint.opacity(0.3))
        )
    }

    // MARK: - Floating Action Button

    private var fabButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            showingTripCreation = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(.otisTeal))
                .otisShadow(.float)
        }
        .scaleEffect(fabScale)
        .onAppear {
            withAnimation(Theme.Animation.materialization.delay(0.3)) {
                fabScale = 1.0
            }
        }
        .accessibilityLabel("Create new trip")
        .accessibilityIdentifier("createTripFAB")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if subscriptionManager.isPro {
                // Pro badge — subtle, not boastful
                Text("PRO")
                    .font(.otisCaptionBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.otisTeal))
                    .accessibilityLabel("Otis Pro active")
            }
        }
    }
}

// MARK: - Trip Row Card

struct TripRowCard: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Trip type icon circle
            ZStack {
                Circle()
                    .fill(Color(hex: trip.tripType.accentColorHex).opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: trip.tripType.iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: trip.tripType.accentColorHex))
            }

            // Trip info
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.otisHeadline)
                    .foregroundStyle(.otisSlate)
                    .lineLimit(1)

                Text(trip.destination)
                    .font(.otisCaption)
                    .foregroundStyle(.otisSlateLight)

                Text(trip.departureDate, style: .date)
                    .font(.otisCaption)
                    .foregroundStyle(.otisSlateLight)
            }

            Spacer()

            // Progress or stamp indicator
            if trip.status == .completed {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.otisGold)
                    .font(.system(size: 22))
            } else {
                // Packing progress ring
                ZStack {
                    Circle()
                        .stroke(Color.otisMint.opacity(0.4), lineWidth: 3)
                        .frame(width: 36, height: 36)
                    Circle()
                        .trim(from: 0, to: trip.packingProgress)
                        .stroke(Color.otisTeal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(trip.packingProgress * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.otisTeal)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(.white)
                .otisShadow(.card)
        )
    }
}

// MARK: - Placeholder for P1-A TripCreationView

/// Replaced entirely in P1-A. Exists so Phase 0 compiles and navigates correctly.
struct TripCreationPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()
                OtisPlaceholderIllustration(state: .active)
                    .frame(width: Theme.IconSize.otisMedium, height: Theme.IconSize.otisMedium)

                Text("Trip creation coming in P1-A")
                    .font(.otisHeadline)
                    .foregroundStyle(.otisSlate)

                Button("Done") { dismiss() }
                    .buttonStyle(.otisPrimary)
                    .padding(.horizontal, Theme.Spacing.xl)
                Spacer()
            }
            .otisBackground()
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.otisTeal)
                }
            }
        }
    }
}

// MARK: - Otis Placeholder Illustration
// Renders a simple programmatic stand-in until pixel art assets are added.

enum OtisState {
    case calm       // checklist, neutral eyes
    case active     // wide eyes, checklist raised
    case celebrating // jumping, stars
    case napping    // eyes closed, Zzz
}

struct OtisPlaceholderIllustration: View {
    let state: OtisState

    private var bgColor: Color {
        switch state {
        case .calm:        return .otisTeal
        case .active:      return .otisTeal
        case .celebrating: return .otisCoral
        case .napping:     return .otisMint
        }
    }

    private var emoji: String {
        switch state {
        case .calm:        return "🦦"
        case .active:      return "🦦"
        case .celebrating: return "🦦"
        case .napping:     return "🦦"
        }
    }

    private var label: String {
        switch state {
        case .calm:        return "Otis is ready."
        case .active:      return "Otis is on the case."
        case .celebrating: return "You did it!"
        case .napping:     return "Otis is napping."
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(bgColor.opacity(0.15))
                    .frame(width: 120, height: 120)

                Text(emoji)
                    .font(.system(size: 64))
            }

            Text(label)
                .font(.otisCaption)
                .foregroundStyle(.otisSlateLight)
        }
    }
}

// MARK: - Preview

#Preview("Empty State") {
    TripListView()
        .environmentObject(SubscriptionManager())
        .modelContainer(for: [Trip.self, PackingItem.self, PackingProfile.self, Stamp.self],
                        inMemory: true)
}

#Preview("With Trips") {
    let container = try! ModelContainer(
        for: Trip.self, PackingItem.self, PackingProfile.self, Stamp.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let trip1 = Trip(
        name: "Lisbon Getaway",
        destinationCity: "Lisbon",
        destinationCountry: "Portugal",
        tripType: .city,
        departureDate: Date().addingTimeInterval(86400 * 7)
    )
    let item1 = PackingItem(name: "Passport", category: .documents, isChecked: true, trip: trip1)
    let item2 = PackingItem(name: "Sunscreen", category: .toiletries, trip: trip1)
    container.mainContext.insert(trip1)
    container.mainContext.insert(item1)
    container.mainContext.insert(item2)
    return TripListView()
        .environmentObject(SubscriptionManager())
        .modelContainer(container)
}
