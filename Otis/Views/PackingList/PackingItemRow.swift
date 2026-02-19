// PackingItemRow.swift
// Otis — Views/PackingList/
//
// Individual packing list item row. Features:
//   - Custom animated checkbox: circle outline → teal fill + checkmark path
//   - Left-to-right strikethrough that draws itself on check
//   - AI badge ("✦ Otis") on isAISuggested items
//   - Swipe-to-delete (trailing red trash)
//   - Long-press context menu: Rename, Move Category, Delete
//   - All animations spring-based, never linear
//
// Usage:
//   PackingItemRow(
//       item: packingItem,
//       onToggle: { vm.toggleItem(item) },
//       onDelete: { vm.deleteItem(item, modelContext: ctx) },
//       onRename: { vm.renameItem(item, newName: $0) },
//       onMoveCategory: { vm.moveItem(item, to: $0) }
//   )

import SwiftUI

// MARK: - PackingItemRow

struct PackingItemRow: View {

    // MARK: - Parameters

    let item: PackingItem
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onMoveCategory: (ItemCategory) -> Void

    // MARK: - Private State

    /// Controls the rename inline sheet.
    @State private var showRenameField: Bool = false
    @State private var renameText: String = ""

    /// Drives the row appear animation.
    @State private var appeared: Bool = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Animated checkbox
            AnimatedCheckbox(isPacked: item.isPacked, onToggle: onToggle)
                .frame(width: 26, height: 26)
                .accessibilityLabel(item.isPacked ? "Packed" : "Not packed")
                .accessibilityHint("Double tap to toggle")
                .accessibilityAddTraits(item.isPacked ? [.isButton, .isSelected] : .isButton)

            // Item name + strikethrough + AI badge
            itemNameStack

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -8)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75).delay(0.05)) {
                appeared = true
            }
        }
        // Swipe to delete
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .tint(.otisCoral)
        }
        // Long-press context menu
        .contextMenu {
            Button {
                renameText = item.name
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showRenameField = true
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Menu {
                ForEach(ItemCategory.allCases.filter { $0 != item.category }) { cat in
                    Button {
                        onMoveCategory(cat)
                    } label: {
                        Label(cat.displayName, systemImage: cat.icon)
                    }
                }
            } label: {
                Label("Move to Category", systemImage: "folder")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        // Inline rename sheet (alert-style for simplicity, keeps keyboard behaviour)
        .alert("Rename Item", isPresented: $showRenameField) {
            TextField("Item name", text: $renameText)
                .autocorrectionDisabled(false)

            Button("Save") {
                onRename(renameText)
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Name + Badge Stack

    private var itemNameStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Item name with animated strikethrough
                StrikethroughText(
                    text: item.name,
                    isPacked: item.isPacked
                )

                // AI badge
                if item.isAISuggested {
                    AIBadge()
                }
            }
        }
    }
}

// MARK: - AnimatedCheckbox

/// Custom circle checkbox that animates to a teal fill with a drawn checkmark.
private struct AnimatedCheckbox: View {

    let isPacked: Bool
    let onToggle: () -> Void

    /// 0 → 1 drives the checkmark path draw-on animation.
    @State private var checkmarkProgress: Double = 0
    /// Drives the fill scale pop.
    @State private var fillScale: Double = 1.0

    var body: some View {
        ZStack {
            // Background fill circle (scales in on check)
            Circle()
                .fill(isPacked ? Color.otisTeal : Color.clear)
                .scaleEffect(fillScale)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPacked)

            // Outline circle (fades out when packed)
            Circle()
                .stroke(
                    isPacked ? Color.otisTeal : Color.otisSlate.opacity(0.3),
                    lineWidth: isPacked ? 0 : 1.5
                )
                .animation(.easeOut(duration: 0.15), value: isPacked)

            // Checkmark drawn via trimmed path
            CheckmarkShape()
                .trim(from: 0, to: isPacked ? 1 : 0)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .padding(6)
                .animation(
                    isPacked
                        ? .spring(response: 0.3, dampingFraction: 0.65).delay(0.05)
                        : .spring(response: 0.2, dampingFraction: 0.7),
                    value: isPacked
                )
        }
        .onTapGesture {
            // Pop scale effect on tap
            withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                fillScale = 1.15
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    fillScale = 1.0
                }
            }
            onToggle()
        }
    }
}

// MARK: - CheckmarkShape

/// A checkmark path that renders within a unit rectangle.
/// Use `.trim(from:to:)` to animate the draw-on effect.
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Left leg: from bottom-left going up to mid
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

// MARK: - StrikethroughText

/// Text that animates a strikethrough line drawing left-to-right when isPacked
/// transitions to true. Uses a GeometryReader overlay to draw the line.
private struct StrikethroughText: View {

    let text: String
    let isPacked: Bool

    /// 0 → 1 drives the strikethrough width animation.
    @State private var strikeWidth: Double = 0

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .foregroundStyle(isPacked ? Color.otisSlate.opacity(0.5) : Color.otisSlate)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPacked)
            .overlay(
                GeometryReader { geo in
                    // Draw the strikethrough line
                    Path { path in
                        let y = geo.size.height * 0.52
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width * strikeWidth, y: y))
                    }
                    .stroke(
                        Color.otisSlate.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                    )
                }
            )
            .onChange(of: isPacked) { _, newValue in
                if newValue {
                    // Draw strikethrough left to right
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8).delay(0.1)) {
                        strikeWidth = 1.0
                    }
                } else {
                    // Erase instantly on uncheck
                    strikeWidth = 0
                }
            }
            .onAppear {
                // Restore state on appear (e.g. list scroll recycle)
                strikeWidth = isPacked ? 1.0 : 0
            }
    }
}

// MARK: - AIBadge

/// Small teal pill badge shown on AI-suggested items.
private struct AIBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Text("✦")
                .font(.system(size: 8, weight: .bold))
            Text("Otis")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.otisTeal)
        )
        .accessibilityLabel("AI suggested by Otis")
    }
}

// MARK: - Preview

#Preview("Packing Item Rows") {
    let unpacked = PackingItem(
        name: "Passport",
        category: .documents,
        isPacked: false,
        isAISuggested: false,
        sortOrder: 0
    )
    let packed = PackingItem(
        name: "Sunscreen SPF 50",
        category: .toiletries,
        isPacked: true,
        isAISuggested: true,
        sortOrder: 1
    )
    let aiItem = PackingItem(
        name: "Universal power adapter",
        category: .electronics,
        isPacked: false,
        isAISuggested: true,
        sortOrder: 2
    )

    return VStack(spacing: 0) {
        Divider()
        PackingItemRow(
            item: unpacked,
            onToggle: {},
            onDelete: {},
            onRename: { _ in },
            onMoveCategory: { _ in }
        )
        Divider().padding(.leading, 54)
        PackingItemRow(
            item: packed,
            onToggle: {},
            onDelete: {},
            onRename: { _ in },
            onMoveCategory: { _ in }
        )
        Divider().padding(.leading, 54)
        PackingItemRow(
            item: aiItem,
            onToggle: {},
            onDelete: {},
            onRename: { _ in },
            onMoveCategory: { _ in }
        )
        Divider()
    }
    .background(Color.otisCreame)
}
