import AppKit
import QuartzCore

final class ScrollEngine: NSObject {
    // Tags events we emit so the tap never smooths its own output a second time.
    private static let syntheticMarker: Int64 = 0x4D46_4C57

    private let settings: Settings
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var template: CGEvent?
    private var targetPID: pid_t = 0
    private var pendingX = 0.0, pendingY = 0.0
    private var carryX = 0.0, carryY = 0.0

    init(settings: Settings) {
        self.settings = settings
        super.init()
        // A display link is bound to one screen and stops when that screen goes away or starts mirroring
        // (e.g. a HiDPI virtual display), which would freeze the glide and swallow the wheel.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resetDisplayLink() }
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        // Tapping after the system has picked the target app lets copies of the event be sent straight to it.
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let engine = Unmanaged<ScrollEngine>.fromOpaque(refcon!).takeUnretainedValue()
                return engine.handle(type: type, event: event)
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
        displayLink?.invalidate()
        displayLink = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type == .scrollWheel,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker,
              // Trackpads and Magic Mouse send continuous events and already scroll smoothly.
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
        else { return pass }

        guard settings.smooth else {
            if settings.reverse { Self.invert(event) }
            return pass
        }

        // The glide is delivered straight to the app under the cursor; without one, keep the original.
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard pid != 0, let copy = event.copy() else { return pass }
        if pid != targetPID {
            pendingX = 0
            pendingY = 0
        }

        var factor = settings.reverse ? -1.0 : 1.0
        if let dash = settings.dashModifier, event.flags.contains(dash) {
            factor *= settings.dashFactor
            // Apps give Option/Control/Command+scroll their own meaning, so hide the key from them.
            copy.flags.remove(dash)
        }
        template = copy
        targetPID = pid

        var dy = distance(event, line: .scrollWheelEventDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1) * factor
        var dx = distance(event, line: .scrollWheelEventDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2) * factor
        if event.flags.contains(.maskShift), dx == 0 {
            (dx, dy) = (dy, 0)
        }
        pendingY = accumulate(pendingY, dy)
        pendingX = accumulate(pendingX, dx)
        startAnimating()
        return nil
    }

    private func distance(_ event: CGEvent, line: CGEventField, point: CGEventField) -> Double {
        let lines = event.getIntegerValueField(line)
        let points = event.getIntegerValueField(point)
        let sign = lines != 0 ? lines.signum() : points.signum()
        guard sign != 0 else { return 0 }
        let magnitude = max(settings.step * Double(abs(lines)), Double(abs(points)))
        return Double(sign) * magnitude * settings.speed
    }

    // Turning the wheel the other way drops the leftover glide so the page reacts at once.
    private func accumulate(_ pending: Double, _ delta: Double) -> Double {
        if delta == 0 { return pending }
        return pending * delta < 0 ? delta : pending + delta
    }

    private func resetDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        if pendingX != 0 || pendingY != 0 { startAnimating() }
    }

    private func startAnimating() {
        let now = CACurrentMediaTime()
        // Running but silent means its screen is gone; rebuild it on whichever screen is main now.
        if let link = displayLink, !link.isPaused, now - lastTick > 0.25 {
            link.invalidate()
            displayLink = nil
        }
        if displayLink?.isPaused != false { lastTick = now }
        if displayLink == nil {
            guard let screen = NSScreen.main else {
                flush()
                return
            }
            let link = screen.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    @objc private func step(_ link: CADisplayLink) {
        lastTick = CACurrentMediaTime()
        let frame = max(link.targetTimestamp - link.timestamp, 1.0 / 240)
        // Exponential ease-out that covers ~95% of the distance within `duration`.
        let progress = 1 - exp(-3 * frame / settings.duration)
        carryX += advance(&pendingX, progress)
        carryY += advance(&pendingY, progress)
        let outX = carryX.rounded(.towardZero), outY = carryY.rounded(.towardZero)
        carryX -= outX
        carryY -= outY
        if outX != 0 || outY != 0 {
            post(dx: outX, dy: outY)
        }
        if pendingX == 0 && pendingY == 0 {
            carryX = 0
            carryY = 0
            link.isPaused = true
        }
    }

    private func advance(_ pending: inout Double, _ progress: Double) -> Double {
        let move = abs(pending) < 1 ? pending : pending * progress
        pending -= move
        return move
    }

    private func flush() {
        post(dx: pendingX.rounded(), dy: pendingY.rounded())
        pendingX = 0
        pendingY = 0
    }

    // Posting a new event back into the event stream gets it re-routed and lost, so each frame is
    // a copy of the user's wheel event sent directly to the app that event was meant for.
    private func post(dx: Double, dy: Double) {
        guard targetPID != 0, let event = template?.copy() else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
        event.postToPid(targetPID)
    }

    // Read every field before writing: setting one delta field can recompute the others.
    private static func invert(_ event: CGEvent) {
        let ints: [CGEventField] = [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
        ]
        let doubles: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
        let intValues = ints.map { event.getIntegerValueField($0) }
        let doubleValues = doubles.map { event.getDoubleValueField($0) }
        for (field, value) in zip(ints, intValues) { event.setIntegerValueField(field, value: -value) }
        for (field, value) in zip(doubles, doubleValues) { event.setDoubleValueField(field, value: -value) }
    }
}
