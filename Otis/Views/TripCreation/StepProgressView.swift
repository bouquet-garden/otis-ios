// StepProgressView.swift
// Otis — Views/TripCreation/
//
// 3-dot step progress indicator used at the top of the TripCreationView sheet.
//
// Visual states:
//   • Completed step  — filled otisTeal circle, full opacity
//   • Current step    — filled otisTeal circle, pulsing scale animation
//   • Upcoming step   — cream fill, otisSlate border, muted opacity
//
// Transitions between states are spring-animated so the progress indicator
// feels alive as the user moves through the wizard.

import SwiftUI

// MARK: - StepProgressView

struct StepProgressView: View {

    /// The zero-indexed step the user is currently on.
    let currentStep: Int

    /// Total number of steps in the flow.
    let totalSteps: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<totalSteps, id: \.self) { index in
                StepDot(
                    state: dotState(for: index),
                    index: index
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
        .accessibilityValue(stepAccessibilityValue)
    }

    // MARK: - Helpers

    private func dotState(for index: Int) -> StepDotState {
        if index < currentStep  { return .completed }
        if index == currentStep { return .current   }
        return .upcoming
    }

    private var stepAccessibilityValue: String {
        switch currentStep {
        case 0: return "Where are you going?"
        case 1: return "When are you traveling?"
        case 2: return "Name your trip"
        default: return ""
        }
    }
}

// MARK: - Dot State

private enum StepDotState {
    case completed
    case current
    case upcoming
}

// MARK: - StepDot

private struct StepDot: View {

    let state: StepDotState
    let index: Int

    /// Drives the pulsing animation for the current step dot.
    @State private var isPulsing: Bool = false

    private var dotSize: CGFloat { 8 }
    private var currentDotSize: CGFloat { 10 }

    var body: some View {
        ZStack {
            // Outer pulse ring — only visible on the current step
            if state == .current {
                Circle()
                    .stroke(Color.otisTeal.opacity(0.3), lineWidth: 2)
                    .frame(width: currentDotSize + 8, height: currentDotSize + 8)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            // Core dot
            Circle()
                .fill(dotFill)
                .frame(width: dotDiameter, height: dotDiameter)
                .overlay(
                    Circle()
                        .stroke(dotBorderColor, lineWidth: state == .upcoming ? 1.5 : 0)
                )
                .scaleEffect(state == .current ? 1.2 : 1.0)
                .opacity(state == .upcoming ? 0.45 : 1.0)
                .shadow(
                    color: state != .upcoming ? Color.otisTeal.opacity(0.25) : .clear,
                    radius: 4, x: 0, y: 2
                )
        }
        .frame(width: currentDotSize + 12, height: currentDotSize + 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state == .current)
        .onAppear {
            if state == .current {
                isPulsing = true
            }
        }
        .onChange(of: state) { _, newState in
            isPulsing = (newState == .current)
        }
    }

    private var dotDiameter: CGFloat {
        state == .current ? currentDotSize : dotSize
    }

    private var dotFill: AnyShapeStyle {
        switch state {
        case .completed: return AnyShapeStyle(Color.otisTeal)
        case .current:   return AnyShapeStyle(Color.otisTeal)
        case .upcoming:  return AnyShapeStyle(Color.otisCreame)
        }
    }

    private var dotBorderColor: Color {
        state == .upcoming ? Color.otisSlate.opacity(0.4) : .clear
    }
}

// MARK: - Connector Line (optional extended variant)

/// Extended variant that draws connecting lines between dots.
/// Use StepProgressView (above) for the standard compact layout.
struct StepProgressBarView: View {

    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalSteps, id: \.self) { index in
                // Dot
                Circle()
                    .fill(index <= currentStep ? Color.otisTeal : Color.otisCreame)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(
                            index <= currentStep ? Color.clear : Color.otisSlate.opacity(0.35),
                            lineWidth: 1.5
                        )
                    )
                    .scaleEffect(index == currentStep ? 1.3 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)

                // Connector (skip after last dot)
                if index < totalSteps - 1 {
                    Rectangle()
                        .fill(
                            index < currentStep
                                ? Color.otisTeal
                                : Color.otisSlate.opacity(0.2)
                        )
                        .frame(height: 2)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
    }
}

// MARK: - Preview

#Preview("Step Progress — Steps") {
    VStack(spacing: Theme.Spacing.xl) {
        ForEach(0..<3) { step in
            VStack(spacing: Theme.Spacing.sm) {
                Text("Step \(step + 1)").font(.otisCaption).foregroundStyle(.secondary)
                StepProgressView(currentStep: step, totalSteps: 3)
            }
        }
    }
    .padding()
    .background(Color.otisCreame)
}
