// PassportView.swift
// Otis — Views/Passport/
//
// The stamp collection screen. Feels like opening a beautiful physical passport.
// Every stamp is unique — subtle random rotation and scale variation per cell.
//
// Architecture:
//   - @Query fetches stamps sorted by earnedAt ascending (chronological collection)
//   - StampCell: reusable hand-stamped card component
//   - StampDetailView: sheet with full stamp, trip details, ShareLink
//   - Empty state: Otis holding blank passport, CTA to create first trip
//   - Share: ImageRenderer renders full grid as shareable image
//
// iOS 17+ SwiftData. iOS 26 Liquid Glass on toolbar controls only.

import SwiftUI
import SwiftData

// MARK: - PassportView

struct PassportView: View {

    // MARK: - SwiftData

    @Query(sort: \Stamp.earnedAt, order: .forward)
    private var stamps: [Stamp]

    // MARK: - Environment

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var selectedStamp: Stamp? = nil
    @State private var showShareSheet: Bool = false
    @State private var shareImage: UIImage? = nil
    @State private var isRenderingShare: Bool = false
    @State private var newStampID: PersistentIdentifier? = nil  // animates new stamp in

    // MARK: - Grid Layout

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    /// Number of locked "ghost" slots to show after earned stamps (creates anticipation)
    private let lockedSlotsToShow: Int = 3

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Cream parchment background — passport feel
                Color.otisCreame.ignoresSafeArea()

