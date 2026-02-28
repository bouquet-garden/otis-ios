// OnboardingView.swift
// Otis — First-launch onboarding carousel
//
// Shown once via fullScreenCover from ContentView.
// Gate: UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
//
// 3 screens in a TabView(.page):
//   Screen 1 — Meet Otis (mascot wave animation)
//   Screen 2 — First trip hook (floating suitcase items)
//   Screen 3 — Passport/stamps (fan of stamp cards + "Let's go" CTA)
//
// Skip button always visible top-right on all screens.
// "Let's go" on screen 3 sets hasCompletedOnboarding = true and dismisses.

import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {

    // MARK: - Dismiss

    @Environment(\.dismiss) private var dismiss

    // MARK: - Page State

    @State private var currentPage: Int = 0

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background gradient (teal → cream, full screen)
            onboardingGradient
                .ignoresSafeArea()

            // Page carousel
            TabView(selection: $currentPage) {
                OnboardingPage1()
                    .tag(0)

                OnboardingPage2()
                    .tag(1)

                OnboardingPage3(onComplete: completeOnboarding)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .animation(.easeInOut(duration: 0.35), value: currentPage)

            // Skip button — always visible top-right
            Button {
                completeOnboarding()
            } label: {
                Text("Skip")
                    .font(.otisBody)
                    .foregroundStyle(.otisSlateLight)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .padding(.top, Theme.Spacing.lg)
            .padding(.trailing, Theme.Spacing.sm)
        }
    }

    // MARK: - Background

    private var onboardingGradient: some View {
        LinearGradient(
            colors: [
                Color.otisTeal.opacity(0.30),
                Color.otisCreame
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Actions

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismiss()
    }
}

// MARK: - Screen 1: Meet Otis

private struct OnboardingPage1: View {

    @State private var isWaving = false
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()

            // Otis mascot with repeating wave animation
            OtisMascotView(isWaving: isWaving)
                .frame(width: Theme.IconSize.otisHero, height: Theme.IconSize.otisHero)
                .scaleEffect(didAppear ? 1.0 : 0.6)
                .opacity(didAppear ? 1.0 : 0.0)
                .animation(Theme.Animation.celebration, value: didAppear)

            VStack(spacing: Theme.Spacing.md) {
                Text("Meet Otis")
                    .font(.otisDisplay)
                    .foregroundStyle(.otisSlate)
                    .multilineTextAlignment(.center)
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 20)
                    .animation(Theme.Animation.gentleReveal.delay(0.15), value: didAppear)

                Text("Your AI packing companion. Otis learns what you need and builds smarter lists every trip.")
                    .font(.otisBody)
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 16)
                    .animation(Theme.Animation.gentleReveal.delay(0.25), value: didAppear)
            }

            Spacer()
            Spacer() // extra room for page dots
        }
        .onAppear {
            didAppear = true
            // Start repeating wave after entrance settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(
                    .easeInOut(duration: 0.55)
                    .repeatForever(autoreverses: true)
                ) {
                    isWaving = true
                }
            }
        }
        .onDisappear {
            isWaving = false
            didAppear = false
        }
    }
}

// MARK: - Screen 2: First Trip Hook

private struct OnboardingPage2: View {

    @State private var didAppear = false

