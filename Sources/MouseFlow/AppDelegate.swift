import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private lazy var engine = ScrollEngine(settings: settings)
    private let store = MappingStore()
    private lazy var buttons = ButtonMapper(store: store)
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var settingsWindow: NSWindow?

    private let speedOptions: [(String, Double)] = [("Chậm", 0.6), ("Vừa", 1.0), ("Nhanh", 1.6), ("Rất nhanh", 2.4)]
    private let durationOptions: [(String, Double)] = [("Ít", 0.15), ("Vừa", 0.3), ("Nhiều", 0.5)]
    private let dashOptions: [(String, Double)] = [
        ("Tắt", 0),
        ("⌥ Option", Double(CGEventFlags.maskAlternate.rawValue)),
        ("⌃ Control", Double(CGEventFlags.maskControl.rawValue)),
        ("⌘ Command", Double(CGEventFlags.maskCommand.rawValue)),
    ]
    private let dashFactorOptions: [(String, Double)] = [("×2", 2), ("×3", 3), ("×5", 5)]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseFlow")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        startWhenTrusted()
        if CommandLine.arguments.contains("--settings") { openSettings() }
        // A trial run quits on its own, so a broken build can never leave the mouse dead.
        if CommandLine.arguments.contains("--trial") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { NSApp.terminate(nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        buttons.stop()
    }

    private func startWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTaps()
            return
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.startTaps()
        }
    }

    private func startTaps() {
        engine.start()
        buttons.start()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !engine.isRunning {
            menu.addItem(item("Cần cấp quyền Accessibility…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        menu.addItem(item("Cuộn mượt", #selector(toggleSmooth), on: settings.smooth))
        menu.addItem(item("Đảo chiều cuộn chuột", #selector(toggleReverse), on: settings.reverse))
        menu.addItem(.separator())
        menu.addItem(submenu("Tốc độ", speedOptions, current: settings.speed, action: #selector(setSpeed(_:))))
        menu.addItem(submenu("Độ mượt", durationOptions, current: settings.duration, action: #selector(setDuration(_:))))
        let dash = Double(settings.dashModifier?.rawValue ?? 0)
        menu.addItem(submenu("Giữ phím để cuộn nhanh", dashOptions, current: dash, action: #selector(setDashModifier(_:))))
        menu.addItem(submenu("Tốc độ khi giữ phím", dashFactorOptions, current: settings.dashFactor, action: #selector(setDashFactor(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Cài đặt nút chuột…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Mở cùng macOS", #selector(toggleLaunchAtLogin), on: SMAppService.mainApp.status == .enabled))
        let quit = NSMenuItem(title: "Thoát", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ options: [(String, Double)], current: Double, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for (label, value) in options {
            let child = item(label, action, on: abs(value - current) < 0.001)
            child.representedObject = value
            menu.addItem(child)
        }
        parent.submenu = menu
        return parent
    }

    @objc private func toggleSmooth() { settings.smooth.toggle() }

    @objc private func toggleReverse() { settings.reverse.toggle() }

    @objc private func setSpeed(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double { settings.speed = value }
    }

    @objc private func setDuration(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double { settings.duration = value }
    }

    @objc private func setDashModifier(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.dashModifier = value == 0 ? nil : CGEventFlags(rawValue: UInt64(value))
    }

    @objc private func setDashFactor(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double { settings.dashFactor = value }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow.make(store: store)
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
