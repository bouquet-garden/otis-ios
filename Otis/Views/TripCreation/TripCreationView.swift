// TripCreationView.swift
// Otis — Views/TripCreation/
//
// 3-step trip creation sheet. Feels like booking a trip, not filling a form.
//
// Step 0 — Where are you going? (destination + TripType chip picker + Otis illustration)
// Step 1 — When?               (departure date, optional return date, night count badge)
// Step 2 — Name your trip       (editable auto-name, 40-char limit, Create CTA)
//
// Sheet presentation: .presentationDetents([.large])
// Step transitions: asymmetric slide — insert from trailing, remove to leading
// All animations: .spring(response: 0.4, dampingFraction: 0.75)
//
// Dependencies (already in project):
//   TripCreationViewModel  — @Observable ViewModel (TripCreationViewModel.swift)
//   TripTypeChip / TripTypeChipRow — pill chip selector (TripTypeChip.swift)
//   StepProgressView       — 3-dot progress indicator (StepProgressView.swift)
//   Theme                  — design system (Theme.swift)
//   Enums (TripType)       — trip type enum (Enums.swift)
//   Trip (@Model)          — SwiftData model (Trip.swift)

import SwiftUI
import SwiftData

// MARK: - TripCreationView

struct TripCreationView: View {

    // MARK: Environment & State

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    /// All existing trips — used to determine isFirstTrip at creation time.
    @Query(sort: \Trip.createdAt, order: .forward)
    private var existingTrips: [Trip]

    @State private var viewModel = TripCreationViewModel()

    /// Focus state for every text field in the sheet.
    @FocusState private var focusedField: Field?

    /// Triggered when the trip is successfully created. Parent uses this to
    /// navigate into the new trip's packing list.
    var onTripCreated: ((Trip) -> Void)?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background
                Color.otisCreame.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Navigation bar area
                    headerBar

                    // Step content — slides between steps
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom navigation buttons
                    bottomNavBar
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
        .confirmationDialog(
            "Discard this trip?",
            isPresented: $viewModel.showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                viewModel.reset()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("Your trip details will be lost.")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            // Cancel button
            Button {
                focusedField = nil
                if viewModel.hasUnsavedChanges {
                    viewModel.showCancelConfirmation = true
                } else {
                    dismiss()
                }
            } label: {
                Text("Cancel")
                    .font(.otisBody)
                    .foregroundStyle(Color.otisSlate.opacity(0.7))
            }
            .accessibilityLabel("Cancel trip creation")

            Spacer()

            // Progress dots
            StepProgressView(
                currentStep: viewModel.currentStep,
                totalSteps: viewModel.totalSteps
            )

            Spacer()

            // Back chevron — hidden on step 0
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    viewModel.goToPreviousStep()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(viewModel.currentStep > 0 ? Color.otisTeal : Color.clear)
            }
            .disabled(viewModel.currentStep == 0)
            .accessibilityLabel("Go to previous step")
            .accessibilityHidden(viewModel.currentStep == 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Step Content Router

    @ViewBuilder
    private var stepContent: some View {
        ZStack {
            switch viewModel.currentStep {
            case 0:
                StepOneView(viewModel: viewModel, focusedField: $focusedField)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
            case 1:
                StepTwoView(viewModel: viewModel, focusedField: $focusedField)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
            case 2:
                StepThreeView(viewModel: viewModel, focusedField: $focusedField)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))
            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.currentStep)
    }

    // MARK: - Bottom Nav Bar

    private var bottomNavBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.15)

            HStack(spacing: Theme.Spacing.md) {
                if viewModel.currentStep < viewModel.totalSteps - 1 {
                    // Next button
                    Button {
                        focusedField = nil
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            viewModel.proceedToNextStep()
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text("Next")
                                .font(.otisBodyBold)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(
                                    viewModel.canProceedFromCurrentStep
                                        ? Color.otisTeal
                                        : Color.otisSlate.opacity(0.2)
                                )
                        )
                    }
                    .disabled(!viewModel.canProceedFromCurrentStep)
                    .accessibilityLabel("Continue to next step")
                    .animation(.easeInOut(duration: 0.2), value: viewModel.canProceedFromCurrentStep)
                } else {
                    // Create Trip CTA (step 2 only)
                    CreateTripButton {
                        focusedField = nil
                        createTrip()
                    }
                    .disabled(!viewModel.canProceedFromCurrentStep)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Color.otisCreame)
    }

    // MARK: - Create Trip Action

    private func createTrip() {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.prepare()
        haptic.impactOccurred()

        let isFirst = existingTrips.isEmpty
        let trip = viewModel.createTrip(modelContext: modelContext, isFirstTrip: isFirst)

        // Give SwiftData a tick to register the insert before we navigate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            onTripCreated?(trip)
            viewModel.reset()
            dismiss()
        }
    }
}