    // Floating items: SF symbol name + stagger index
    private let floatingItems: [(symbol: String, index: Int)] = [
        ("tshirt.fill", 0),
        ("shoe.fill", 1),
        ("eyeglasses", 2),
        ("camera.fill", 3),
        ("cross.case.fill", 4),
        ("book.fill", 5),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()

            // Suitcase + floating item illustration
            ZStack {
                // Base suitcase
                Image(systemName: "suitcase.fill")
                    .font(.system(size: Theme.IconSize.otisHero))
                    .foregroundStyle(.otisTeal)
                    .scaleEffect(didAppear ? 1.0 : 0.7)
                    .opacity(didAppear ? 1.0 : 0)
                    .animation(Theme.Animation.celebration, value: didAppear)

                // Floating items orbit the suitcase
                ForEach(0 ..< floatingItems.count, id: \.self) { i in
                    let item = floatingItems[i]
                    let angle = Double(i) * 60.0 // degrees, evenly spread
                    let radius: CGFloat = 80
                    let dx = CGFloat(cos(angle * .pi / 180)) * radius
                    let dy = CGFloat(sin(angle * .pi / 180)) * radius

                    Image(systemName: item.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.otisTeal.opacity(0.75))
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.otisCreame)
                                .shadow(color: .otisTeal.opacity(0.15), radius: 6, x: 0, y: 2)
                        )
                        .offset(
                            x: didAppear ? dx : 0,
                            y: didAppear ? dy : 0
                        )
                        .opacity(didAppear ? 1.0 : 0.0)
                        .scaleEffect(didAppear ? 1.0 : 0.3)
                        .animation(
                            Theme.Animation.celebration
                                .delay(Double(item.index) * 0.07 + 0.1),
                            value: didAppear
                        )
                }
            }
            .frame(width: 240, height: 240)

            VStack(spacing: Theme.Spacing.md) {
                Text("Your first trip is on us")
                    .font(.otisDisplay)
                    .foregroundStyle(.otisSlate)
                    .multilineTextAlignment(.center)
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 20)
                    .animation(Theme.Animation.gentleReveal.delay(0.3), value: didAppear)

                Text("Otis gives you one free AI packing list. No credit card. No pressure. Just great packing.")
                    .font(.otisBody)
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 16)
                    .animation(Theme.Animation.gentleReveal.delay(0.40), value: didAppear)
            }

            Spacer()
            Spacer()
        }
        .onAppear { didAppear = true }
        .onDisappear { didAppear = false }
    }
}

// MARK: - Screen 3: Passport & Stamps

private struct OnboardingPage3: View {

    let onComplete: () -> Void

    @State private var didAppear = false

    // Fan angles for the 3 stamp cards
    private let stampAngles: [Double] = [-18, 0, 18]
    private let stampColors: [Color] = [.otisMint, .otisGold, .otisTeal]

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()

            // Stamp fan illustration
            ZStack {
                ForEach(0 ..< 3, id: \.self) { i in
                    StampCardThumbnail(color: stampColors[i])
                        .rotationEffect(.degrees(didAppear ? stampAngles[i] : 0))
                        .offset(y: didAppear ? CGFloat(i) * -6 : 0)
                        .opacity(didAppear ? 1.0 : 0.0)
                        .scaleEffect(didAppear ? 1.0 : 0.5)
                        .animation(
                            Theme.Animation.celebration.delay(Double(i) * 0.10 + 0.05),
                            value: didAppear
                        )
                        .zIndex(Double(3 - i))
                }
            }
            .frame(width: 200, height: 160)

            VStack(spacing: Theme.Spacing.md) {
                Text("Build your passport")
                    .font(.otisDisplay)
                    .foregroundStyle(.otisSlate)
                    .multilineTextAlignment(.center)
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 20)
                    .animation(Theme.Animation.gentleReveal.delay(0.35), value: didAppear)

                Text("Every trip earns a stamp. Collect them all.")
                    .font(.otisBody)
                    .foregroundStyle(.otisSlateLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .opacity(didAppear ? 1.0 : 0.0)
                    .offset(y: didAppear ? 0 : 16)
                    .animation(Theme.Animation.gentleReveal.delay(0.45), value: didAppear)
            }

            Spacer()

            // Primary CTA — full width teal button
            Button {
                onComplete()
            } label: {
                Text("Let's go")
            }
            .buttonStyle(.otisPrimary)
            .padding(.horizontal, Theme.Spacing.xl)
            .opacity(didAppear ? 1.0 : 0.0)
            .offset(y: didAppear ? 0 : 24)
            .animation(Theme.Animation.gentleReveal.delay(0.55), value: didAppear)

