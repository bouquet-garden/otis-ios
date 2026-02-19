// SuggestionCard.swift
// Otis — Views/AISuggestions/SuggestionCard.swift
//
// Reusable suggestion card component. Self-contained — owns its own
// press state and checkbox animation. The parent (AISuggestionsView)
// drives isAccepted from the ViewModel; this card fires onToggle and
// lets the parent mutate state.
//
// Visual hierarchy (top to bottom):
//   [Priority badge]  [Category chip]          [Animated checkbox]
//   Item name (semibold, slate)
//   Reason text (secondary, italic — the "magic" detail)
//
// States:
//   Unselected  — white/cream card, empty circle checkbox
//   Selected    — otisTeal.opacity(0.08) tint, filled teal checkmark
//   Pressed     — scaleEffect(0.97) spring pop
//
// iOS 26+: selected card gets subtle .glassEffect on its shape.
// iOS 17–25: selected state uses tinted background fill.
//
// Accessibility:
//   - Single accessibilityLabel combining name + reason + priority
//   - accessibilityHint for the toggle action
//   - accessibilityValue "selected" / "not selected"
//   - Minimum 44pt touch target enforced via .contentShape

import SwiftUI

// MARK: - SuggestionCard

struct SuggestionCard: View {

    // MARK: - Parameters

    let suggestion: PackingSuggestion
    let onToggle: () -> Void

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Private State

    @State private var isPressed: Bool = false

    // MARK: - Body

    var body: some View {
        Button(action: handleTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isPressed)
        // Accessibility
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to \(suggestion.isAccepted ? "remove from" : "add to") your list")
        .accessibilityValue(suggestion.isAccepted ? "selected" : "not selected")
        .accessibilityAddTraits(suggestion.isAccepted ? [.isButton, .isSelected] : .isButton)
        // Press gesture for scale feedback
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        if #available(iOS 26, *) {
            cardInner
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            suggestion.isAccepted ? Color.otisTeal.opacity(0.35) : Color.clear,
                            lineWidth: 1.5
                        )
                )
                // iOS 26: selected cards get a subtle glass shimmer
                .glassEffect(
                    suggestion.isAccepted ? .regular : .identity,
                    in: .rect(cornerRadius: 16),
                    isEnabled: suggestion.isAccepted
                )
        } else {
            cardInner
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            suggestion.isAccepted ? Color.otisTeal.opacity(0.35) : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
    }

    // MARK: - Card Inner Layout

    private var cardInner: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: text content column
            VStack(alignment: .leading, spacing: 8) {
                // Row 1: priority badge + category chip
                HStack(spacing: 6) {
                    PriorityBadge(priority: suggestion.priority)
                    CategoryChip(category: suggestion.category)
                    Spacer(minLength: 0)
                }

                // Row 2: item name
                Text(suggestion.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.otisSlate)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Row 3: reason text — the magic detail
                Text(suggestion.reason)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.otisSlate.opacity(0.65))
                    .italic()
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            // Right: animated checkbox
            SuggestionCheckbox(isAccepted: suggestion.isAccepted)
                .frame(width: 28, height: 28)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        // Ensure at least 44pt vertical touch target
        .frame(minHeight: 44)
    }

    // MARK: - Background

    private var cardBackground: Color {
        if suggestion.isAccepted {
            return Color.otisTeal.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }
        return colorScheme == .dark
            ? Color.otisSlate.opacity(0.25)
            : Color.white
    }

    // MARK: - Accessibility Label

    private var accessibilityLabel: String {
        "\(suggestion.name). \(suggestion.priority.displayName). \(suggestion.reason). Category: \(suggestion.category.displayName)."
    }

    // MARK: - Actions

    private func handleTap() {
        // Haptic before state change for immediacy
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onToggle()
    }
}

// MARK: - SuggestionCheckbox

