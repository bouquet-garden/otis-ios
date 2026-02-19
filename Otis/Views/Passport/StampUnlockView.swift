// StampUnlockView.swift
// Otis — Views/Passport/
//
// Full-screen celebration overlay presented as .fullScreenCover after trip completion.
// This is Otis's biggest moment — the payoff for finishing a trip.
//
// Animation Sequence (time-based, fully implemented):
//   t=0.0s  Dark overlay fades in (0.3s). Otis appears center, spring scale 0.3→1.1→1.0
//   t=0.0s  Haptic: UINotificationFeedbackGenerator(.success)
//   t=0.4s  Confetti particle system fires (50 particles, palette colors, random trajectories)
//   t=0.8s  Stamp graphic slides up from bottom with spring, settles above Otis
//   t=0.8s  Haptic: UIImpactFeedbackGenerator(.heavy) — stamp "thud"
//   t=1.2s  Stamp title fades in: "You earned: The Pioneer"
//   t=1.2s  Haptic: UIImpactFeedbackGenerator(.medium)
//   t=1.8s  Glow ring animation starts on stamp
//   t=2.5s  "Continue" button fades in at bottom
//   Tap "Continue" → scale + fade out dismissal
//
// Presented from TripDetailView:
//   .fullScreenCover(item: $vm.newlyEarnedStamp) { stamp in
//       StampUnlockView(stamp: stamp) { vm.newlyEarnedStamp = nil }
//   }

import SwiftUI

// MARK: - Particle Shape

enum ParticleShape: CaseIterable {
    case circle, square, star
}

// MARK: - Confetti Particle Model

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var x: CGFloat          // 0-1 across screen width
    var y: CGFloat          // starts near 0.5 (center), moves toward random position
    var rotation: Double    // degrees
    var color: Color
    var scale: CGFloat      // 0.5-1.2
    var shape: ParticleShape
    var yTarget: CGFloat    // final y position (0-1)
    var rotationTarget: Double
    var speed: Double       // animation duration multiplier

    static func generate(count: Int) -> [ConfettiParticle] {
        let palette: [Color] = [.otisTeal, .otisCoral, .otisGold, Color(hex: "A8E6CF"), Color(hex: "FFB347")]
        return (0..<count).map { _ in
            ConfettiParticle(
                x: CGFloat.random(in: 0.05...0.95),
                y: 0.5,
                rotation: Double.random(in: -30...30),
                color: palette.randomElement() ?? .otisTeal,
                scale: CGFloat.random(in: 0.5...1.2),
                shape: ParticleShape.allCases.randomElement() ?? .circle,
                yTarget: CGFloat.random(in: 0.0...1.0),
                rotationTarget: Double.random(in: 180...720) * (Bool.random() ? 1 : -1),
                speed: Double.random(in: 0.8...1.4)
            )
        }
    }
}

// MARK: - StampUnlockView

struct StampUnlockView: View {

    // MARK: - Input

    let stamp: Stamp
    let onDismiss: () -> Void

    // MARK: - Animation State

    @State private var overlayOpacity: Double = 0
    @State private var otisScale: CGFloat = 0.3
    @State private var otisOpacity: Double = 0
    @State private var stampOffset: CGFloat = 300
    @State private var stampOpacity: Double = 0
    @State private var stampScale: CGFloat = 0.6
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 12
    @State private var continueOpacity: Double = 0
    @State private var continueOffset: CGFloat = 20

    // Confetti
    @State private var particles: [ConfettiParticle] = []
    @State private var particlesAnimated: Bool = false

    // Stamp glow
    @State private var glowPulse: Bool = false
    @State private var glowColor: Color = .otisTeal

    // Milestone extras
    @State private var milestoneRingScale: CGFloat = 0.8
    @State private var milestoneRingOpacity: Double = 0
    @State private var starBurstRotation: Double = 0

    // Dismiss animation
    @State private var isDismissing: Bool = false
    @State private var dismissScale: CGFloat = 1.0
    @State private var dismissOpacity: Double = 1.0

    // MARK: - Haptics (pre-warmed)

    private let successGenerator = UINotificationFeedbackGenerator()
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Layer 1: Dark scrim ──
            Color.black
                .opacity(overlayOpacity * 0.78)
                .ignoresSafeArea()

