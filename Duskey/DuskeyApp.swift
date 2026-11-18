import SwiftUI

@main
@MainActor
struct DuskeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #if DEBUG && DUSKEY_UI_TESTING
    @StateObject private var viewState = ContentViewState()
    #endif

    var body: some Scene {
        #if DEBUG && DUSKEY_UI_TESTING
        WindowGroup("Duskey UI Test") {
            ContentView(state: viewState)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--light") ? .light : .dark)
        }
        .windowResizability(.contentSize)
        #else
        // The delegate owns the status item. Settings views exist only while
        // its popover is open, rather than living in a retained scene all day.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppRuntime.isUITesting ? .regular : .accessory)
        if !AppRuntime.isUITesting {
            menuBarController = MenuBarController()
        }
        AutoBacklightController.shared.startMonitoring()
        if !AppRuntime.isUITesting {
            SunScheduleManager.shared.refreshLocationOnceAtStartup()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AutoBacklightController.shared.stopMonitoring()
        menuBarController?.stop()
        menuBarController = nil
        if AppRuntime.isUITesting {
            UserDefaults.standard.removePersistentDomain(forName: "Duskey.UITesting")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController?.showSettings()
        return false
    }
}
