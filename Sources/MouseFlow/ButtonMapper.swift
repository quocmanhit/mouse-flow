import AppKit

final class ButtonMapper {
    private static let syntheticMarker: Int64 = 0x4D46_4B42

    private let store: MappingStore
    private let settings: Settings
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    // Buttons whose press we replaced, so the matching drag/release is swallowed too.
    private var swallowed = Set<Int64>()

    init(store: MappingStore, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let mapper = Unmanaged<ButtonMapper>.fromOpaque(refcon!).takeUnretainedValue()
                return mapper.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
        swallowed.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        // The bypass key only selects native behaviour, so the app must not see it as a modified click.
        let bypass = settings.bypassModifier.map { event.flags.contains($0) } ?? false
        if bypass, let key = settings.bypassModifier { event.flags.remove(key) }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .otherMouseDown:
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let tagged = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
            let target = tagged != 0 ? tagged : Self.windowOwner(at: event.location) ?? 0
            // Presses on our own settings window stay native so they can be identified there.
            guard !bypass, target != ownPID else { return pass }
            // Keystrokes go to the focused app, so that is the app whose mapping applies. While our settings
            // window has focus, a press over another app's window uses that app's mapping instead.
            let front = NSWorkspace.shared.frontmostApplication
            let ownFront = front?.processIdentifier == ownPID
            let bundleID = ownFront ? NSRunningApplication(processIdentifier: target)?.bundleIdentifier : front?.bundleIdentifier
            guard let action = store.action(button: Int(button), bundleID: bundleID) else { return pass }
            let shortcut: Shortcut
            switch action {
            case .system(let system):
                shortcut = system.shortcut
            case .shortcut(let appShortcut):
                // It would land in our settings window rather than the app under the cursor.
                if ownFront { return pass }
                shortcut = appShortcut
            case .native:
                return pass
            }
            swallowed.insert(button)
            send(shortcut)
            return nil
        case .otherMouseDragged:
            return swallowed.contains(button) ? nil : pass
        case .otherMouseUp:
            return swallowed.remove(button) != nil ? nil : pass
        default:
            return pass
        }
    }

    // Topmost normal window under the pointer, for events that arrive without a target app.
    private static func windowOwner(at point: CGPoint) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows where window[kCGWindowLayer as String] as? Int == 0 {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point) else { continue }
            return window[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }

    // Real arrow/F-key presses carry these flags, and system shortcuts like Ctrl+← only match with them.
    private static func implicitFlags(_ keyCode: UInt16) -> CGEventFlags {
        switch keyCode {
        case 123...126: [.maskSecondaryFn, .maskNumericPad]
        case 96...101, 103, 105...107, 109, 111, 113, 115...122: .maskSecondaryFn
        default: []
        }
    }

    private func send(_ shortcut: Shortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let key = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: isDown) else { continue }
            key.flags = shortcut.flags.union(Self.implicitFlags(shortcut.keyCode))
            key.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            key.post(tap: .cghidEventTap)
        }
    }
}
