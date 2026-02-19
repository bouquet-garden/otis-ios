// SubscriptionBadge.swift
// Otis — Views/Paywall/
//
// Small reusable badge that displays the user's current subscription tier.
// Used in SettingsView on the subscription row, and anywhere else the tier
// should be surfaced at a glance.
//
// Variants:
//   .free      — slate gray pill  "Free"
//   .proAnnual — otisTeal pill    "Pro ✦"  with sparkles icon
//   .lifetime  — otisGold pill    "Lifetime ✦"
//
// Size variants: .small (caption), .regular (subheadline), .large (body)
//
// Usage:
//   SubscriptionBadge(status: subscriptionManager.subscriptionStatus)
//   SubscriptionBadge(status: .proAnnual, size: .large)

import SwiftUI

// MARK: - SubscriptionBadge

struct SubscriptionBadge: View {

    // MARK: - Types

    enum BadgeSize {
        case small    // used inside list rows, compact contexts
        case regular  // default
        case large    // settings hero row

        var font: Font {
            switch self {
            case .small:   return .system(size: 11, weight: .bold, design: .rounded)
            case .regular: return .system(size: 12, weight: .bold, design: .rounded)
            case .large:   return .system(size: 14, weight: .bold, design: .rounded)
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small:   return 9
            case .regular: return 10
            case .large:   return 12
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small:   return 8
            case .regular: return 10
            case .large:   return 14
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small:   return 3
            case .regular: return 4
            case .large:   return 6
            }
        }
    }

    // MARK: - Properties

    let status: UserSubscriptionStatus
    var size: BadgeSize = .regular

    // MARK: - Computed

    private var config: BadgeConfig {
        switch status {
        case .free:
            return BadgeConfig(
                label: "Free",
                icon: nil,
                foreground: .white,
                background: Color.otisSlate.opacity(0.45)
            )
        case .proAnnual:
            return BadgeConfig(
                label: "Pro",
                icon: "sparkles",
                foreground: .white,
                background: Color.otisTeal
            )
        case .lifetime:
            return BadgeConfig(
                label: "Lifetime",
                icon: "star.fill",
                foreground: Color.otisSlate,
                background: Color.otisGold
            )
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            if let icon = config.icon {
                Image(systemName: icon)
                    .font(.system(size: size.iconSize, weight: .bold))
                    .foregroundStyle(config.foreground)
            }

            Text(config.label)
                .font(size.font)
                .foregroundStyle(config.foreground)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(config.background, in: Capsule())
    }

    // MARK: - BadgeConfig

    private struct BadgeConfig {
        let label: String
        let icon: String?
        let foreground: Color
        let background: Color
    }
}

// MARK: - SubscriptionStatusRow
// A full settings row combining label, current plan description, and badge.
// Drop-in for SettingsView's subscription section.

struct SubscriptionStatusRow: View {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showingPaywall: Bool = false

    var body: some View {
        Button {
            if !subscriptionManager.isPro {
                showingPaywall = true
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconBackground)
                        .frame(width: 32, height: 32)
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Color.otisSlate)
                    Text(planDescription)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.otisSlate.opacity(0.55))
                }

                Spacer()

                // Badge + chevron
                HStack(spacing: Theme.Spacing.sm) {
                    SubscriptionBadge(status: subscriptionManager.subscriptionStatus)
                    if !subscriptionManager.isPro {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.otisSlate.opacity(0.35))
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(
                context: .settings,
                subscriptionManager: subscriptionManager
            )
            .environmentObject(subscriptionManager)
        }
    }

    // MARK: - Helpers

    private var planDescription: String {
        switch subscriptionManager.subscriptionStatus {
        case .free:
            return "Manual lists only · Tap to upgrade"
        case .proAnnual:
            return "AI suggestions · Stamps · iCloud sync"
        case .lifetime:
            return "All features · Forever"
        }
    }

    private var iconName: String {
        switch subscriptionManager.subscriptionStatus {
        case .free:     return "lock.fill"
        case .proAnnual: return "sparkles"
        case .lifetime:  return "star.fill"
        }
    }

    private var iconBackground: Color {
        switch subscriptionManager.subscriptionStatus {
        case .free:      return Color.otisSlate.opacity(0.5)
        case .proAnnual: return Color.otisTeal
        case .lifetime:  return Color.otisGold
        }
    }
}

// MARK: - FirstTripFreeBanner
// Shown in SettingsView (and optionally TripListView) when the First Trip Free
// mechanic is active — communicates remaining trial value without pressure.

struct FirstTripFreeBanner: View {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var body: some View {
        if subscriptionManager.isFirstTripFree {
            HStack(spacing: Theme.Spacing.sm) {
                Text("🎉")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("First Trip Free!")
                        .font(Theme.Typography.body.weight(.bold))
                        .foregroundStyle(Color.otisSlate)
                    Text("You have full Pro access for this trip. Enjoy!")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.otisSlate.opacity(0.65))
                }

                Spacer()

                SubscriptionBadge(status: .proAnnual, size: .small)
            }
            .padding(Theme.Spacing.md)
            .background(Color.otisTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Color.otisTeal.opacity(0.25), lineWidth: 1)
            )
        }
    }
}

// MARK: - Preview

#Preview("Badge Variants") {
    VStack(spacing: 20) {
        HStack(spacing: 12) {
            SubscriptionBadge(status: .free, size: .small)
            SubscriptionBadge(status: .proAnnual, size: .small)
            SubscriptionBadge(status: .lifetime, size: .small)
        }
        HStack(spacing: 12) {
            SubscriptionBadge(status: .free)
            SubscriptionBadge(status: .proAnnual)
            SubscriptionBadge(status: .lifetime)
        }
        HStack(spacing: 12) {
            SubscriptionBadge(status: .free, size: .large)
            SubscriptionBadge(status: .proAnnual, size: .large)
            SubscriptionBadge(status: .lifetime, size: .large)
        }
    }
    .padding()
    .background(Color.otisCreame)
}

#Preview("Status Row — Free") {
    let sm = SubscriptionManager()
    List {
        SubscriptionStatusRow()
            .environmentObject(sm)
    }
}

#Preview("Status Row — Pro") {
    let sm = SubscriptionManager()
    // sm.subscriptionStatus = .proAnnual  // set in debug builds
    List {
        SubscriptionStatusRow()
            .environmentObject(sm)
    }
}

#Preview("First Trip Free Banner") {
    let sm = SubscriptionManager()
    FirstTripFreeBanner()
        .environmentObject(sm)
        .padding()
        .background(Color.otisCreame)
}
