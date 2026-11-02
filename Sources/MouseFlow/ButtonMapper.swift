import AppKit

final class ButtonMapper {
    private static let syntheticMarker: Int64 = 0x4D46_4B42

    private let store: MappingStore
    private let settings: Settings
    private lazy var exclusions = ExclusionCache(settings: settings)
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    // Buttons whose press we replaced, so the matching drag/release is swallowed too.
    private var swallowed = Set<Int64>()
    // Buttons pressed in an excluded app, whose drag/release must stay untouched too.
    private var untouched = Set<Int64>()

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
        untouched.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .otherMouseDown:
            // A lost mouse-up must not leave stale state that swallows a later release.
            swallowed.remove(button)
            untouched.remove(button)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let tagged = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
            let target = tagged != 0 ? tagged : Self.windowOwner(at: event.location) ?? 0
            // Presses on our own settings window stay native so they can be identified there.
            if target == ownPID {
                stripHoldKeys(event)
                return pass
            }
            // Keystrokes go to the focused app, so that is the app whose mapping applies. While our settings
            // window has focus, a press over another app's window uses that app's mapping instead.
            let front = NSWorkspace.shared.frontmostApplication
            let ownFront = front?.processIdentifier == ownPID
            let bundleID = ownFront ? NSRunningApplication(processIdentifier: target)?.bundleIdentifier : front?.bundleIdentifier
            // Also covers a click on an excluded app's window while another app is frontmost.
            if settings.isExcluded(bundleID: bundleID) || exclusions.isExcluded(pid: target) {
                untouched.insert(button)
                return pass
            }
            let held = stripHoldKeys(event)
            if held.native { return pass }
            // nil makes the lookup fall through to the "every app" mappings.
            let lookupID = held.useDefaults ? nil : bundleID
            guard let action = store.action(button: Int(button), bundleID: lookupID) else { return pass }
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
            if untouched.contains(button) { return pass }
            stripHoldKeys(event)
            return swallowed.contains(button) ? nil : pass
        case .otherMouseUp:
            if untouched.remove(button) != nil { return pass }
            stripHoldKeys(event)
            return swallowed.remove(button) != nil ? nil : pass
        default:
            return pass
        }
    }

    // The hold keys only pick which behaviour applies, so the app must not see them as a modified click.
    // When both are held, or both use the same key, native behaviour wins.
    @discardableResult
    private func stripHoldKeys(_ event: CGEvent) -> (native: Bool, useDefaults: Bool) {
        let flags = event.flags
        let native = settings.bypassModifier.map { flags.contains($0) } ?? false
        let useDefaults = settings.defaultsModifier.map { flags.contains($0) } ?? false
        if native, let key = settings.bypassModifier { event.flags.remove(key) }
        if useDefaults, let key = settings.defaultsModifier { event.flags.remove(key) }
        return (native, useDefaults && !native)
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
