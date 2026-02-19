// TripTypeChip.swift
// Otis — Views/TripCreation/
//
// Reusable pill chip representing a single TripType in the horizontal
// selection row. Taps toggle selection state with spring animation.
//
// Visual states:
//   Unselected — otisCreame fill, otisSlate 1pt border, slate text+icon
//   Selected   — otisTeal fill, white text+icon, teal shadow
//              — iOS 26+: .glassEffect(.regular, in: .capsule) overlay
//
// Usage:
//   TripTypeChip(tripType: .beach, isSelected: vm.selectedTripType == .beach) {
//       vm.selectedTripType = .beach
//   }

import SwiftUI

// MARK: - TripTypeChip

struct TripTypeChip: View {

    let tripType: TripType
    let isSelected: Bool
    let action: () -> Void

    /// Tracks the press-down state for the scale feedback micro-animation.
    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: handleTap) {
            chipContent
        }
        .buttonStyle(.plain)
        // Press scale feedback
        .scaleEffect(isPressed ? 0.93 : (isSelected ? 1.03 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        // Capture press gesture for tactile scale without interfering with the Button action
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .accessibilityLabel("\(tripType.displayName) trip type")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select")
    }

    // MARK: - Chip Content

    @ViewBuilder
    private var chipContent: some View {
        if #available(iOS 26, *) {
            glassChipContent
        } else {
            legacyChipContent
        }
    }

    // MARK: - iOS 26 Glass Variant

    @available(iOS 26, *)
    private var glassChipContent: some View {
        HStack(spacing: 6) {
            Image(systemName: tripType.icon)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(tripType.displayName)
                .font(.otisCaptionBold)
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.white : Color.otisSlate)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // Glass effect when selected — identity variant (no glass) when unselected
        // to avoid costly view hierarchy rebuilds
        .glassEffect(
            isSelected ? .regular : .identity,
            in: .capsule
        )
        // Teal tint under the glass on the selected state
        .background(
            Capsule()
                .fill(isSelected ? Color.otisTeal : Color.otisCreame)
        )
        // For unselected state, show the border on top of the cream fill
        .overlay(
            Capsule()
                .stroke(
                    isSelected ? Color.clear : Color.otisSlate.opacity(0.25),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isSelected ? Color.otisTeal.opacity(0.35) : .clear,
            radius: 8, x: 0, y: 3
        )
    }

    // MARK: - iOS 17 Legacy Variant

    private var legacyChipContent: some View {
        HStack(spacing: 6) {
            Image(systemName: tripType.icon)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(tripType.displayName)
                .font(.otisCaptionBold)
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.white : Color.otisSlate)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(isSelected ? Color.otisTeal : Color.otisCreame)
        )
        .overlay(
            Capsule()
                .stroke(
                    isSelected ? Color.clear : Color.otisSlate.opacity(0.25),
                    lineWidth: 1
                )
        )
        .shadow(
            color: isSelected ? Color.otisTeal.opacity(0.3) : Color.otisSlate.opacity(0.08),
            radius: isSelected ? 8 : 2,
            x: 0,
            y: isSelected ? 3 : 1
        )
    }

    // MARK: - Actions

    private func handleTap() {
        isPressed = false
        action()
        // Haptic feedback — selection changed
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

// MARK: - TripTypeChipRow

/// Horizontally scrolling row of all TripType chips. Used in Step 0
/// of TripCreationView. Drives selection through a binding to TripType.
struct TripTypeChipRow: View {

    @Binding var selectedTripType: TripType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(TripType.allCases) { tripType in
                    TripTypeChip(
                        tripType: tripType,
                        isSelected: selectedTripType == tripType
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedTripType = tripType
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
        // Clip so shadow is visible but scrollview doesn't cut it
        .padding(.vertical, -Theme.Spacing.xs)
    }
}

// MARK: - Preview

#Preview("Trip Type Chips") {
    @Previewable @State var selected: TripType = .beach

    VStack(spacing: Theme.Spacing.xl) {
        // Full scrollable row
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TRIP TYPE")
                .font(.otisOverline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.md)

            TripTypeChipRow(selectedTripType: $selected)
        }

        // Individual chip states
        HStack(spacing: Theme.Spacing.sm) {
            TripTypeChip(tripType: .beach, isSelected: false) { }
            TripTypeChip(tripType: .ski,   isSelected: true)  { }
        }
    }
    .padding(.vertical, Theme.Spacing.xl)
    .background(Color.otisCreame)
}