                if stamps.isEmpty {
                    emptyStateView
                } else {
                    stampCollectionView
                }
            }
            .navigationTitle("My Passport")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .sheet(item: $selectedStamp) { stamp in
                StampDetailView(stamp: stamp)
                    .presentationDetents([.height(580)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = shareImage {
                    ShareSheet(image: img)
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                renderAndShare()
            } label: {
                HStack(spacing: 5) {
                    if isRenderingShare {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(.otisTeal)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
            }
            .disabled(stamps.isEmpty || isRenderingShare)
            .foregroundStyle(stamps.isEmpty ? .otisSlateLight : .otisTeal)
            .if_available_iOS26 { view in
                view.glassEffect(in: .capsule)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Stamp Collection View

    private var stampCollectionView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Passport header with Otis + stats
                passportHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                // Divider — like a passport page separator
                PassportPageDivider()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                // Stamp grid
                LazyVGrid(columns: columns, spacing: 16) {
                    // Earned stamps
                    ForEach(stamps) { stamp in
                        StampCell(
                            stamp: stamp,
                            isNew: stamp.persistentModelID == newStampID
                        )
                        .onTapGesture {
                            selectedStamp = stamp
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.3).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                    }

                    // Locked ghost slots (next 3 upcoming stamps)
                    ForEach(0..<lockedSlotsToShow, id: \.self) { idx in
                        LockedStampCell(tripNumber: stamps.count + idx + 1)
                    }
                }
                .padding(.horizontal, 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: stamps.count)

                // Footer encouragement
                if stamps.count >= 1 {
                    passportFooter
                        .padding(.top, 32)
                        .padding(.bottom, 40)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Passport Header

    private var passportHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            // Otis holding passport illustration
            ZStack(alignment: .bottomTrailing) {
                // Otis mascot
                Image("otis-calm")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.otisTeal.opacity(0.3), lineWidth: 2))

                // Mini passport overlay
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "1A472A"))
                        .frame(width: 26, height: 34)
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

                    Text("🌍")
                        .font(.system(size: 12))
                }
                .offset(x: 8, y: 8)
            }
            .padding(.trailing, 4)

            // Stats
            HStack(spacing: 0) {
                StatPill(value: stamps.count, label: stamps.count == 1 ? "Stamp" : "Stamps")

                TealDivider()

                StatPill(
                    value: uniqueCountries,
                    label: uniqueCountries == 1 ? "Country" : "Countries"
                )

                TealDivider()

                StatPill(value: stamps.count, label: "Trips")
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.6))
                    .shadow(color: .otisSlate.opacity(0.06), radius: 6, x: 0, y: 2)
            )
        }
    }

    private var uniqueCountries: Int {
        // Heuristic: count unique destinations as a proxy for countries
        Set(stamps.map { $0.destination.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) ?? $0.destination }).count
    }

    // MARK: - Footer

    private var passportFooter: some View {
        VStack(spacing: 8) {
            Text("✦ \(stamps.count) of your adventures, stamped ✦")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.otisSlateLight)
                .multilineTextAlignment(.center)

            if let nextMilestone = nextMilestoneNumber {
                Text("\(nextMilestone - stamps.count) trips until \"\(milestoneLabel(nextMilestone))\"")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.otisTeal.opacity(0.8))
            }
        }
        .padding(.horizontal, 20)
    }

    private var nextMilestoneNumber: Int? {
        let milestones = StampService.milestoneNumbers.sorted()
        return milestones.first { $0 > stamps.count }
    }

    private func milestoneLabel(_ n: Int) -> String {
        switch n {
        case 5:  return "Seasoned Traveler"
        case 10: return "World Wanderer"
        case 25: return "Expedition Master"
        case 50: return "Otis Legend"
        default: return "Milestone"
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // Passport illustration
            ZStack {
                // Passport book
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "1A472A"))
                    .frame(width: 110, height: 145)
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)

                // Embossed circle
                Circle()
                    .stroke(Color.otisGold.opacity(0.5), lineWidth: 2)
                    .frame(width: 64, height: 64)

                // Question mark — waiting for first stamp
                Text("?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.otisGold.opacity(0.45))
            }
            .overlay(alignment: .bottomTrailing) {
                // Otis peeking with excitement
                VStack(spacing: 2) {
                    Text("🦦")
                        .font(.system(size: 44))
                }
                .offset(x: 22, y: 18)
            }
            .padding(.bottom, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Your passport is waiting")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.otisSlate)
                    .multilineTextAlignment(.center)

                Text("Complete your first trip and Otis will stamp your passport. Each destination earns a unique stamp.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .lineSpacing(3)
            }

            // CTA — posts notification to show TripCreation sheet
            Button {
                NotificationCenter.default.post(name: .showTripCreation, object: nil)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create a Trip")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.otisTeal, Color(hex: "4AAFA5")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .otisTeal.opacity(0.4), radius: 10, x: 0, y: 4)
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Share Rendering

    private func renderAndShare() {
        isRenderingShare = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            let shareView = PassportShareCard(stamps: stamps)
            let renderer = ImageRenderer(content: shareView)
            renderer.scale = 3.0  // @3x for crisp sharing

            if let uiImage = renderer.uiImage {
                shareImage = uiImage
                showShareSheet = true
            }
            isRenderingShare = false
        }
    }
}

// MARK: - StampCell

/// A single passport stamp cell — the core visual unit of the collection.
/// Hand-stamped aesthetic with subtle random rotation and scale variation.
struct StampCell: View {

    let stamp: Stamp
    var isNew: Bool = false

    // Each stamp gets a stable random seed from its trip number for consistent jitter
    private var rotationDegrees: Double {
        let seed = stamp.tripNumber
        let mapped = Double((seed * 7 + 3) % 9) - 4.0  // -4...4
        return mapped * 0.5  // subtle: -2...2
    }

    private var scaleVariation: CGFloat {
        let seed = stamp.tripNumber
        let mapped = CGFloat((seed * 13 + 5) % 10)
        return 0.96 + (mapped / 10.0 * 0.06)  // 0.96...1.02
    }

    @State private var appeared: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            // Stamp card
            ZStack {
                // Backing card with stamp-border aesthetic
                stampBorderBackground

                // Stamp graphic
                VStack(spacing: 4) {
                    stampGraphic
                        .frame(width: 52, height: 52)

                    // Milestone badge
                    if stamp.isMilestone {
                        MilestoneBadge()
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)

                // Trip number badge — top left corner like a real stamp
                Text("#\(stamp.tripNumber)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(stamp.stampType.accentColor.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.85))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)
            }
            .frame(minHeight: stamp.isMilestone ? 110 : 98)
            .rotationEffect(.degrees(rotationDegrees))
            .scaleEffect(scaleVariation)
            .scaleEffect(appeared ? 1.0 : 0.3)
            .opacity(appeared ? 1.0 : 0.0)

            // Destination label
            Text(stamp.destination)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.otisSlate)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)