            // ── Layer 2: Confetti particles ──
            GeometryReader { geo in
                ForEach(particles) { particle in
                    ParticleView(particle: particle, animated: particlesAnimated)
                        .position(
                            x: particle.x * geo.size.width,
                            y: (particlesAnimated ? particle.yTarget : particle.y) * geo.size.height
                        )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // ── Layer 3: Content ──
            VStack(spacing: 0) {
                Spacer()

                // Stamp (slides up first, sits above Otis)
                ZStack {
                    // firstTrip: star burst
                    if stamp.stampType == .firstTrip {
                        Image(systemName: "burst.fill")
                            .font(.system(size: 200))
                            .foregroundStyle(Color.otisGold.opacity(0.12))
                            .rotationEffect(.degrees(starBurstRotation))
                    }

                    // Milestone: golden outer ring
                    if stamp.isMilestone {
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(
                                LinearGradient(
                                    colors: [.otisGold, Color(hex: "FFB347"), .otisGold],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 196, height: 196)
                            .scaleEffect(milestoneRingScale)
                            .opacity(milestoneRingOpacity)
                    }

                    // Animated glow ring (all stamps)
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(glowColor.opacity(glowPulse ? 0.55 : 0.1), lineWidth: glowPulse ? 4 : 1)
                        .frame(width: 188, height: 188)
                        .scaleEffect(glowPulse ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                            value: glowPulse
                        )

                    // The stamp cell — large format
                    StampCell(stamp: stamp, isNew: true)
                        .frame(width: 160, height: 160)
                        .scaleEffect(1.45)
                        .padding(24)
                }
                .offset(y: stampOffset)
                .opacity(stampOpacity)
                .scaleEffect(stampScale)

                Spacer().frame(height: 20)

                // Otis celebration mascot
                Image("otis-celebration")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.otisTeal.opacity(0.4), lineWidth: 2)
                    )
                    .shadow(color: .otisTeal.opacity(0.3), radius: 16, x: 0, y: 4)
                    .scaleEffect(otisScale)
                    .opacity(otisOpacity)

                Spacer().frame(height: 24)

                // Stamp earned title
                VStack(spacing: 8) {
                    Text("You earned:")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))

                    Text(stamp.displayTitle)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                    Text(stamp.destination)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))

                    // Milestone special label
                    if stamp.isMilestone {
                        HStack(spacing: 5) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 12))
                            Text("Trip #\(stamp.tripNumber) Milestone!")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(.otisGold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.otisGold.opacity(0.2))
                                .overlay(Capsule().stroke(Color.otisGold.opacity(0.5), lineWidth: 1))
                        )
                        .padding(.top, 4)
                    }

                    // firstTrip special label
                    if stamp.stampType == .firstTrip {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                            Text("Your first adventure — ever!")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.otisCoral)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.otisCoral.opacity(0.18))
                                .overlay(Capsule().stroke(Color.otisCoral.opacity(0.4), lineWidth: 1))
                        )
                        .padding(.top, 4)
                    }
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)

                Spacer().frame(height: 48)

                // Continue button
                Button {
                    triggerDismiss()
                } label: {
                    Text("Continue")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.otisTeal)
                        .frame(width: 220)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
                .opacity(continueOpacity)
                .offset(y: continueOffset)

                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .scaleEffect(dismissScale)
        .opacity(dismissOpacity)
        .onAppear {
            warmUpHaptics()
            startAnimationSequence()
        }
    }

    // MARK: - Haptic Warm-Up

    private func warmUpHaptics() {
        successGenerator.prepare()
        heavyImpact.prepare()
        mediumImpact.prepare()
    }

    // MARK: - Full Animation Sequence

    private func startAnimationSequence() {

        // ── t=0.0s: Overlay fades in + Otis appears ──
        successGenerator.notificationOccurred(.success)

        withAnimation(.easeIn(duration: 0.3)) {
            overlayOpacity = 1.0
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
            otisScale = 1.0
            otisOpacity = 1.0
        }

        // ── t=0.4s: Confetti fires ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            particles = ConfettiParticle.generate(count: 50)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 2.2)) {
                    particlesAnimated = true
                }
            }
        }

        // ── t=0.8s: Stamp slides up + heavy haptic ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            heavyImpact.impactOccurred()

            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                stampOffset = 0
                stampOpacity = 1.0
                stampScale = 1.0
            }

            // Start glow cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                startGlowCycle()
            }

            // Milestone ring animation
            if stamp.isMilestone {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                    milestoneRingScale = 1.0
                    milestoneRingOpacity = 1.0
                }
            }

            // firstTrip: slow star burst rotation
            if stamp.stampType == .firstTrip {
                withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                    starBurstRotation = 360
                }
            }
        }

        // ── t=1.2s: Title fades in + medium haptic ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            mediumImpact.impactOccurred()

            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                titleOpacity = 1.0
                titleOffset = 0
            }
        }

        // ── t=2.5s: Continue button appears ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                continueOpacity = 1.0
                continueOffset = 0
            }
        }
    }

    // MARK: - Glow Color Cycle (teal → coral → gold → teal)

    private func startGlowCycle() {
        glowPulse = true
        cycleGlowColor()
    }

    private func cycleGlowColor() {
        let colors: [Color] = [.otisTeal, .otisCoral, .otisGold]
        var index = 0

        func next() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                guard !isDismissing else { return }
                index = (index + 1) % colors.count
                withAnimation(.easeInOut(duration: 0.6)) {
                    glowColor = colors[index]
                }
                next()
            }
        }
        next()
    }

    // MARK: - Dismiss

    private func triggerDismiss() {
        isDismissing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            dismissScale = 1.06
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.28)) {
                dismissScale = 0.88
                dismissOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            onDismiss()
        }
    }
}

