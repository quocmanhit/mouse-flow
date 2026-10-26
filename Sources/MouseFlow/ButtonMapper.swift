import AppKit

final class ButtonMapper {
    private static let syntheticMarker: Int64 = 0x4D46_4B42

    private let store: MappingStore
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    // Buttons whose press we replaced, so the matching drag/release is swallowed too.
    private var swallowed = Set<Int64>()

    init(store: MappingStore) {
        self.store = store
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
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .otherMouseDown:
            // Keystrokes go to the focused app, so that is the app whose mapping applies.
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            // Leave buttons alone in our own settings window so presses can be identified there.
            guard bundleID != Bundle.main.bundleIdentifier,
                  let shortcut = store.shortcut(button: Int(button), bundleID: bundleID) else { return pass }
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
