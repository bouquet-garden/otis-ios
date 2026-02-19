// PaywallView.swift
// Otis — Views/Paywall/
//
// The primary monetization surface. Shown as a sheet in two scenarios:
//   1. Soft paywall — after trip 1 completes (First Trip Free exhausted)
//   2. Hard paywall — user taps a Pro-gated feature (AI, stamps, sync)
//
// Design principle: "Never gate the beauty. Only gate the intelligence."
// The paywall sells by being warm and honest — not by using pressure patterns.
//
// Layout:
//   - Otis illustration (animated bounce on appear)
//   - Context note banner (hard paywall only)
//   - Headline + subheadline
//   - 3-item feature list
//   - Annual card (primary, teal border, "Most Popular")
//   - Lifetime card (secondary, coral accent)
//   - Primary CTA button
//   - Restore · Privacy · Terms links
//   - "Cancel anytime." micro-copy
//   - DEBUG sandbox banner
//
// App Store compliance:
//   - Restore Purchases always visible
//   - Privacy Policy and Terms links present
//   - "Cancel anytime" copy on subscription
//   - No interactiveDismissDisabled — user can always swipe away

import SwiftUI

// MARK: - PaywallView

struct PaywallView: View {

    // MARK: - Environment

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - ViewModel

    @State private var vm: PaywallViewModel

    // MARK: - Animation State

    @State private var otisBounceTrigger: Bool = false
    @State private var contentAppeared: Bool = false

    // MARK: - Init

    /// - Parameter context: Why the paywall was shown. Drives copy + Otis state.
    init(context: PaywallViewModel.PaywallContext, subscriptionManager: SubscriptionManager) {
        _vm = State(initialValue: PaywallViewModel(
            subscriptionManager: subscriptionManager,
            context: context
        ))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Color.otisCreame.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {

                    // Dismiss button (soft / settings contexts)
                    if vm.context.isDismissible {
                        dismissBar
                    }

                    // DEBUG sandbox banner
                    #if DEBUG
                    sandboxBanner
                    #endif

                    // Context note (hard paywalls only)
                    if let note = vm.contextNote {
                        contextNoteBanner(note)
                    }

                    // Otis illustration
                    otisIllustration
                        .padding(.top, vm.contextNote != nil ? Theme.Spacing.md : Theme.Spacing.xl)

                    // Headline block
                    headlineBlock
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.lg)

                    // Feature list
                    featureList
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.lg)

