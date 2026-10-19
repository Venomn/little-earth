import AppKit

/// Explicit dismissal for a nonactivating desktop companion. AppKit's transient
/// behavior alone does not cover its owner panel and other apps consistently.
final class PopoverDismissal: NSObject, NSPopoverDelegate {
    private let popover: NSPopover
    private let onOutsideClick: (NSEvent) -> Void
    private let onClose: () -> Void
    private let onShow: () -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    init(popover: NSPopover, onOutsideClick: @escaping (NSEvent) -> Void, onClose: @escaping () -> Void = {}, onShow: @escaping () -> Void = {}) {
        self.popover = popover; self.onOutsideClick = onOutsideClick; self.onClose = onClose; self.onShow = onShow
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
    }
    func popoverDidShow(_ notification: Notification) {
        // The floating owner deliberately stays non-key. Give the visible card
        // its own keyboard focus so local key monitoring receives actual keys.
        popover.contentViewController?.view.window?.makeKey()
        onShow()
        stopMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown,.rightMouseDown,.otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching:clicks.union(.keyDown)) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalEvent(event)
        }
        // Global mouse monitoring requires no keyboard/accessibility permission.
        // It observes other apps; it cannot consume or alter their click.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching:clicks) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        activationObserver = NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }
    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown else { return event }
        if event.type == .keyDown {
            if event.keyCode == 53 { popover.performClose(nil); return nil }
            return event
        }
        if event.window !== popover.contentViewController?.view.window {
            onOutsideClick(event)
            popover.performClose(nil)
        }
        return event
    }
    func popoverDidClose(_ notification: Notification) {
        stopMonitoring(); onClose()
    }
    private func stopMonitoring() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }; activationObserver = nil
    }
    deinit { stopMonitoring() }
}
