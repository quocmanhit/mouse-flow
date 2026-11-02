import AppKit
import ServiceManagement

enum LaunchAtLogin {
    // Lets the Settings window follow a change made from the menu while it stays open.
    static let didChange = Notification.Name("LaunchAtLoginDidChange")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
