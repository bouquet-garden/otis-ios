// ProFeatureGate.swift
// Otis — Views/Paywall/
//
// Reusable ViewModifier that intercepts taps on any view when the user is
// not a Pro subscriber, presenting the contextual PaywallView as a sheet.
//
// Usage:
//   Text("AI Suggestions")
//       .proGated(context: .hardAISuggestions)
//
//   // Or with explicit subscriptionManager (non-environment contexts):
//   Button("Stamps") { }
//       .proGated(context: .hardStamps, subscriptionManager: sm)
//
// Implementation notes:
//   - Uses a clear Color overlay + contentShape to intercept taps cleanly
//     without blocking accessibility or VoiceOver on the wrapped view.
//   - Pro users see the content and interact normally — zero overhead.
//   - The modifier NEVER prevents the underlying action for Pro users.
//   - A subtle "Pro" lock badge appears on gated views (opt-in via showLockBadge).

import SwiftUI

// MARK: - ProFeatureGate ViewModifier

struct ProFeatureGate: ViewModifier {

    // MARK: - Properties

    let context: PaywallViewModel.PaywallContext

    /// Set to false to suppress the lock badge overlay (e.g. on full-screen surfaces).
    var showLockBadge: Bool = true

    // MARK: - Environment

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    // MARK: - State

    @State private var showingPaywall: Bool = false

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            // Tap interception overlay — only active for Free users
            .overlay {
                if !subscriptionManager.isPro {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            showingPaywall = true
                        }
                }
            }
            // Lock badge — top-right corner, subtle
            .overlay(alignment: .topTrailing) {
                if !subscriptionManager.isPro && showLockBadge {
                    lockBadge
                        .padding(6)
                }
            }
            // Paywall sheet
            .sheet(isPresented: $showingPaywall) {
                PaywallView(
                    context: context,
                    subscriptionManager: subscriptionManager
                )
                .environmentObject(subscriptionManager)
            }
    }

    // MARK: - Lock Badge

    private var lockBadge: some View {
        ZStack {
            Circle()
                .fill(Color.otisSlate.opacity(0.75))
                .frame(width: 22, height: 22)
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - ProFeatureGateDirect
// Version that accepts an explicit subscriptionManager for non-environment contexts.

struct ProFeatureGateDirect: ViewModifier {

    let context: PaywallViewModel.PaywallContext
    let subscriptionManager: SubscriptionManager
    var showLockBadge: Bool = true

    @State private var showingPaywall: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !subscriptionManager.isPro {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            showingPaywall = true
                        }
                }
            }
            .overlay(alignment: .topTrailing) {
                if !subscriptionManager.isPro && showLockBadge {
                    ZStack {
                        Circle()
                            .fill(Color.otisSlate.opacity(0.75))
                            .frame(width: 22, height: 22)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(6)
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(
                    context: context,
                    subscriptionManager: subscriptionManager
                )
                .environmentObject(subscriptionManager)
            }
    }
}

// MARK: - View Extensions

extension View {

    /// Gate this view behind a Pro subscription check.
    /// Intercepts taps and presents the contextual paywall if user is Free.
    /// Reads SubscriptionManager from the environment.
    ///
    /// - Parameters:
    ///   - context: Why the paywall is being shown (drives copy + Otis state).
    ///   - showLockBadge: Whether to show the small lock icon overlay. Default true.
    func proGated(
        context: PaywallViewModel.PaywallContext,
        showLockBadge: Bool = true
    ) -> some View {
        modifier(ProFeatureGate(context: context, showLockBadge: showLockBadge))
    }

    /// Gate this view with an explicit SubscriptionManager (not from environment).
    /// Use this in contexts where EnvironmentObject injection is unavailable.
    func proGated(
        context: PaywallViewModel.PaywallContext,
        subscriptionManager: SubscriptionManager,
        showLockBadge: Bool = true
    ) -> some View {
        modifier(ProFeatureGateDirect(
            context: context,
            subscriptionManager: subscriptionManager,
            showLockBadge: showLockBadge
        ))
    }
}

// MARK: - ProBanner
// A full-width banner strip used in TripDetailView to surface the AI feature.
// Tapping it presents the paywall with .hardAISuggestions context.

struct ProBanner: View {

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showingPaywall: Bool = false
    @State private var isPressed: Bool = false

    var body: some View {
        if !subscriptionManager.isPro {
            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                showingPaywall = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.otisTeal)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Otis can suggest items for this trip")
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Color.otisSlate)
                        Text("Unlock AI suggestions with Pro")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Color.otisSlate.opacity(0.6))
                    }

                    Spacer()

                    // Pro pill
                    Text("Pro")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.otisTeal, in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.otisSlate.opacity(0.4))
                }
                .padding(Theme.Spacing.md)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Color.otisTeal.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .sheet(isPresented: $showingPaywall) {
                PaywallView(
                    context: .hardAISuggestions,
                    subscriptionManager: subscriptionManager
                )
                .environmentObject(subscriptionManager)
            }
        }
    }
}

// MARK: - Preview

#Preview("ProBanner") {
    let sm = SubscriptionManager()
    VStack {
        ProBanner()
            .environmentObject(sm)
            .padding()
        Spacer()
    }
    .background(Color.otisCreame)
}

#Preview("proGated modifier") {
    let sm = SubscriptionManager()

    VStack(spacing: 20) {
        // Gated card
        VStack(alignment: .leading) {
            Text("AI Suggestions")
                .font(.headline)
            Text("Pack smarter with AI")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .proGated(context: .hardAISuggestions, subscriptionManager: sm)
        .padding(.horizontal)
    }
    .background(Color.otisCreame)
    .environmentObject(sm)
}
