import Foundation
import Combine

/// Keep only editing values between popover openings. This object must never
/// own views, hosting controllers, menus, or bindings back into a view tree.
@MainActor
final class ContentViewState: ObservableObject {
    @Published var onboardingPage = 0
    @Published var editingID: UUID?
    @Published var draft: BrightnessPeriod?
    @Published var isAddingNew = false
    @Published var overlapWarning = false
    @Published var showManualLocationEditor = false
    @Published var showLocationControls = false
    @Published var showApproximateLocationConsent = false
    @Published var manualLatitude = ""
    @Published var manualLongitude = ""
    @Published var demoMinutes = 0
    @Published var demoSeconds = 30

    func closeTransientControls() {
        if showLocationControls { showLocationControls = false }
        if showManualLocationEditor { showManualLocationEditor = false }
        if showApproximateLocationConsent { showApproximateLocationConsent = false }
    }
}
