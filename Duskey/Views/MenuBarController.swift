import AppKit
import Combine
import SwiftUI

/// Own the lightweight status item separately from the short-lived settings UI.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let viewState = ContentViewState()
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleSettings(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Duskey — Keyboard backlight"
            button.setAccessibilityLabel("Duskey")
            button.setAccessibilityHelp("Open keyboard backlight settings")
        }
        AutoBacklightController.shared.$isNightMode
            .removeDuplicates()
            .sink { [weak self] in self?.updateIcon(isNight: $0) }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification))
            .sink { [weak self] _ in self?.popover?.close() }
            .store(in: &cancellables)
    }

    @objc private func toggleSettings(_ sender: Any?) {
        if let popover {
            popover.performClose(sender)
        } else {
            showSettings()
        }
    }

    func showSettings() {
        guard popover == nil, let button = statusItem.button, button.window != nil else { return }
        // Catch up after a day/time-zone change before constructing any labels.
        SunScheduleManager.shared.refreshSolarTimesIfNeeded()
        let host = SettingsHostingController(rootView: ContentView(state: viewState)
            .fixedSize(horizontal: false, vertical: true))
        host.sizingOptions = [.preferredContentSize]

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = host
        host.popover = popover
        // Ask SwiftUI for an initial size rather than depending on a hosting
        // view's constraints having completed their first AppKit layout pass.
        popover.contentSize = host.sizeThatFits(in: NSSize(width: 380, height: 1_000))
        self.popover = popover
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Make text fields and native menus available to keyboard navigation.
        popover.contentViewController?.view.window?.makeKey()
        if !popover.isShown { releasePopover(popover) }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover else { return }
        releasePopover(closed)
    }

    private func releasePopover(_ closed: NSPopover) {
        guard popover === closed else { return }
        closed.delegate = nil
        // Break AppKit's ownership of the hosting controller, its SwiftUI graph,
        // native picker menus, materials, and subscriptions as soon as it closes.
        closed.contentViewController = nil
        popover = nil
        viewState.closeTransientControls()
    }

    private func updateIcon(isNight: Bool) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: isNight ? "moon.stars.fill" : "sun.max.fill",
                            accessibilityDescription: "Duskey")
        image?.isTemplate = true
        button.image = image
        button.title = image == nil ? "Duskey" : ""
    }

    func stop() {
        if let popover {
            popover.animates = false
            popover.close()
            releasePopover(popover)
        }
        cancellables.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

/// Explicitly forward SwiftUI's preferred-size changes so mode/onboarding and
/// timeout controls continue to resize a visible popover. The weak reference
/// must not keep a closed popover or its hosting controller alive.
@MainActor
private final class SettingsHostingController<Content: View>: NSHostingController<Content> {
    weak var popover: NSPopover?

    override var preferredContentSize: NSSize {
        didSet {
            guard let popover, popover.isShown,
                  preferredContentSize.width > 0, preferredContentSize.height > 0,
                  popover.contentSize != preferredContentSize else { return }
            popover.contentSize = preferredContentSize
        }
    }
}
