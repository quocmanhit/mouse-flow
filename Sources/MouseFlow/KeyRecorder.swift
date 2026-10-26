import AppKit

// Records one shortcut from a HID-level tap, which sees keys before macOS turns them into system
// shortcuts, so combinations like ⌃← or F-keys bound to Mission Control can still be captured.
final class KeyRecorder {
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var completion: ((Shortcut?) -> Void)?

    // Calls back with nil when the user cancels with Esc.
    func start(_ completion: @escaping (Shortcut?) -> Void) -> Bool {
        stop()
        let types: [CGEventType] = [.keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let recorder = Unmanaged<KeyRecorder>.fromOpaque(refcon!).takeUnretainedValue()
                return recorder.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = source
        self.completion = completion
        return true
    }

    func stop() {
        completion = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
            let shortcut = keyCode == 53 && modifiers.isEmpty ? nil : Shortcut(keyCode: keyCode, modifiers: modifiers.rawValue)
            let completion = completion
            // Tearing the tap down from inside its own callback is unsafe, so finish on the next turn.
            DispatchQueue.main.async {
                self.stop()
                completion?(shortcut)
            }
            return nil
        case .keyUp:
            return nil
        default:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
    }
}
