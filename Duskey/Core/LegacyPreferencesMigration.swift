import Foundation

/// Copies the previous app's settings once, without replacing any Duskey choices.
enum LegacyPreferencesMigration {
    // Compatibility identifier, deliberately unchanged so existing installs can upgrade.
    static let previousDomain = "Andreupeak.Lumina"
    static let completionKey = "hasMigratedPreviousAppPreferences"

    private static let preferenceKeys = [
        "hasCompletedOnboarding", "overrideEnabled", "manualBrightness", "manualAutoBrightness",
        "automationTab", "solarNightBrightness", "solarAutoBrightness", "latitude", "longitude",
        "hasSavedLocation", "solarLocationSource", "inactivityTimeoutEnabled",
        "inactivityTimeoutMinutes", "inactivityTimeoutSeconds", "customPeriods_v3",
        // Older releases are normalized by Preferences after the domain migration.
        "isOverridden", "sunsetBrightness", "sunsetUseAmbient", "manualUseAmbient",
        "defaultStartupBrightness", "useCoreLocation"
    ]

    static func apply(to defaults: UserDefaults) {
        guard !defaults.bool(forKey: completionKey) else { return }
        apply(to: defaults, previous: defaults.persistentDomain(forName: previousDomain))
    }

    static func apply(to defaults: UserDefaults, previous: [String: Any]?) {
        guard !defaults.bool(forKey: completionKey) else { return }
        for key in preferenceKeys where defaults.object(forKey: key) == nil {
            if let value = previous?[key] { defaults.set(value, forKey: key) }
        }
        // Mark even a fresh install: forgotten locations and removed slots must never
        // be resurrected from the previous domain on a later launch.
        defaults.set(true, forKey: completionKey)
    }
}
