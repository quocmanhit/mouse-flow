import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = Settings()
    private lazy var engine = ScrollEngine(settings: settings)
    private let store = MappingStore()
    private lazy var buttons = ButtonMapper(store: store, settings: settings)
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var settingsWindow: NSWindow?
    private let nav = SettingsNav()

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
        menu.addItem(item(tr("Reverse vertical scrolling", "Đảo chiều cuộn dọc"), #selector(toggleReverseVertical), on: settings.reverseVertical))
        menu.addItem(item(tr("Reverse horizontal scrolling", "Đảo chiều cuộn ngang"), #selector(toggleReverseHorizontal), on: settings.reverseHorizontal))
        menu.addItem(.separator())
        let preferences = item(tr("Settings…", "Cài đặt…"), #selector(openSettings))
        preferences.keyEquivalent = ","
        menu.addItem(preferences)
        menu.addItem(.separator())
        menu.addItem(languageMenu())
        menu.addItem(item(tr("Launch at login", "Mở cùng macOS"), #selector(toggleLaunchAtLogin), on: LaunchAtLogin.isEnabled))
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
        changeLanguage(language)
    }

    private func changeLanguage(_ language: Language) {
        Language.saved = language
        nav.languageRevision += 1
        settingsWindow?.title = SettingsWindow.title
    }

    @objc private func toggleSmooth() { settings.smooth.toggle() }

    @objc private func toggleReverseVertical() { settings.reverseVertical.toggle() }

    @objc private func toggleReverseHorizontal() { settings.reverseHorizontal.toggle() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow.make(store: store, settings: settings, nav: nav) { [weak self] in self?.changeLanguage($0) }
            settingsWindow?.delegate = self
        }
        // A menu bar-only app may be refused focus while another app is active, leaving the window behind it.
        // Acting as a regular app while the window is open lets it come to the front reliably.
        NSApp.setActivationPolicy(.regular)
        // Wait for the status menu to finish closing, or the activation can be lost.
        DispatchQueue.main.async {
            NSApp.activate()
            self.settingsWindow?.makeKeyAndOrderFront(nil)
            self.settingsWindow?.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }
}