// MARK: - Field Focus Enum

private enum Field: Hashable {
    case destination
    case tripName
}

// MARK: - Step 1: Where Are You Going?

private struct StepOneView: View {

    @Bindable var viewModel: TripCreationViewModel
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {

                // Otis illustration
                OtisIllustration(tripType: viewModel.selectedTripType)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.sm)

                // Heading
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Where are you headed?")
                        .font(.otisTitle)
                        .foregroundStyle(Color.otisSlate)

                    Text("Tell Otis where you're going so he can help you pack perfectly.")
                        .font(.otisBody)
                        .foregroundStyle(Color.otisSlate.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.md)

                // Destination field
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("DESTINATION")
                        .font(.otisOverline)
                        .foregroundStyle(Color.otisSlate.opacity(0.5))
                        .padding(.horizontal, Theme.Spacing.md)

                    TextField("e.g. Tokyo, Japan", text: $viewModel.destination)
                        .font(.otisHeadline)
                        .foregroundStyle(Color.otisSlate)
                        .padding(Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(Color.white)
                                .shadow(
                                    color: Color.otisSlate.opacity(0.08),
                                    radius: 8, x: 0, y: 2
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(
                                    focusedField.wrappedValue == .destination
                                        ? Color.otisTeal
                                        : Color.otisSlate.opacity(0.12),
                                    lineWidth: focusedField.wrappedValue == .destination ? 2 : 1
                                )
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        .focused(focusedField, equals: .destination)
                        .submitLabel(.done)
                        .onSubmit { focusedField.wrappedValue = nil }
                        .accessibilityLabel("Destination city or country")
                        .animation(.easeInOut(duration: 0.15), value: focusedField.wrappedValue)
                }

                // Trip type picker
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("TRIP TYPE")
                        .font(.otisOverline)
                        .foregroundStyle(Color.otisSlate.opacity(0.5))
                        .padding(.horizontal, Theme.Spacing.md)

                    TripTypeChipRow(selectedTripType: $viewModel.selectedTripType)
                }

                Spacer(minLength: Theme.Spacing.xxl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focusedField.wrappedValue = .destination }
    }
}

// MARK: - Step 2: When?

private struct StepTwoView: View {

    @Bindable var viewModel: TripCreationViewModel
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {

                // Heading
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("When are you going?")
                        .font(.otisTitle)
                        .foregroundStyle(Color.otisSlate)
                        .padding(.top, Theme.Spacing.md)

                    Text("Otis uses your dates to nail timing and pack just the right amount.")
                        .font(.otisBody)
                        .foregroundStyle(Color.otisSlate.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.md)

                // Date card
                VStack(spacing: 0) {
                    // Departure
                    DatePickerRow(
                        label: "Departure",
                        icon: "airplane.departure",
                        date: $viewModel.departureDate,
                        range: Date.now...
                    ) {
                        viewModel.onDepartureDateChanged()
                    }

                    Divider()
                        .padding(.horizontal, Theme.Spacing.md)
                        .opacity(0.12)

                    // Return date toggle
                    Toggle(isOn: Binding(
                        get: { viewModel.hasReturnDate },
                        set: { _ in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                viewModel.toggleReturnDate()
                            }
                        }
                    )) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "airplane.arrival")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.otisTeal)
                                .frame(width: 22)

                            Text("Return Date")
                                .font(.otisBodyBold)
                                .foregroundStyle(Color.otisSlate)
                        }
                    }
                    .tint(Color.otisTeal)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                    .accessibilityLabel("Has return date")

                    // Return date picker (conditional)
                    if viewModel.hasReturnDate {
                        Divider()
                            .padding(.horizontal, Theme.Spacing.md)
                            .opacity(0.12)

                        DatePickerRow(
                            label: "Return",
                            icon: "arrow.uturn.backward",
                            date: Binding(
                                get: { viewModel.returnDate ?? viewModel.minimumReturnDate },
                                set: { viewModel.returnDate = $0 }
                            ),
                            range: viewModel.minimumReturnDate...
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .fill(Color.white)
                        .shadow(color: Color.otisSlate.opacity(0.08), radius: 12, x: 0, y: 3)
                )
                .padding(.horizontal, Theme.Spacing.md)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.hasReturnDate)

                // Night count badge
                if let label = viewModel.nightCountLabel {
                    NightCountBadge(label: label)
                        .padding(.horizontal, Theme.Spacing.md)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                // Quick pack nudge
                if viewModel.isQuickTrip {
                    QuickPackNudge()
                        .padding(.horizontal, Theme.Spacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: Theme.Spacing.xxl)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.nightCountLabel)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.isQuickTrip)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focusedField.wrappedValue = nil }
    }
}