            // Earned date
            Text(stamp.earnedAt.formatted(.dateTime.month(.abbreviated).year()))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(.otisSlateLight)
        }
        .onAppear {
            if !appeared {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.68).delay(isNew ? 0.0 : 0.05)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Stamp Border Background

    private var stampBorderBackground: some View {
        ZStack {
            // Main fill
            RoundedRectangle(cornerRadius: 14)
                .fill(stamp.stampType.backgroundColor)

            // Dashed perforated border — classic stamp look
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    stamp.isMilestone
                        ? Color.otisGold
                        : stamp.stampType.accentColor.opacity(0.6),
                    style: StrokeStyle(
                        lineWidth: stamp.isMilestone ? 2 : 1.5,
                        dash: [3, 2.5]
                    )
                )
                .padding(4)

            // firstTrip: gold outer glow ring
            if stamp.stampType == .firstTrip {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.otisGold, lineWidth: 2)
                    .opacity(0.8)
            }
        }
        .shadow(
            color: stamp.stampType.accentColor.opacity(stamp.isMilestone ? 0.25 : 0.12),
            radius: stamp.isMilestone ? 8 : 4,
            x: 0, y: 2
        )
    }

    // MARK: - Stamp Graphic (SF Symbol + Color)

    @ViewBuilder
    private var stampGraphic: some View {
        switch stamp.stampType {
        case .firstTrip:
            firstTripGraphic
        case .milestone:
            milestoneGraphic
        case .beach:
            stampIcon("sun.max.fill", color: Color(hex: "2196F3"), bg: Color(hex: "E3F2FD"))
        case .mountain:
            stampIcon("mountain.2.fill", color: Color(hex: "607D8B"), bg: Color(hex: "ECEFF1"))
        case .international:
            stampIcon("globe.europe.africa.fill", color: .otisGold, bg: Color(hex: "FFF8E1"))
        case .business:
            stampIcon("briefcase.fill", color: Color(hex: "3F51B5"), bg: Color(hex: "E8EAF6"))
        case .city:
            stampIcon("building.2.fill", color: Color(hex: "546E7A"), bg: Color(hex: "ECEFF1"))
        case .winter:
            stampIcon("snowflake", color: Color(hex: "42A5F5"), bg: Color(hex: "E3F2FD"))
        case .spring:
            stampIcon("leaf.fill", color: Color(hex: "66BB6A"), bg: Color(hex: "E8F5E9"))
        case .summer:
            stampIcon("sun.min.fill", color: Color(hex: "FFA726"), bg: Color(hex: "FFF3E0"))
        case .autumn:
            stampIcon("wind", color: Color(hex: "FF7043"), bg: Color(hex: "FBE9E7"))
        }
    }

    private func stampIcon(_ name: String, color: Color, bg: Color) -> some View {
        ZStack {
            Circle()
                .fill(bg)
                .frame(width: 48, height: 48)
            Image(systemName: name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private var firstTripGraphic: some View {
        ZStack {
            // Star burst behind
            Image(systemName: "burst.fill")
                .font(.system(size: 46))
                .foregroundStyle(Color.otisGold.opacity(0.25))

            Circle()
                .fill(Color(hex: "FFF8E1"))
                .frame(width: 42, height: 42)

            Image(systemName: "star.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.otisCoral)
        }
    }

    private var milestoneGraphic: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "FFF8E1"))
                .frame(width: 48, height: 48)

            Image(systemName: "trophy.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.otisGold)
        }
    }
}

// MARK: - Locked Stamp Cell

