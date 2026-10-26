import CoreGraphics
import Foundation

final class Settings {
    private let defaults = UserDefaults.standard

    // Minimum pixels per wheel notch, so a single click still moves a readable distance.
    let step = 40.0

    init() {
        defaults.register(defaults: [
            Key.smooth: true,
            Key.reverse: false,
            Key.speed: 1.0,
            Key.duration: 0.3,
            Key.dashModifier: Int(CGEventFlags.maskAlternate.rawValue),
            Key.dashFactor: 3.0,
        ])
    }

    // Held while scrolling to multiply the distance; nil turns the shortcut off.
    var dashModifier: CGEventFlags? {
        get {
            let raw = defaults.integer(forKey: Key.dashModifier)
            return raw == 0 ? nil : CGEventFlags(rawValue: UInt64(raw))
        }
        set { defaults.set(Int(newValue?.rawValue ?? 0), forKey: Key.dashModifier) }
    }

    var dashFactor: Double {
        get { defaults.double(forKey: Key.dashFactor) }
        set { defaults.set(newValue, forKey: Key.dashFactor) }
    }

    var smooth: Bool {
        get { defaults.bool(forKey: Key.smooth) }
        set { defaults.set(newValue, forKey: Key.smooth) }
    }

    var reverse: Bool {
        get { defaults.bool(forKey: Key.reverse) }
        set { defaults.set(newValue, forKey: Key.reverse) }
    }

    var speed: Double {
        get { defaults.double(forKey: Key.speed) }
        set { defaults.set(newValue, forKey: Key.speed) }
    }

    var duration: Double {
        get { defaults.double(forKey: Key.duration) }
        set { defaults.set(newValue, forKey: Key.duration) }
    }

    private enum Key {
        static let smooth = "smooth"
        static let reverse = "reverse"
        static let speed = "speed"
        static let duration = "duration"
        static let dashModifier = "dashModifier"
        static let dashFactor = "dashFactor"
    }
}
