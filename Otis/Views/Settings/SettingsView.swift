// SettingsView.swift
// Otis — Settings screen
//
// Sections:
//   1. Subscription status + manage/restore
//   2. Notifications preference
//   3. Support (email, privacy policy, terms)
//   4. App version footer + Otis napping illustration

import SwiftUI
import RevenueCat

struct SettingsView: View {

    // MARK: - Environment

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    // MARK: - Local State

    @State private var isRestoring = false
    @State private var showingRestoreConfirmation = false
    @State private var showingPaywall = false
    @State private var notificationsEnabled = true

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.otisCreame.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {

                        // Otis napping — visible at top for free users, subtle footer feel
                        if !subscriptionManager.isPro {
                            otisNappingBanner
                        }

                        // 1. Subscription card
                        subscriptionSection

                        // 2. Preferences
                        preferencesSection

                        // 3. Support
                        supportSection

                        // 4. About / version footer
                        aboutSection

                        // Bottom padding for tab bar clearance
                        Spacer().frame(height: Theme.Spacing.xl)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingPaywall) {
                // P3: PaywallView will be inserted here
                PaywallPlaceholderView()
            }
            .alert("Purchases Restored", isPresented: $showingRestoreConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(subscriptionManager.isPro
                     ? "Your Otis Pro subscription has been restored."
                     : "No active subscription found. If you believe this is an error, contact support.")
            }
        }
    }

    // MARK: - Otis Napping Banner (free tier only)

    private var otisNappingBanner: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Otis napping illustration placeholder
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Color.otisMint.opacity(0.3))
                    .frame(width: 60, height: 60)

                Image("otis-napping")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .overlay {
                        if UIImage(named: "otis-napping") == nil {
                            Text("💤🦦")
                                .font(.system(size: 28))
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Otis is napping.")
                    .font(.otisBodyBold)
                    .foregroundStyle(.otisSlate)

                Text("Unlock Pro to wake him up and get AI packing suggestions.")
                    .font(.otisCaption)
                    .foregroundStyle(.otisSlateLight)
                    .lineLimit(2)
            }

            Spacer()

            Button("Unlock") {
                showingPaywall = true
            }
            .font(.otisCaptionBold)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(Capsule().fill(.otisTeal))
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(.white)
                .otisShadow(.card)
        )
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        SettingsSectionCard(title: "Subscription") {
            // Current plan row
            SettingsRow(
                icon: "crown.fill",
                iconColor: subscriptionManager.isPro ? .otisGold : .otisSlateLight,
                title: "Current Plan",
                trailing: {
                    Text(subscriptionManager.status.displayName)
                        .font(.otisBodyBold)
                        .foregroundStyle(subscriptionManager.isPro ? .otisGold : .otisSlate)
                }
            )

            Divider().padding(.horizontal, -Theme.Spacing.md)

            if subscriptionManager.isPro {
                // Manage subscription — opens system subscription management
                SettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .otisTeal,
                    title: "Manage Subscription",
                    chevron: true,
                    action: openSubscriptionManagement
                )

                Divider().padding(.horizontal, -Theme.Spacing.md)
            } else {
                // Upgrade CTA
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.otisGold)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.otisGold.opacity(0.12)))

                        Text("Upgrade to Otis Pro")
                            .font(.otisBodyBold)
                            .foregroundStyle(.otisSlate)

                        Spacer()

                        Text("$19.99/yr")
                            .font(.otisCaptionBold)
                            .foregroundStyle(.otisTeal)

                        Image(systemName: "chevron.right")
                            .font(.otisCaption)
                            .foregroundStyle(.otisSlateLight)
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.plain)

                Divider().padding(.horizontal, -Theme.Spacing.md)
            }

            // Restore purchases — required by App Store guidelines 3.1.1
            Button {
                Task { await restorePurchases() }
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.otisTeal)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.otisTeal.opacity(0.10)))

                    Text("Restore Purchases")
                        .font(.otisBody)
                        .foregroundStyle(.otisSlate)

                    Spacer()

                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)
            .accessibilityIdentifier("restorePurchasesButton")
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        SettingsSectionCard(title: "Preferences") {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.otisCoral)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.otisCoral.opacity(0.12)))

                Text("Travel Day Nudge")
                    .font(.otisBody)
                    .foregroundStyle(.otisSlate)

                Spacer()

                Toggle("", isOn: $notificationsEnabled)
                    .tint(.otisTeal)
                    .labelsHidden()
            }
            .padding(.vertical, Theme.Spacing.sm)

            if notificationsEnabled {
                Text("Otis will remind you 3 hours before departure. One notification, never more.")
                    .font(.otisCaption)
                    .foregroundStyle(.otisSlateLight)
                    .padding(.top, -Theme.Spacing.sm)
            }
        }
    }

    // MARK: - Support Section

    private var supportSection: some View {
        SettingsSectionCard(title: "Support") {
            // Email support
            SettingsLinkRow(
                icon: "envelope.fill",
                iconColor: .otisTeal,
                title: "Contact Support",
                url: URL(string: "mailto:\(AppConfig.supportEmail)")!
            )

            Divider().padding(.horizontal, -Theme.Spacing.md)

            // Privacy policy
            SettingsLinkRow(
                icon: "hand.raised.fill",
                iconColor: .otisSlate,
                title: "Privacy Policy",
                url: AppConfig.privacyPolicyURL
            )

            Divider().padding(.horizontal, -Theme.Spacing.md)

            // Terms
            SettingsLinkRow(
                icon: "doc.text.fill",
                iconColor: .otisSlate,
                title: "Terms of Service",
                url: AppConfig.termsOfServiceURL
            )
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Otis napping — footer illustration for Pro users
            if subscriptionManager.isPro {
                Image("otis-napping")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .overlay {
                        if UIImage(named: "otis-napping") == nil {
                            Text("🦦")
                                .font(.system(size: 44))
                        }
                    }
                    .opacity(0.6)
            }

            Text(AppConfig.appName)
                .font(.otisCaption)
                .foregroundStyle(.otisSlateLight)

            Text(AppConfig.versionString)
                .font(.otisCaption)
                .foregroundStyle(Color.otisSlateLight.opacity(0.6))

            Text("Made with care by Bouquet Garden 🌸")
                .font(.otisCaption)
                .foregroundStyle(Color.otisSlateLight.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Actions

    private func restorePurchases() async {
        isRestoring = true
        await subscriptionManager.restorePurchases()
        isRestoring = false
        showingRestoreConfirmation = true
    }

    private func openSubscriptionManagement() {
        // Opens the iOS subscription management screen in Settings
        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Reusable Settings Components

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(.otisOverline)
                .foregroundStyle(.otisSlateLight)
                .padding(.horizontal, Theme.Spacing.xs)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(.white)
                    .otisShadow(.card)
            )
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    var chevron: Bool = false
    var action: (() -> Void)? = nil
    let trailing: () -> Trailing

    init(
        icon: String,
        iconColor: Color,
        title: String,
        chevron: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.chevron = chevron
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(iconColor.opacity(0.12)))

                Text(title)
                    .font(.otisBody)
                    .foregroundStyle(.otisSlate)

                Spacer()

                trailing()

                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.otisCaption)
                        .foregroundStyle(.otisSlateLight)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// Convenience init with no trailing view
extension SettingsRow where Trailing == EmptyView {
    init(
        icon: String,
        iconColor: Color,
        title: String,
        chevron: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            chevron: chevron,
            action: action,
            trailing: { EmptyView() }
        )
    }
}

struct SettingsLinkRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(iconColor.opacity(0.12)))

                Text(title)
                    .font(.otisBody)
                    .foregroundStyle(.otisSlate)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.otisCaption)
                    .foregroundStyle(.otisSlateLight)
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paywall Placeholder (P3 replaces with full RevenueCat paywall)

struct PaywallPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Text("✨")
                    .font(.system(size: 64))

                Text("Otis Pro")
                    .font(.otisDisplay)
                    .foregroundStyle(.otisSlate)

                Text("Full paywall UI coming in P3.\nRevenueCat integration, First Trip Free mechanic, and pricing cards.")
                    .font(.otisBody)
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)

                Button("Dismiss") { dismiss() }
                    .buttonStyle(.otisPrimary)
                    .padding(.horizontal, Theme.Spacing.xl)

                Spacer()
            }
            .otisBackground()
            .navigationTitle("Upgrade")
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

// MARK: - Preview

#Preview("Free Tier") {
    SettingsView()
        .environmentObject(SubscriptionManager())
}

#Preview("Pro Tier") {
    let manager = SubscriptionManager()
    // Note: in a real preview, RevenueCat status comes from sandbox.
    // The manager defaults to .free; in the Xcode preview canvas, use
    // a mock subclass or environment override for Pro preview.
    return SettingsView()
        .environmentObject(manager)
}
