// PackingProgressRing.swift
// Otis — Views/PackingList/
//
// Circular progress ring for the trip detail header. Animates smoothly as
// items are checked off. At 100% it pulses coral once and shows a checkmark.
//
// Usage:
//   PackingProgressRing(progress: vm.packingProgress, size: 60, lineWidth: 5)

import SwiftUI

// MARK: - PackingProgressRing

struct PackingProgressRing: View {

    // MARK: - Parameters

    /// Packing completion ratio, 0.0 – 1.0.
    let progress: Double

    /// Outer diameter of the ring.
    var size: CGFloat = 60

    /// Stroke width of both rings.
    var lineWidth: CGFloat = 5

    // MARK: - Private State

    /// Drives the 100% celebration pulse.
    @State private var isPulsing: Bool = false

    /// Tracks the previous progress to detect the 100% transition.
    @State private var lastProgress: Double = 0

    // MARK: - Computed

    private var isComplete: Bool { progress >= 1.0 }

    private var ringColor: Color {
        isPulsing ? .otisCoral : .otisTeal
    }

    private var percentageText: String {
        "\(Int(progress * 100))%"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.otisTeal.opacity(0.15), lineWidth: lineWidth)
                .frame(width: size, height: size)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: progress)

            // Center content
            centerContent
        }
        .scaleEffect(isPulsing ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isPulsing)
        .onChange(of: progress) { oldValue, newValue in
            if newValue >= 1.0 && oldValue < 1.0 {
                fireCelebrationPulse()
            }
            lastProgress = newValue
        }
        .onAppear {
            lastProgress = progress
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Packing progress")
        .accessibilityValue("\(Int(progress * 100)) percent packed")
    }

    // MARK: - Center Content

    @ViewBuilder
    private var centerContent: some View {
        if isComplete {
            // Checkmark at 100%
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(.otisTeal)
                .transition(.scale.combined(with: .opacity))
        } else {
            // Percentage text
            Text(percentageText)
                .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                .foregroundStyle(.otisSlate)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: percentageText)
        }
    }

    // MARK: - Celebration Pulse

    private func fireCelebrationPulse() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            isPulsing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isPulsing = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Progress Ring") {
    VStack(spacing: 32) {
        HStack(spacing: 24) {
            PackingProgressRing(progress: 0.0, size: 60, lineWidth: 5)
            PackingProgressRing(progress: 0.33, size: 60, lineWidth: 5)
            PackingProgressRing(progress: 0.75, size: 60, lineWidth: 5)
            PackingProgressRing(progress: 1.0, size: 60, lineWidth: 5)
        }

        // Interactive demo
        InteractiveRingDemo()
    }
    .padding()
    .background(Color.otisCreame)
}

private struct InteractiveRingDemo: View {
    @State private var progress: Double = 0.0

    var body: some View {
        VStack(spacing: 16) {
            PackingProgressRing(progress: progress, size: 80, lineWidth: 6)
            Slider(value: $progress, in: 0...1)
                .tint(.otisTeal)
                .padding(.horizontal)
        }
    }
}
