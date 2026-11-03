import XCTest
@testable import DuskeyCore

final class LegacyPreferencesMigrationTests: XCTestCase {
    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "Duskey.MigrationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @MainActor
    func testSettingsSchedulesAndRoundedLocationSurviveTheRename() async throws {
        try withDefaults { defaults in
            let slot = BrightnessPeriod(name: "Evening", startHour: 18, startMinute: 0,
                                        endHour: 22, endMinute: 0, brightness: 0.4)
            let previous: [String: Any] = [
                "hasCompletedOnboarding": true, "overrideEnabled": true,
                "manualBrightness": 0.3, "manualAutoBrightness": true,
                "automationTab": 1, "solarNightBrightness": 0.6,
                "inactivityTimeoutEnabled": true, "inactivityTimeoutSeconds": 45,
                "customPeriods_v3": try JSONEncoder().encode([slot]),
                "latitude": 52.520008, "longitude": 13.404954,
                "solarLocationSource": SolarLocationSource.manual.rawValue
            ]
            LegacyPreferencesMigration.apply(to: defaults, previous: previous)
            let prefs = Preferences(defaults: defaults)
            XCTAssertTrue(prefs.hasCompletedOnboarding)
            XCTAssertTrue(prefs.overrideEnabled)
            XCTAssertEqual(prefs.manualBrightness, 0.3)
            XCTAssertTrue(prefs.manualAutoBrightness)
            XCTAssertEqual(prefs.automationTab, 1)
            XCTAssertEqual(prefs.solarNightBrightness, 0.6)
            XCTAssertTrue(prefs.inactivityTimeoutEnabled)
            XCTAssertEqual(prefs.inactivityTimeoutSeconds, 45)
            XCTAssertEqual(prefs.customPeriods, [slot])
            XCTAssertTrue(prefs.hasSavedLocation)
            XCTAssertEqual(prefs.latitude, 52.5)
            XCTAssertEqual(prefs.longitude, 13.4)
            XCTAssertEqual(prefs.solarLocationSource, .manual)
        }
    }

    @MainActor
    func testExistingDuskeySettingsTakePrecedence() async throws {
        withDefaults { defaults in
            defaults.set(0.2, forKey: "manualBrightness")
            defaults.set(false, forKey: "overrideEnabled")
            LegacyPreferencesMigration.apply(to: defaults, previous: [
                "manualBrightness": 0.9, "overrideEnabled": true,
                "solarNightBrightness": 0.7, "unrelatedPreference": "do not import"
            ])
            let prefs = Preferences(defaults: defaults)
            XCTAssertEqual(prefs.manualBrightness, 0.2)
            XCTAssertFalse(prefs.overrideEnabled)
            XCTAssertEqual(prefs.solarNightBrightness, 0.7)
            XCTAssertNil(defaults.object(forKey: "unrelatedPreference"))
        }
    }

    @MainActor
    func testForgottenLocationAndDeletedSlotsAreNeverImportedAgain() async throws {
        try withDefaults { defaults in
            let slot = BrightnessPeriod(name: "Evening", startHour: 18, startMinute: 0,
                                        endHour: 22, endMinute: 0, brightness: 0.4)
            let previous: [String: Any] = [
                "latitude": 52.5, "longitude": 13.4,
                "customPeriods_v3": try JSONEncoder().encode([slot])
            ]
            LegacyPreferencesMigration.apply(to: defaults, previous: previous)
            let prefs = Preferences(defaults: defaults)
            prefs.clearLocation()
            prefs.removePeriod(id: slot.id)
            LegacyPreferencesMigration.apply(to: defaults, previous: previous)
            let reloaded = Preferences(defaults: defaults)
            XCTAssertFalse(reloaded.hasSavedLocation)
            XCTAssertTrue(reloaded.customPeriods.isEmpty)
            XCTAssertNil(defaults.object(forKey: "latitude"))
            XCTAssertNil(defaults.object(forKey: "longitude"))
        }
    }

    @MainActor
    func testFreshInstallDoesNotImportSettingsOnALaterLaunch() async throws {
        withDefaults { defaults in
            LegacyPreferencesMigration.apply(to: defaults, previous: nil)
            LegacyPreferencesMigration.apply(to: defaults, previous: ["manualBrightness": 0.9])
            XCTAssertEqual(Preferences(defaults: defaults).manualBrightness, 0.5)
            XCTAssertTrue(defaults.bool(forKey: LegacyPreferencesMigration.completionKey))
        }
    }

    @MainActor
    func testOlderPreferenceKeysStillUpgradeAfterTheRename() async throws {
        withDefaults { defaults in
            LegacyPreferencesMigration.apply(to: defaults, previous: [
                "isOverridden": true, "sunsetBrightness": 0.8, "sunsetUseAmbient": true,
                "manualUseAmbient": true, "defaultStartupBrightness": 0.3
            ])
            let prefs = Preferences(defaults: defaults)
            XCTAssertTrue(prefs.overrideEnabled)
            XCTAssertEqual(prefs.solarNightBrightness, 0.8)
            XCTAssertTrue(prefs.solarAutoBrightness)
            XCTAssertTrue(prefs.manualAutoBrightness)
            XCTAssertEqual(prefs.manualBrightness, 0.3)
            XCTAssertTrue(prefs.hasCompletedOnboarding)
        }
    }
}