// MARK: - Step 3: Name Your Trip

private struct StepThreeView: View {

    @Bindable var viewModel: TripCreationViewModel
    var focusedField: FocusState<Field?>.Binding

    private let maxNameLength = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {

                // Heading
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Name your adventure")
                        .font(.otisTitle)
                        .foregroundStyle(Color.otisSlate)
                        .padding(.top, Theme.Spacing.md)

                    Text("Give this trip a name you'll love looking back on.")
                        .font(.otisBody)
                        .foregroundStyle(Color.otisSlate.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.md)

                // Trip name field
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text("TRIP NAME")
                            .font(.otisOverline)
                            .foregroundStyle(Color.otisSlate.opacity(0.5))

                        Spacer()

                        // Character counter
                        Text("\(viewModel.tripName.count)/\(maxNameLength)")
                            .font(.otisOverline)
                            .foregroundStyle(
                                viewModel.tripName.count >= maxNameLength
                                    ? Color.otisCoral
                                    : Color.otisSlate.opacity(0.35)
                            )
                            .animation(.easeInOut(duration: 0.1), value: viewModel.tripName.count)
                    }
                    .padding(.horizontal, Theme.Spacing.md)

                    TextField(viewModel.tripNameSuggestion, text: $viewModel.tripName)
                        .font(.otisHeadline)
                        .foregroundStyle(Color.otisSlate)
                        .padding(Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(Color.white)
                                .shadow(
                                    color: Color.otisSlate.opacity(0.08),
                                    radius: 8, x: 0, y: 2
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .stroke(
                                    focusedField.wrappedValue == .tripName
                                        ? Color.otisTeal
                                        : Color.otisSlate.opacity(0.12),
                                    lineWidth: focusedField.wrappedValue == .tripName ? 2 : 1
                                )
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        .focused(focusedField, equals: .tripName)
                        .submitLabel(.done)
                        .onSubmit { focusedField.wrappedValue = nil }
                        .onChange(of: viewModel.tripName) { _, newValue in
                            // Enforce max length
                            if newValue.count > maxNameLength {
                                viewModel.tripName = String(newValue.prefix(maxNameLength))
                            }
                            viewModel.onTripNameEdited()
                        }
                        .accessibilityLabel("Trip name, \(viewModel.tripName.count) of \(maxNameLength) characters used")
                        .animation(.easeInOut(duration: 0.15), value: focusedField.wrappedValue)
                }

                // Summary card
                TripSummaryCard(viewModel: viewModel)
                    .padding(.horizontal, Theme.Spacing.md)

                Spacer(minLength: Theme.Spacing.xxl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Auto-focus the name field with a slight delay so the
            // step transition animation completes first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                focusedField.wrappedValue = .tripName
            }
        }
    }
}

// MARK: - Subviews

// MARK: OtisIllustration

/// Otis mascot illustration area. Shows "otis-calm" as the base image
/// (asset must exist in the project's asset catalog) with a TripType-specific
/// SF Symbol badge overlaid in the lower-right corner.
/// When no "otis-calm" asset is available, falls back to a teal circle avatar.
private struct OtisIllustration: View {

    let tripType: TripType

    @State private var badgeScale: CGFloat = 0.5
    @State private var badgeOpacity: Double = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Base Otis avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.otisTeal.opacity(0.15), Color.otisTeal.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                // Try to load the real asset; fall back to SF Symbol if unavailable
                Group {
                    if UIImage(named: "otis-calm") != nil {
                        Image("otis-calm")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "face.smiling.inverse")
                            .font(.system(size: 72))
                            .foregroundStyle(Color.otisTeal)
                    }
                }
            }

            // Trip type badge
            ZStack {
                Circle()
                    .fill(Color.otisCreame)
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.otisSlate.opacity(0.15), radius: 6, x: 0, y: 2)

                Image(systemName: tripType.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tripType.defaultStampColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(badgeScale)
            .opacity(badgeOpacity)
            .offset(x: 4, y: 4)
        }
        .frame(height: 160)
        .onAppear { animateBadgeIn() }
        .onChange(of: tripType) { _, _ in
            // Pop the badge out and back in on type change
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                badgeScale = 0.5
                badgeOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                animateBadgeIn()
            }
        }
        .accessibilityLabel("Otis the packing assistant, \(tripType.displayName) trip")
        .accessibilityHidden(true) // decorative
    }

    private func animateBadgeIn() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            badgeScale = 1.0
            badgeOpacity = 1.0
        }
    }
}