/// Custom animated checkbox: empty circle → teal fill + drawn checkmark.
/// Mirrors the AnimatedCheckbox in PackingItemRow for visual consistency,
/// but uses otisTeal checkmark colour instead of white (for the card context).
private struct SuggestionCheckbox: View {

    let isAccepted: Bool

    @State private var fillScale: Double = 1.0

    var body: some View {
        ZStack {
            // Teal fill circle
            Circle()
                .fill(isAccepted ? Color.otisTeal : Color.clear)
                .scaleEffect(fillScale)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isAccepted)

            // Stroke outline — fades when accepted
            Circle()
                .stroke(
                    isAccepted ? Color.otisTeal : Color.otisSlate.opacity(0.28),
                    lineWidth: isAccepted ? 0 : 1.5
                )
                .animation(.easeOut(duration: 0.15), value: isAccepted)

            // Drawn checkmark path
            SuggestionCheckmarkShape()
                .trim(from: 0, to: isAccepted ? 1 : 0)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )
                .padding(6)
                .animation(
                    isAccepted
                        ? .spring(response: 0.3, dampingFraction: 0.65).delay(0.05)
                        : .spring(response: 0.2, dampingFraction: 0.7),
                    value: isAccepted
                )
        }
        .onChange(of: isAccepted) { _, newValue in
            if newValue {
                // Scale pop on select
                withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                    fillScale = 1.18
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        fillScale = 1.0
                    }
                }
            } else {
                fillScale = 1.0
            }
        }
    }
}

// MARK: - SuggestionCheckmarkShape

private struct SuggestionCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startX = rect.minX + rect.width * 0.15
        let startY = rect.midY + rect.height * 0.05
        let midX   = rect.minX + rect.width * 0.40
        let midY   = rect.maxY - rect.height * 0.12
        let endX   = rect.maxX - rect.width * 0.10
        let endY   = rect.minY + rect.height * 0.10
        path.move(to: CGPoint(x: startX, y: startY))
        path.addLine(to: CGPoint(x: midX, y: midY))
        path.addLine(to: CGPoint(x: endX, y: endY))
        return path
    }
}

// MARK: - PriorityBadge

/// Small coloured pill: "Essential" (coral), "Recommended" (teal), "Nice" (gold).
struct PriorityBadge: View {

    let priority: SuggestionPriority

    var body: some View {
        Text(priority.displayName)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(badgeColor)
            )
    }

    private var badgeColor: Color {
        switch priority {
        case .essential:   return .otisCoral
        case .recommended: return .otisTeal
        case .niceToHave:  return .otisGold
        }
    }
}

// MARK: - CategoryChip

/// Tiny chip with SF Symbol icon + category name on mint background.
struct CategoryChip: View {

    let category: ItemCategory

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(category.displayName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundStyle(Color.otisTeal)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.otisTeal.opacity(0.12))
        )
    }
}

// MARK: - Preview

#Preview("Suggestion Cards") {
    ScrollView {
        VStack(spacing: 12) {
            // Unselected essential
            SuggestionCard(
                suggestion: PackingSuggestion(
                    name: "Passport",
                    category: .documents,
                    reason: "Required for international entry — always carry-on, never checked.",
                    priority: .essential,
                    isAccepted: false
                ),
                onToggle: {}
            )

            // Selected recommended
            SuggestionCard(
                suggestion: PackingSuggestion(
                    name: "Sunscreen SPF 50",
                    category: .toiletries,
                    reason: "Bali's UV index is extreme year-round — reapply every 2 hours.",
                    priority: .recommended,
                    isAccepted: true
                ),
                onToggle: {}
            )

            // Unselected nice-to-have
            SuggestionCard(
                suggestion: PackingSuggestion(
                    name: "Portable white noise machine",
                    category: .essentials,
                    reason: "Gamelan music and roosters start early in Ubud.",
                    priority: .niceToHave,
                    isAccepted: false
                ),
                onToggle: {}
            )
        }
        .padding()
    }
    .background(Color.otisCreame)
}
