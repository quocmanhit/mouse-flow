import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private lazy var engine = ScrollEngine(settings: settings)
    private let store = MappingStore()
    private lazy var buttons = ButtonMapper(store: store, settings: settings)
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var settingsWindow: NSWindow?

    private var speedOptions: [(String, Double)] {
        [(tr("Slow", "Chậm"), 0.6), (tr("Medium", "Vừa"), 1.0), (tr("Fast", "Nhanh"), 1.6), (tr("Very fast", "Rất nhanh"), 2.4)]
    }
    private var durationOptions: [(String, Double)] {
        [(tr("Low", "Ít"), 0.15), (tr("Medium", "Vừa"), 0.3), (tr("High", "Nhiều"), 0.5)]
    }
    private var modifierOptions: [(String, Double)] { [
        (tr("Off", "Tắt"), 0),
        ("⌥ Option", Double(CGEventFlags.maskAlternate.rawValue)),
        ("⌃ Control", Double(CGEventFlags.maskControl.rawValue)),
        ("⌘ Command", Double(CGEventFlags.maskCommand.rawValue)),
    ] }
    private let dashFactorOptions: [(String, Double)] = [("×2", 2), ("×3", 3), ("×5", 5)]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        if Language.saved == nil { askLanguage() }
        startWhenTrusted()
        if CommandLine.arguments.contains("--settings") { openSettings() }
        // A trial run quits on its own, so a broken build can never leave the mouse dead.
        if CommandLine.arguments.contains("--trial") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { NSApp.terminate(nil) }
        }
    }

    // The bundled icon only exists in the packaged app; `swift run` falls back to an SF Symbol.
    private static func menuBarIcon() -> NSImage? {
        guard let icon = NSImage(named: "MenuBarIconTemplate") else {
            return NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseFlow")
        }
        icon.isTemplate = true
        icon.size = NSSize(width: 18, height: 18)
        icon.accessibilityDescription = "MouseFlow"
        return icon
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
            menu.addItem(item(tr("Grant Accessibility permission…", "Cần cấp quyền Accessibility…"), #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        menu.addItem(item(tr("Smooth scrolling", "Cuộn mượt"), #selector(toggleSmooth), on: settings.smooth))
        menu.addItem(item(tr("Reverse mouse scrolling", "Đảo chiều cuộn chuột"), #selector(toggleReverse), on: settings.reverse))
        menu.addItem(.separator())
        menu.addItem(submenu(tr("Speed", "Tốc độ"), speedOptions, current: settings.speed, action: #selector(setSpeed(_:))))
        menu.addItem(submenu(tr("Smoothness", "Độ mượt"), durationOptions, current: settings.duration, action: #selector(setDuration(_:))))
        let dash = Double(settings.dashModifier?.rawValue ?? 0)
        menu.addItem(submenu(tr("Hold key to scroll fast", "Giữ phím để cuộn nhanh"), modifierOptions, current: dash, action: #selector(setDashModifier(_:))))
        menu.addItem(submenu(tr("Fast scroll factor", "Tốc độ khi giữ phím"), dashFactorOptions, current: settings.dashFactor, action: #selector(setDashFactor(_:))))
        menu.addItem(.separator())
        menu.addItem(item(tr("Mouse button settings…", "Cài đặt nút chuột…"), #selector(openSettings)))
        let bypass = Double(settings.bypassModifier?.rawValue ?? 0)
        menu.addItem(submenu(tr("Hold key for native buttons", "Giữ phím để dùng nút gốc"), modifierOptions, current: bypass, action: #selector(setBypassModifier(_:))))
        menu.addItem(.separator())
        menu.addItem(languageMenu())
        menu.addItem(item(tr("Launch at login", "Mở cùng macOS"), #selector(toggleLaunchAtLogin), on: SMAppService.mainApp.status == .enabled))
        let quit = NSMenuItem(title: tr("Quit MouseFlow", "Thoát"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    // The title stays bilingual so the menu can be found whatever language is active.
    private func languageMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Language / Ngôn ngữ", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for language in Language.allCases {
            let child = item(language.title, #selector(setLanguage(_:)), on: language == Language.current)
            child.representedObject = language.rawValue
            menu.addItem(child)
        }
        parent.submenu = menu
        return parent
    }

    private func askLanguage() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Choose a language / Chọn ngôn ngữ"
        alert.informativeText = "You can change it later from the menu bar.\nCó thể đổi lại trong menu trên thanh menu."
        for language in Language.allCases { alert.addButton(withTitle: language.title) }
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        Language.saved = Language.allCases.indices.contains(index) ? Language.allCases[index] : .english
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = Language(rawValue: raw) else { return }
        Language.saved = language
        // SwiftUI reads strings when the window is built, so rebuild it in the new language.
        settingsWindow?.close()
        settingsWindow = nil
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

    @objc private func setBypassModifier(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.bypassModifier = value == 0 ? nil : CGEventFlags(rawValue: UInt64(value))
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