struct LockedStampCell: View {
    let tripNumber: Int

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Gray silhouette background
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.otisSlate.opacity(0.06))

                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.otisSlate.opacity(0.15),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])
                    )
                    .padding(4)

                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.otisSlate.opacity(0.2))

                    Text("Trip #\(tripNumber)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.otisSlateLight.opacity(0.5))
                }
            }
            .frame(minHeight: 98)

            Text("Coming soon")
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.otisSlateLight.opacity(0.4))

            Text("—")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.clear)
        }
    }
}

// MARK: - Milestone Badge

struct MilestoneBadge: View {
    var body: some View {
        Text("MILESTONE")
            .font(.system(size: 7, weight: .black, design: .rounded))
            .foregroundStyle(.otisGold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.otisGold.opacity(0.15))
                    .overlay(Capsule().stroke(Color.otisGold.opacity(0.4), lineWidth: 0.5))
            )
    }
}

// MARK: - Passport Page Divider

struct PassportPageDivider: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<40, id: \.self) { _ in
                Rectangle()
                    .fill(Color.otisTeal.opacity(0.2))
                    .frame(width: 6, height: 1)
                Spacer()
            }
        }
        .frame(height: 1)
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.otisSlate)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4), value: value)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.otisSlateLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

// MARK: - Teal Divider

struct TealDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.otisTeal.opacity(0.25))
            .frame(width: 1, height: 28)
    }
}

// MARK: - StampDetailView

struct StampDetailView: View {

    let stamp: Stamp
    @Environment(\.dismiss) private var dismiss

    @State private var glowPulse: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.otisCreame.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // Large stamp graphic
                    ZStack {
                        // Pulsing glow ring
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(
                                stamp.stampType.accentColor.opacity(glowPulse ? 0.4 : 0.1),
                                lineWidth: glowPulse ? 3 : 1
                            )
                            .frame(width: 188, height: 188)
                            .scaleEffect(glowPulse ? 1.08 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                                value: glowPulse
                            )

                        // Stamp cell at 2x size
                        StampCell(stamp: stamp)
                            .frame(width: 160, height: 160)
                            .scaleEffect(1.45)
                            .padding(24)
                    }
                    .onAppear { glowPulse = true }

                    // Stamp title
                    VStack(spacing: 6) {
                        Text(stamp.displayTitle)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.otisSlate)
                            .multilineTextAlignment(.center)

                        if stamp.isMilestone {
                            HStack(spacing: 4) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.otisGold)
                                Text("Milestone Stamp")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.otisGold)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color.otisGold.opacity(0.12))
                            )
                        }
                    }

                    // Trip details card
                    VStack(spacing: 0) {
                        DetailRow(icon: "mappin.circle.fill", color: .otisTeal,
                                  label: "Destination", value: stamp.destination)
                        Divider().padding(.leading, 44)
                        DetailRow(icon: "number.circle.fill", color: .otisCoral,
                                  label: "Trip Number", value: "Trip #\(stamp.tripNumber)")
                        Divider().padding(.leading, 44)
                        DetailRow(icon: "calendar.circle.fill", color: .otisGold,
                                  label: "Earned", value: stamp.earnedAt.formatted(.dateTime.month(.wide).day().year()))
                        Divider().padding(.leading, 44)
                        DetailRow(icon: "cloud.sun.fill", color: Color(hex: "66BB6A"),
                                  label: "Season", value: stamp.season.displayName)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.8))
                            .shadow(color: .otisSlate.opacity(0.07), radius: 8, x: 0, y: 2)
                    )
                    .padding(.horizontal, 20)

                    // Share button
                    ShareLink(
                        item: renderedStampImage,
                        preview: SharePreview(
                            "\(stamp.displayTitle) — \(stamp.destination)",
                            image: renderedStampImage
                        )
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Stamp")
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [.otisTeal, Color(hex: "4AAFA5")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .otisTeal.opacity(0.35), radius: 8, x: 0, y: 3)
                        )
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 20)
                }
                .padding(.top, 32)
            }

            // Close button
            Button {
                dismiss()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.otisSlate.opacity(0.4))
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(20)
        }
    }

    // Render stamp as transferable image for ShareLink
    private var renderedStampImage: Image {
        let renderer = ImageRenderer(
            content: StampShareCard(stamp: stamp)
                .frame(width: 400, height: 400)
                .background(Color.otisCreame)
        )
        renderer.scale = 3.0
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.otisSlateLight)
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.otisSlate)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - StampShareCard (for ShareLink rendering)

