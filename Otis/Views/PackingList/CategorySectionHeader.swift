// CategorySectionHeader.swift
// Otis — Views/PackingList/
//
// Section header for the grouped packing list. Shows the category icon,
// name, and item count. Tapping collapses/expands the section with an
// animated chevron. When all items in the section are packed, the header
// dims and shows a green checkmark instead of the count badge.
//
// Usage:
//   CategorySectionHeader(
//       category: .clothing,
//       totalCount: 8,
//       packedCount: 8,
//       isCollapsed: false,
//       onTap: { vm.toggleCollapse(.clothing) }
//   )

import SwiftUI

// MARK: - CategorySectionHeader

struct CategorySectionHeader: View {

    // MARK: - Parameters

    let category: ItemCategory
    let totalCount: Int
    let packedCount: Int
    let isCollapsed: Bool
    let onTap: () -> Void

    // MARK: - Derived

    private var isAllPacked: Bool {
        totalCount > 0 && packedCount == totalCount
    }

    private var unpackedCount: Int {
        totalCount - packedCount
    }

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Category icon
                ZStack {
                    Circle()
                        .fill(isAllPacked ? Color.green.opacity(0.12) : Color.otisTeal.opacity(0.12))
                        .frame(width: 30, height: 30)

                    Image(systemName: isAllPacked ? "checkmark" : category.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isAllPacked ? .green : .otisTeal)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isAllPacked)

                // Category name
                Text(category.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isAllPacked ? .otisSlateLight : .otisSlate)
                    .animation(.easeInOut(duration: 0.2), value: isAllPacked)

                Spacer()

                // Item count badge or "all done" checkmark
                countBadge

                // Collapse chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.otisSlateLight)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isCollapsed)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.displayName) section, \(packedCount) of \(totalCount) packed")
        .accessibilityHint(isCollapsed ? "Double tap to expand" : "Double tap to collapse")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Count Badge

    @ViewBuilder
    private var countBadge: some View {
        if isAllPacked {
            // All done — show subtle "Done" label
            Text("Done")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.green.opacity(0.12))
                )
                .transition(.scale.combined(with: .opacity))
        } else {
            // Unpacked count badge
            Text("\(unpackedCount) left")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.otisSlateLight)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.otisSlate.opacity(0.08))
                )
                .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Preview

#Preview("Category Headers") {
    VStack(spacing: 0) {
        Divider()

        CategorySectionHeader(
            category: .clothing,
            totalCount: 8,
            packedCount: 3,
            isCollapsed: false,
            onTap: {}
        )
        Divider().padding(.leading, 56)

        CategorySectionHeader(
            category: .documents,
            totalCount: 3,
            packedCount: 3,
            isCollapsed: false,
            onTap: {}
        )
        Divider().padding(.leading, 56)

        CategorySectionHeader(
            category: .electronics,
            totalCount: 5,
            packedCount: 0,
            isCollapsed: true,
            onTap: {}
        )
        Divider()
    }
    .background(Color.otisCreame)
}
