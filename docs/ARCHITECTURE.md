# Architecture

Duskey uses an AppKit status item with SwiftUI settings. Xcode's synchronized `Duskey/` group compiles all app sources.
`Package.swift` compiles the same `Duskey/Core/` files as a small library for hardware-independent
XCTest coverage; the app does not link or download a separate copy of the library.

| Area | Responsibility |
| --- | --- |
| `DuskeyApp.swift` | Startup, Debug UI scene, and normal termination |
| `Views/MenuBarController.swift` | Status item and on-demand settings popover lifetime |
| `Views/ContentViewState.swift` | Small editing/onboarding state retained between popover openings |
| `Core/LegacyPreferencesMigration.swift` | One-time import of known settings from the previous app identity |
| `ContentView.swift` | Mode selection, onboarding, schedule editing, and bounded scrolling |
| `Views/` | Native duration/time menus, sliders, switches, and reusable styling |
| `Core/BrightnessPeriod.swift` | Validated daily ranges, overnight intervals, and overlap checks |
| `Core/Preferences.swift` | Main-actor UserDefaults storage, migration, validation, and location deletion |
| `Core/AutomationPolicy.swift` | Pure brightness decisions, idle-timeout precedence, and inactivity state |
| `Core/SolarCalculator.swift` | Offline NOAA-based solar events, time zones, and polar conditions |
| `Core/LocationCoordinate.swift` | Coordinate validation, reduced storage precision, response parsing, and startup policy |
| `Core/LocationLookupClient.swift` | Bounded, cancellable, optional HTTPS IP lookup |
| `Location/SunScheduleManager.swift` | Mac location authorization, request lifecycle, saved coordinates, and solar refresh |
| `Automation/AutoBacklightController.swift` | Applies policy, manages previews and sleep/wake, and publishes status |
| `Hardware/KeyboardBacklightManager.swift` | Fixed-path CoreBrightness loading and checked Objective-C dispatch |

## Runtime

Observable controllers and preferences are isolated to the main actor. One reusable main-run-loop
timer wakes for the next policy boundary, earliest possible idle timeout, preview expiry,
or hardware retry. Only an inactivity-dimmed keyboard polls twice a second to detect actual input;
invalid idle counters also retry at that cadence. Time Slots checks local minute boundaries, which
preserves repeated-hour/DST behavior. Sun Cycle wakes at sunrise/sunset and daily/DST refreshes.
System Control without an idle timeout only needs the daily solar-cache refresh. Cached policy
targets include formatted status text, so idle checks do not rebuild settings, strings, calendars,
or interval arrays. Timer callbacks execute directly on the main actor without creating Tasks,
stay available during native menu tracking through common run-loop modes, and drain temporary
Objective-C allocations in a local autorelease pool.

Hardware commands compare brightness/ambient output independently of visible schedule labels.
Failed or partially successful writes invalidate the cached hardware output and retry with bounded
exponential backoff (0.5–30 seconds). New output requests bypass an older output's retry deadline.
Published values change only when needed. Solar validity uses cached Date bounds rather than a
new string/calendar/time-zone key on every check; clock/time-zone/locale changes and wake force
refreshes. Formatted solar labels are cached and update even when only their time-zone offset changes.

The status item subscribes only to distinct day/night icon values. Opening settings creates a
popover and hosting controller; closing it detaches and releases the entire SwiftUI hierarchy,
native menus, and view subscriptions. Only plain editing values and onboarding progress survive
in `ContentViewState`, which never owns views or bindings. Preferred-size changes resize an open
popover. The Debug test window keeps the same views and state model, without a status item.

The controller captures brightness and ambient mode once before taking control and restores them
on normal termination. Sleep stops polling and cancels a brightness preview; wake reapplies the
current mode without replacing the original captured state. Suspended monitoring rejects delayed
preference/location callbacks. Slider previews move the shared timer's deadline and expire after
three seconds; no delayed reset work items are queued. Preview and startup-grace durations use
monotonic uptime, so wall-clock adjustments cannot extend them.

The core inactivity latch prevents changing a schedule or removing a timeout from lighting an
unattended keyboard. Actual input clears it. Slot-specific nonzero timeouts take priority; zero
inherits the global setting. Invalid stored periods are excluded before time arithmetic.

## Location lifecycle

The selected source is preserved across launches. Startup can refresh only an already authorized
Mac Location source. IP lookup requires a user confirmation and never runs as a fallback.
Network requests use a cancellable task plus an identity check; switching to manual/Mac location
or forgetting location invalidates pending results. Core Location callbacks are accepted only
while a Mac location request is active. Core Location's manager is created only for a Mac Location
request or startup authorization check for that saved source. A single invalidatable run-loop timer
bounds each permission/location wait; sleep/quit cancels outstanding requests and timers.
Responses are rounded before being persisted.

## Test window

Only a Debug build compiled with `DUSKEY_UI_TESTING` replaces the status item with a regular
window. It uses an isolated preference domain and simulates keyboard hardware, idle input, and
location requests. Release builds ignore the test flag. This allows UI verification without
changing the user's keyboard state or location settings. It does not test CoreBrightness itself. `--light` selects light appearance.
The explicit `--test-mac-location` argument enables a real, consent-based Mac Location request
in that Debug-only window; IP lookup and keyboard hardware remain simulated. Test coordinates
stay in the isolated domain and are deleted on normal quit.