struct StampShareCard: View {
    let stamp: Stamp

    var body: some View {
        VStack(spacing: 20) {
            // App branding
            HStack(spacing: 6) {
                Text("🦦")
                    .font(.system(size: 18))
                Text("Otis")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.otisTeal)
            }

            // Large stamp
            StampCell(stamp: stamp)
                .frame(width: 140, height: 140)
                .scaleEffect(1.4)
                .padding(24)

            // Title and destination
            VStack(spacing: 6) {
                Text(stamp.displayTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.otisSlate)

                Text(stamp.destination)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.otisSlateLight)

                Text("Trip #\(stamp.tripNumber) · \(stamp.earnedAt.formatted(.dateTime.month(.wide).year()))")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.otisSlateLight.opacity(0.7))
            }
        }
        .padding(32)
        .frame(width: 400, height: 400)
        .background(Color.otisCreame)
    }
}

// MARK: - PassportShareCard (full collection for toolbar share)

struct PassportShareCard: View {
    let stamps: [Stamp]

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 6) {
                Text("🦦")
                    .font(.system(size: 20))
                Text("My Otis Passport")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.otisTeal)
            }

            Text("\(stamps.count) stamps earned")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.otisSlateLight)

            // Mini stamp grid
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(stamps.prefix(9)) { stamp in
                    StampCell(stamp: stamp)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)

            if stamps.count > 9 {
                Text("+ \(stamps.count - 9) more adventures")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.otisTeal)
            }
        }
        .padding(24)
        .background(Color.otisCreame)
        .frame(width: 500)
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Notification Extension

extension Notification.Name {
    /// Posted by PassportView empty state CTA to trigger TripCreation sheet in root.
    static let showTripCreation = Notification.Name("OtisShowTripCreation")
}

// MARK: - StampType Display Helpers

extension StampType {
    /// Background fill color for the stamp card.
    var backgroundColor: Color {
        switch self {
        case .firstTrip:      return Color(hex: "FFF3E0")
        case .milestone:      return Color(hex: "FFF8E1")
        case .beach:          return Color(hex: "E3F2FD")
        case .mountain:       return Color(hex: "ECEFF1")
        case .international:  return Color(hex: "FFF8E1")
        case .business:       return Color(hex: "E8EAF6")
        case .city:           return Color(hex: "F5F5F5")
        case .winter:         return Color(hex: "E3F2FD")
        case .spring:         return Color(hex: "E8F5E9")
        case .summer:         return Color(hex: "FFF3E0")
        case .autumn:         return Color(hex: "FBE9E7")
        }
    }

    /// Accent color used for borders, icons, and badges.
    var accentColor: Color {
        switch self {
        case .firstTrip:      return .otisCoral
        case .milestone:      return .otisGold
        case .beach:          return Color(hex: "2196F3")
        case .mountain:       return Color(hex: "607D8B")
        case .international:  return .otisGold
        case .business:       return Color(hex: "3F51B5")
        case .city:           return Color(hex: "546E7A")
        case .winter:         return Color(hex: "42A5F5")
        case .spring:         return Color(hex: "66BB6A")
        case .summer:         return Color(hex: "FFA726")
        case .autumn:         return Color(hex: "FF7043")
        }
    }
}

// MARK: - Season Display Name

extension Season {
    var displayName: String {
        switch self {
        case .winter: return "Winter"
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .autumn: return "Autumn"
        }
    }
}

// MARK: - iOS 26 Liquid Glass Compatibility Shim
// Apply .glassEffect() only on iOS 26+; no-op on earlier versions.

extension View {
    @ViewBuilder
    func if_available_iOS26<Content: View>(@ViewBuilder transform: (Self) -> Content) -> some View {
        if #available(iOS 26, *) {
            transform(self)
        } else {
            self
        }
    }
}
