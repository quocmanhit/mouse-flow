import CoreGraphics
import Foundation

final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    // Minimum pixels per wheel notch, so a single click still moves a readable distance.
    let step = 40.0

    // Bumped whenever the excluded list changes, so per-pid caches in the event taps know to refill.
    private(set) var excludedRevision = 0

    // Bundle ID to display name. Kept in memory because the scroll tap consults it on every wheel event.
    var excludedApps: [String: String] {
        willSet { objectWillChange.send() }
        didSet {
            defaults.set(excludedApps, forKey: Key.excludedApps)
            excludedRevision += 1
        }
    }

    init() {
        // Runs before register(defaults:), which would make the unset new keys look set.
        if defaults.object(forKey: Key.reverse) != nil {
            if defaults.bool(forKey: Key.reverse),
               defaults.object(forKey: Key.reverseVertical) == nil, defaults.object(forKey: Key.reverseHorizontal) == nil {
                defaults.set(true, forKey: Key.reverseVertical)
                defaults.set(true, forKey: Key.reverseHorizontal)
            }
            defaults.removeObject(forKey: Key.reverse)
        }
        excludedApps = defaults.dictionary(forKey: Key.excludedApps) as? [String: String] ?? [:]
        defaults.register(defaults: [
            Key.smooth: true,
            Key.reverseVertical: false,
            Key.reverseHorizontal: false,
            Key.speed: 1.0,
            Key.duration: 0.3,
            Key.dashModifier: Int(CGEventFlags.maskAlternate.rawValue),
            Key.dashFactor: 3.0,
            Key.bypassModifier: Int(CGEventFlags.maskControl.rawValue),
            Key.defaultsModifier: Int(CGEventFlags.maskAlternate.rawValue),
        ])
    }

    // Held while scrolling to multiply the distance; nil turns the shortcut off.
    var dashModifier: CGEventFlags? {
        get {
            let raw = defaults.integer(forKey: Key.dashModifier)
            return raw == 0 ? nil : CGEventFlags(rawValue: UInt64(raw))
        }
        set { objectWillChange.send(); defaults.set(Int(newValue?.rawValue ?? 0), forKey: Key.dashModifier) }
    }

    // Held while clicking to skip button mappings and keep the button's own behaviour; nil turns it off.
    var bypassModifier: CGEventFlags? {
        get {
            let raw = defaults.integer(forKey: Key.bypassModifier)
            return raw == 0 ? nil : CGEventFlags(rawValue: UInt64(raw))
        }
        set { objectWillChange.send(); defaults.set(Int(newValue?.rawValue ?? 0), forKey: Key.bypassModifier) }
    }

    // Held while clicking to use the "every app" mappings instead of the app's own; nil turns it off.
    var defaultsModifier: CGEventFlags? {
        get {
            let raw = defaults.integer(forKey: Key.defaultsModifier)
            return raw == 0 ? nil : CGEventFlags(rawValue: UInt64(raw))
        }
        set { objectWillChange.send(); defaults.set(Int(newValue?.rawValue ?? 0), forKey: Key.defaultsModifier) }
    }

    var dashFactor: Double {
        get { defaults.double(forKey: Key.dashFactor) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.dashFactor) }
    }

    var smooth: Bool {
        get { defaults.bool(forKey: Key.smooth) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.smooth) }
    }

    var reverseVertical: Bool {
        get { defaults.bool(forKey: Key.reverseVertical) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.reverseVertical) }
    }

    var reverseHorizontal: Bool {
        get { defaults.bool(forKey: Key.reverseHorizontal) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.reverseHorizontal) }
    }

    var speed: Double {
        get { defaults.double(forKey: Key.speed) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.speed) }
    }

    var duration: Double {
        get { defaults.double(forKey: Key.duration) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.duration) }
    }

    func isExcluded(bundleID: String?) -> Bool {
        bundleID.map { excludedApps[$0] != nil } ?? false
    }

    private enum Key {
        static let smooth = "smooth"
        static let reverse = "reverse"
        static let reverseVertical = "reverseVertical"
        static let reverseHorizontal = "reverseHorizontal"
        static let excludedApps = "excludedApps"
        static let speed = "speed"
        static let duration = "duration"
        static let dashModifier = "dashModifier"
        static let dashFactor = "dashFactor"
        static let bypassModifier = "bypassModifier"
        static let defaultsModifier = "defaultsModifier"
    }
}