// MARK: DatePickerRow

private struct DatePickerRow: View {

    let label: String
    let icon: String
    @Binding var date: Date
    let range: PartialRangeFrom<Date>
    var onChange: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.otisTeal)
                .frame(width: 22)

            Text(label)
                .font(.otisBodyBold)
                .foregroundStyle(Color.otisSlate)

            Spacer()

            DatePicker(
                label,
                selection: $date,
                in: range,
                displayedComponents: .date
            )
            .labelsHidden()
            .tint(Color.otisTeal)
            .onChange(of: date) { _, _ in onChange?() }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) date")
    }
}

// MARK: NightCountBadge

private struct NightCountBadge: View {

    let label: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))

            Text(label)
                .font(.otisCaptionBold)
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.otisTeal)
        )
        .shadow(color: Color.otisTeal.opacity(0.35), radius: 8, x: 0, y: 3)
        .accessibilityLabel("\(label) trip duration")
    }
}

// MARK: QuickPackNudge

private struct QuickPackNudge: View {

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("⚡")
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick trip?")
                    .font(.otisBodyBold)
                    .foregroundStyle(Color.otisSlate)

                Text("Otis recommends our Quick Pack profile — minimal, optimised for speed.")
                    .font(.otisCaption)
                    .foregroundStyle(Color.otisSlate.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Color.otisGold.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.otisGold.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick trip tip: Otis recommends the Quick Pack profile for short trips.")
    }
}

// MARK: TripSummaryCard

/// Readonly summary of the trip shown at the bottom of Step 3 so the user
/// can confirm everything before tapping Create.
private struct TripSummaryCard: View {

    let viewModel: TripCreationViewModel

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dep = formatter.string(from: viewModel.departureDate)
        if viewModel.hasReturnDate, let ret = viewModel.returnDate {
            return "\(dep) – \(formatter.string(from: ret))"
        }
        return "\(dep) · One-way"
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryRow(
                icon: "mappin.circle.fill",
                label: "Destination",
                value: viewModel.destination.isEmpty ? "—" : viewModel.destination
            )
            Divider().padding(.horizontal, Theme.Spacing.md).opacity(0.12)
            summaryRow(
                icon: tripTypeIconName,
                label: "Trip Type",
                value: viewModel.selectedTripType.displayName
            )
            Divider().padding(.horizontal, Theme.Spacing.md).opacity(0.12)
            summaryRow(
                icon: "calendar",
                label: "Dates",
                value: dateRangeText
            )
            if let nights = viewModel.nightCountLabel {
                Divider().padding(.horizontal, Theme.Spacing.md).opacity(0.12)
                summaryRow(
                    icon: "moon.stars",
                    label: "Duration",
                    value: nights
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(Color.white)
                .shadow(color: Color.otisSlate.opacity(0.07), radius: 12, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trip summary: \(viewModel.selectedTripType.displayName) to \(viewModel.destination), \(dateRangeText)")
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.otisTeal)
                .frame(width: 20)

            Text(label)
                .font(.otisCaption)
                .foregroundStyle(Color.otisSlate.opacity(0.5))
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.otisBodyBold)
                .foregroundStyle(Color.otisSlate)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 12)
    }

    private var tripTypeIconName: String {
        viewModel.selectedTripType.icon
    }
}

// MARK: CreateTripButton

/// Full-width "Create Trip" CTA with spring haptic tap animation.
private struct CreateTripButton: View {

    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPressed = false
                }
                action()
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))

                Text("Create Trip")
                    .font(.otisBodyBold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.otisTeal, Color.otisTeal.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.otisTeal.opacity(0.45), radius: 12, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .accessibilityLabel("Create trip")
        .accessibilityHint("Creates your new trip and opens the packing list")
    }
}

// MARK: - Theme Radius Extension (if not already in Theme.swift)

// These are referenced above — add to Theme.swift if missing.
// Declared here as a fallback so this file compiles standalone.
private extension Theme {
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }
}

// MARK: - Preview

#Preview("Trip Creation — Light") {
    TripCreationView { trip in
        print("Trip created: \(trip.name)")
    }
    .modelContainer(for: [Trip.self, PackingItem.self, Stamp.self], inMemory: true)
}

#Preview("Trip Creation — Dark") {
    TripCreationView { trip in
        print("Trip created: \(trip.name)")
    }
    .modelContainer(for: [Trip.self, PackingItem.self, Stamp.self], inMemory: true)
    .preferredColorScheme(.dark)
}