// MARK: - ParticleView

struct ParticleView: View {
    let particle: ConfettiParticle
    let animated: Bool

    var body: some View {
        Group {
            switch particle.shape {
            case .circle:
                Circle()
                    .fill(particle.color)
                    .frame(width: 8 * particle.scale, height: 8 * particle.scale)
            case .square:
                Rectangle()
                    .fill(particle.color)
                    .frame(width: 7 * particle.scale, height: 7 * particle.scale)
                    .cornerRadius(1.5)
            case .star:
                Image(systemName: "star.fill")
                    .font(.system(size: 9 * particle.scale))
                    .foregroundStyle(particle.color)
            }
        }
        .rotationEffect(.degrees(animated ? particle.rotationTarget : particle.rotation))
        .opacity(animated ? 0.0 : 1.0)
        .animation(
            .easeOut(duration: 2.0 * particle.speed),
            value: animated
        )
    }
}

// MARK: - Integration Notes for TripDetailView
//
// 1. Add to TripDetailView state:
//    @State private var newlyEarnedStamp: Stamp? = nil
//
// 2. Update completeTrip call in PackingListViewModel to return the stamp:
//    func completeTrip(modelContext: ModelContext) async -> Stamp? { ... }
//    Or use NotificationCenter to receive the stamp:
//    .onReceive(NotificationCenter.default.publisher(for: .stampDidUnlock)) { note in
//        if let stamp = note.object as? Stamp {
//            newlyEarnedStamp = stamp
//        }
//    }
//
// 3. Add fullScreenCover to TripDetailView body:
//    .fullScreenCover(item: $newlyEarnedStamp) { stamp in
//        StampUnlockView(stamp: stamp) {
//            newlyEarnedStamp = nil
//        }
//    }
//
// 4. In PackingListViewModel.completeTrip(), after posting .tripDidComplete:
//    Task { @MainActor in
//        let stamp = await StampService.shared.awardStamp(for: trip, modelContext: modelContext)
//        NotificationCenter.default.post(name: .stampDidUnlock, object: stamp)
//    }

// MARK: - TripDetailView Integration Extension
// Drop-in modifier to wire up StampUnlockView from any view.

struct StampUnlockModifier: ViewModifier {
    @Binding var stamp: Stamp?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $stamp) { earnedStamp in
                StampUnlockView(stamp: earnedStamp) {
                    stamp = nil
                }
            }
    }
}

extension View {
    /// Presents StampUnlockView as a fullScreenCover when `stamp` is non-nil.
    /// Usage: .stampUnlockCover(stamp: $vm.newlyEarnedStamp)
    func stampUnlockCover(stamp: Binding<Stamp?>) -> some View {
        modifier(StampUnlockModifier(stamp: stamp))
    }
}