                    // Pricing cards
                    pricingCards
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.lg)

                    // Primary CTA
                    primaryCTAButton
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.lg)

                    // Legal links row
                    legalLinks
                        .padding(.top, Theme.Spacing.md)

                    // Cancel anytime note
                    Text("Cancel anytime. No commitment.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Color.otisSlate.opacity(0.5))
                        .padding(.top, Theme.Spacing.xs)
                        .padding(.bottom, Theme.Spacing.xxl)
                }
            }

            // Restore success banner — floats at top
            if vm.showRestoreSuccess {
                restoreSuccessBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .alert("Purchase Error", isPresented: Binding(
            get: { vm.purchaseError != nil },
            set: { if !$0 { vm.purchaseError = nil } }
        )) {
            Button("Try Again") {
                vm.purchaseError = nil
            }
            Button("Cancel", role: .cancel) {
                vm.purchaseError = nil
            }
        } message: {
            if let err = vm.purchaseError {
                Text(err)
            }
        }
        .onChange(of: vm.purchaseSucceeded) { _, succeeded in
            if succeeded { dismiss() }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4)) {
                contentAppeared = true
            }
            // Start Otis bounce loop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                otisBounceTrigger = true
            }
        }
    }

    // MARK: - Dismiss Bar

    private var dismissBar: some View {
        HStack {
            Spacer()
            Button(vm.context.dismissLabel) {
                dismiss()
            }
            .font(Theme.Typography.subheadline.weight(.medium))
            .foregroundStyle(Color.otisSlate.opacity(0.6))
            .padding(.trailing, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
        }
    }

    // MARK: - Sandbox Banner

    #if DEBUG
    private var sandboxBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "testtube.2")
                .font(.caption2)
            Text("Sandbox Mode — Purchases are free")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.85), in: Capsule())
        .padding(.top, Theme.Spacing.sm)
    }
    #endif

    // MARK: - Context Note Banner

    private func contextNoteBanner(_ note: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.otisCoral)
            Text(note)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Color.otisCoral)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color.otisCoral.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .opacity(contentAppeared ? 1 : 0)
    }

    // MARK: - Otis Illustration

    private var otisIllustration: some View {
        ZStack {
            // Soft glow behind Otis
            Circle()
                .fill(Color.otisTeal.opacity(0.08))
                .frame(width: 180, height: 180)

            // Otis mascot — swap based on context
            Group {
                if vm.otisState == .napping {
                    // Soft paywall: sleeping Otis with speech bubble
                    sleepingOtisView
                } else {
                    // Hard / settings: excited Otis holding passport + checklist
                    activeOtisView
                }
            }
        }
        // Gentle perpetual bounce
        .offset(y: otisBounceTrigger ? -6 : 0)
        .animation(
            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
            value: otisBounceTrigger
        )
        .opacity(contentAppeared ? 1 : 0)
        .scaleEffect(contentAppeared ? 1 : 0.8)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: contentAppeared)
    }

    /// Active Otis: bold otter emoji + passport + checklist prop icons.
    private var activeOtisView: some View {
        VStack(spacing: 4) {
            ZStack {
                // Main character
                Text("🦦")
                    .font(.system(size: 90))

                // Passport prop (top-right)
                Text("📘")
                    .font(.system(size: 32))
                    .offset(x: 44, y: -20)
                    .rotationEffect(.degrees(15))

                // Checklist prop (bottom-left)
                Text("📋")
                    .font(.system(size: 28))
                    .offset(x: -42, y: 18)
                    .rotationEffect(.degrees(-10))
            }
            .frame(width: 140, height: 120)
        }
    }

    /// Napping Otis: sleepy otter + speech bubble asking to continue.
    private var sleepingOtisView: some View {
        VStack(spacing: 0) {
            // Speech bubble
            speechBubble("Wake me up for\nyour next trip?")
                .offset(y: 8)

            ZStack {
                Text("🦦")
                    .font(.system(size: 90))
                // Z Z Z floating up
                Text("z z z")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.otisTeal.opacity(0.7))
                    .offset(x: 46, y: -28)
                    .rotationEffect(.degrees(-10))
            }
        }
    }

    private func speechBubble(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption.weight(.medium))
            .foregroundStyle(Color.otisSlate)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Color.white)
                    .shadow(color: Color.otisSlate.opacity(0.15), radius: 6, y: 3)
            )
            .overlay(alignment: .bottom) {
                // Triangle pointer
                Triangle()
                    .fill(Color.white)
                    .frame(width: 14, height: 8)
                    .offset(y: 8)
            }
    }

    // MARK: - Headline Block

    private var headlineBlock: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(vm.headline)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.otisSlate)
                .multilineTextAlignment(.center)

            Text(vm.subheadline)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Color.otisSlate.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .opacity(contentAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.1), value: contentAppeared)
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: Theme.Spacing.md) {
            FeatureRow(
                icon: "sparkles",
                iconColor: Color.otisTeal,
                title: "AI packing suggestions",
                detail: "Otis thinks for you"
            )
            FeatureRow(
                icon: "book.closed.fill",
                iconColor: Color.otisGold,
                title: "Passport stamps",
                detail: "Collect every trip"
            )
            FeatureRow(
                icon: "icloud.fill",
                iconColor: Color(hex: "5B6FD4"),
                title: "iCloud sync",
                detail: "Your lists, everywhere"
            )
        }
        .padding(Theme.Spacing.md)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .opacity(contentAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.15), value: contentAppeared)
    }

    // MARK: - Pricing Cards

    private var pricingCards: some View {
        VStack(spacing: Theme.Spacing.md) {
            annualCard
            lifetimeCard
        }
        .opacity(contentAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.2), value: contentAppeared)
    }

    // Annual — PRIMARY card
    private var annualCard: some View {
        Button {
            Task { await vm.purchaseAnnual() }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    // "Most Popular" badge
                    Text("Most Popular")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.otisTeal, in: Capsule())

                    Spacer()

                    // Trial pill — only shown if RevenueCat confirms eligibility
                    if vm.isTrialEligible {
                        Text("7-day free trial")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.otisSlate)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.otisGold.opacity(0.85), in: Capsule())
                    }
                }

                Text(vm.annualPriceString)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.otisSlate)

                Text(vm.annualMonthlyBreakdown)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.otisSlate.opacity(0.6))
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Color.otisTeal, lineWidth: 2.5)
            )
            .otisShadow(.card)
        }
        .buttonStyle(.plain)
        .disabled(vm.isPurchasing)
    }

    // Lifetime — SECONDARY card
    private var lifetimeCard: some View {
        Button {
            Task { await vm.purchaseLifetime() }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Lifetime")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.otisCoral)

                    Spacer()

                    // "Best value" badge for power users (2+ trips)
                    if vm.showBestValueBadge {
                        Text("Best Value")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.otisCoral, in: Capsule())
                    }
                }

                Text(vm.lifetimePriceString)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.otisSlate)

                Text("Own it forever — no renewals")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.otisSlate.opacity(0.6))
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Color.otisCoral.opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isPurchasing)
    }

    // MARK: - Primary CTA Button

    private var primaryCTAButton: some View {
        Button {
            Task { await vm.purchaseAnnual() }
        } label: {
            ZStack {
                if vm.isPurchasing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                } else {
                    Text(vm.primaryCTATitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                vm.isPurchasing ? Color.otisTeal.opacity(0.6) : Color.otisTeal,
                in: RoundedRectangle(cornerRadius: Theme.Radius.pill)
            )
        }
        .buttonStyle(.plain)
        .disabled(vm.isPurchasing)
        .opacity(contentAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.25), value: contentAppeared)
    }

    // MARK: - Legal Links

    private var legalLinks: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button("Restore Purchases") {
                Task { await vm.restorePurchases() }
            }
            .disabled(vm.isPurchasing)

            Text("·")

            Link("Privacy Policy", destination: URL(string: "https://yourapp.com/privacy")!)

            Text("·")

            Link("Terms", destination: URL(string: "https://yourapp.com/terms")!)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Color.otisSlate.opacity(0.5))
        .multilineTextAlignment(.center)
    }

    // MARK: - Restore Success Banner

    private var restoreSuccessBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.otisTeal)
            Text("Purchases restored!")
                .font(Theme.Typography.subheadline.weight(.semibold))
                .foregroundStyle(Color.otisSlate)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .otisShadow(.card)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Icon container
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Color.otisSlate)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.otisSlate.opacity(0.6))
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.otisTeal)
        }
    }
}

// MARK: - Triangle Shape (speech bubble pointer)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview("Soft Paywall — Post Trip") {
    let sm = SubscriptionManager()
    PaywallView(context: .softPostTrip, subscriptionManager: sm)
        .environmentObject(sm)
}

#Preview("Hard Paywall — AI Suggestions") {
    let sm = SubscriptionManager()
    PaywallView(context: .hardAISuggestions, subscriptionManager: sm)
        .environmentObject(sm)
}

#Preview("Hard Paywall — Stamps") {
    let sm = SubscriptionManager()
    PaywallView(context: .hardStamps, subscriptionManager: sm)
        .environmentObject(sm)
}

#Preview("Settings Paywall") {
    let sm = SubscriptionManager()
    PaywallView(context: .settings, subscriptionManager: sm)
        .environmentObject(sm)
}
