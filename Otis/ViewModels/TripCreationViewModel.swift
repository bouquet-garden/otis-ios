// TripCreationViewModel.swift
// Otis
//
// @Observable ViewModel driving the 3-step trip creation sheet.
// Owns all form state, step validation, computed derived values,
// and the final SwiftData insert. No UIKit imports — haptics are
// triggered by the view layer via HapticEngine.
//
// Step 0 — Where are you going? (destination + trip type)
// Step 1 — When?               (dates + night count)
// Step 2 — Name your trip      (editable auto-suggested name + create CTA)

import Foundation
import SwiftData
import Observation

@Observable
final class TripCreationViewModel {

    // MARK: - Step Navigation

    /// Current wizard step. Range: 0...2.
    var currentStep: Int = 0

    /// Total number of steps in the creation flow.
    let totalSteps: Int = 3

    // MARK: - Step 0: Destination & Trip Type

    /// Free-text destination entered by the user.
    var destination: String = ""

    /// The selected trip type chip.
    var selectedTripType: TripType = .city

    // MARK: - Step 1: Dates

    /// Departure date. Defaults to 7 days from now.
    var departureDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    /// Return date. nil when hasReturnDate is false.
    var returnDate: Date? = Calendar.current.date(byAdding: .day, value: 12, to: .now)

    /// When false the return date picker is hidden and returnDate is forced nil.
    var hasReturnDate: Bool = true

    // MARK: - Step 2: Trip Name

    /// Editable trip name — pre-filled with suggestion when entering step 2.
    var tripName: String = ""

    /// Whether the user has manually edited the trip name away from the suggestion.
    private var hasCustomName: Bool = false

    // MARK: - Confirmation Dialog

    /// Presented when the user taps Cancel with unsaved data.
    var showCancelConfirmation: Bool = false

    // MARK: - Computed: Night Count

    /// Number of nights between departure and return.
    /// Returns 0 if no return date is set or dates are equal/reversed.
    var nightCount: Int {
        guard hasReturnDate, let ret = returnDate else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: departureDate, to: ret).day ?? 0
        return max(0, days)
    }

    /// True when the trip is shorter than 3 nights — surfaces the Quick Pack nudge.
    var isQuickTrip: Bool {
        guard hasReturnDate else { return false }
        return nightCount > 0 && nightCount < 3
    }

    /// Formatted night count label. Returns nil when no return date is set.
    var nightCountLabel: String? {
        guard hasReturnDate, nightCount > 0 else { return nil }
        return nightCount == 1 ? "1 night" : "\(nightCount) nights"
    }

    // MARK: - Computed: Trip Name Suggestion

    /// Auto-generated name built from the selected type and destination.
    /// Updates reactively as either field changes.
    var tripNameSuggestion: String {
        let dest = destination.trimmingCharacters(in: .whitespaces)
        let type = selectedTripType.displayName
        if dest.isEmpty {
            return type
        }
        return "\(type) to \(dest)"
    }

    // MARK: - Computed: Validation

    /// Whether the user may advance from the current step.
    var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case 0:
            return !destination.trimmingCharacters(in: .whitespaces).isEmpty
        case 1:
            if hasReturnDate {
                guard let ret = returnDate else { return false }
                // Return must be at least same day as departure (day trips allowed)
                return ret >= departureDate
            }
            return true
        case 2:
            return !tripName.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return false
        }
    }

    /// True when any meaningful data has been entered — used to gate cancel confirmation.
    var hasUnsavedChanges: Bool {
        !destination.trimmingCharacters(in: .whitespaces).isEmpty
            || hasCustomName
            || selectedTripType != .city
    }

    // MARK: - Step Navigation Actions

    /// Advances to the next step with side effects (e.g., pre-filling name).
    func proceedToNextStep() {
        guard canProceedFromCurrentStep else { return }

        // When entering the name step, pre-fill with suggestion if the user
        // hasn't typed a custom name yet.
        if currentStep == 1 && !hasCustomName {
            tripName = tripNameSuggestion
        }

        if currentStep < totalSteps - 1 {
            currentStep += 1
        }
    }

    /// Steps back one step without clearing data.
    func goToPreviousStep() {
        if currentStep > 0 {
            currentStep -= 1
        }
    }

    /// Called when the user manually edits the trip name field.
    /// Marks the name as custom so re-entering the step doesn't overwrite it.
    func onTripNameEdited() {
        hasCustomName = !tripName.isEmpty
    }

    // MARK: - Return Date Handling

    /// Minimum valid return date — departure day itself (day trips allowed).
    var minimumReturnDate: Date {
        departureDate
    }

    /// Called when departureDate changes — clamp returnDate forward if needed.
    func onDepartureDateChanged() {
        guard hasReturnDate, let ret = returnDate, ret < departureDate else { return }
        // Preserve the original duration or default to +5 nights
        let nights = max(1, nightCount)
        returnDate = Calendar.current.date(byAdding: .day, value: nights, to: departureDate)
    }

    /// Toggles one-way mode. When enabling return date, default to departure + 5 nights.
    func toggleReturnDate() {
        hasReturnDate.toggle()
        if hasReturnDate && returnDate == nil {
            returnDate = Calendar.current.date(byAdding: .day, value: 5, to: departureDate)
        }
    }

    // MARK: - Trip Creation

    /// Inserts a new Trip into the SwiftData ModelContext and returns it.
    /// The caller is responsible for saving the context (ModelContext auto-saves
    /// on the next run-loop tick with the default container configuration).
    @discardableResult
    func createTrip(modelContext: ModelContext, isFirstTrip: Bool = false) -> Trip {
        let name = tripName.trimmingCharacters(in: .whitespaces)
        let dest = destination.trimmingCharacters(in: .whitespaces)

        let trip = Trip(
            name: name.isEmpty ? tripNameSuggestion : name,
            destination: dest,
            tripType: selectedTripType,
            departureDate: departureDate,
            returnDate: hasReturnDate ? returnDate : nil,
            isFirstTrip: isFirstTrip
        )

        modelContext.insert(trip)
        return trip
    }

    // MARK: - Reset

    /// Resets all form state back to defaults. Call after successful creation
    /// or if the user cancels and you want to recycle the VM.
    func reset() {
        currentStep = 0
        destination = ""
        selectedTripType = .city
        departureDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        returnDate = Calendar.current.date(byAdding: .day, value: 12, to: .now)
        hasReturnDate = true
        tripName = ""
        hasCustomName = false
        showCancelConfirmation = false
    }
}