            Spacer()
                .frame(height: Theme.Spacing.xxl) // breathing room above page dots
        }
        .onAppear { didAppear = true }
        .onDisappear { didAppear = false }
    }
}

// MARK: - Otis Mascot View

/// A hand-drawn style Otis mascot built entirely from SwiftUI shapes.
/// The waving arm rotates when `isWaving` is true.
///
/// Usage:
///   OtisMascotView(isWaving: $isWaving)
///     .frame(width: 180, height: 180)
struct OtisMascotView: View {

    var isWaving: Bool = false

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let s = size / 180 // scale factor (designed at 180pt)

            ZStack {
                // Body — rounded teardrop shape
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color.otisTeal, Color.otisTeal.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 100 * s, height: 110 * s)
                    .offset(y: 30 * s)

                // Left arm (static)
                Capsule()
                    .fill(Color.otisTeal)
                    .frame(width: 18 * s, height: 44 * s)
                    .rotationEffect(.degrees(30))
                    .offset(x: -54 * s, y: 40 * s)

                // Right arm — waves when isWaving
                Capsule()
                    .fill(Color.otisTeal)
                    .frame(width: 18 * s, height: 44 * s)
                    .rotationEffect(
                        .degrees(isWaving ? -50 : -20),
                        anchor: .bottom
                    )
                    .offset(x: 54 * s, y: 28 * s)

                // Head
                Circle()
                    .fill(Color.otisTeal)
                    .frame(width: 88 * s, height: 88 * s)
                    .offset(y: -12 * s)

                // Left eye
                Circle()
                    .fill(Color.white)
                    .frame(width: 22 * s, height: 22 * s)
                    .offset(x: -16 * s, y: -14 * s)
                Circle()
                    .fill(Color.otisSlate)
                    .frame(width: 11 * s, height: 11 * s)
                    .offset(x: -15 * s, y: -13 * s)

                // Right eye
                Circle()
                    .fill(Color.white)
                    .frame(width: 22 * s, height: 22 * s)
                    .offset(x: 16 * s, y: -14 * s)
                Circle()
                    .fill(Color.otisSlate)
                    .frame(width: 11 * s, height: 11 * s)
                    .offset(x: 17 * s, y: -13 * s)

                // Smile (arc via Circle trim)
                Circle()
                    .trim(from: 0.62, to: 0.88)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
                    .frame(width: 32 * s, height: 32 * s)
                    .offset(y: -4 * s)

                // Blush left
                Ellipse()
                    .fill(Color.otisCoral.opacity(0.35))
                    .frame(width: 14 * s, height: 8 * s)
                    .offset(x: -22 * s, y: -4 * s)

                // Blush right
                Ellipse()
                    .fill(Color.otisCoral.opacity(0.35))
                    .frame(width: 14 * s, height: 8 * s)
                    .offset(x: 22 * s, y: -4 * s)

                // Feet
                Capsule()
                    .fill(Color.otisTeal.opacity(0.85))
                    .frame(width: 28 * s, height: 16 * s)
                    .offset(x: -22 * s, y: 88 * s)

                Capsule()
                    .fill(Color.otisTeal.opacity(0.85))
                    .frame(width: 28 * s, height: 16 * s)
                    .offset(x: 22 * s, y: 88 * s)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Stamp Card Thumbnail

/// A small decorative stamp card used in the fan illustration on screen 3.
private struct StampCardThumbnail: View {

    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(color.opacity(0.25))
                .frame(width: 120, height: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(color.opacity(0.6), lineWidth: 2)
                )

            VStack(spacing: 4) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(color)

                Text("STAMP")
                    .font(.otisCaptionBold)
                    .foregroundStyle(color.opacity(0.8))
                    .tracking(2)
            }
        }
        .otisShadow(.card)
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView()
}

#Preview("Mascot") {
    ZStack {
        Color.otisCreame.ignoresSafeArea()
        OtisMascotView(isWaving: true)
            .frame(width: 180, height: 180)
    }
}
