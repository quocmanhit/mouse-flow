import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsWindow {
    static func make(store: MappingStore) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
        window.title = tr("Mouse Buttons", "Nút chuột")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private enum Target: Hashable {
    case defaults
    case app(String)
}

private var mouseButtons: [(number: Int, title: String)] {
    [
        (2, tr("Wheel click", "Click con lăn")),
        (3, tr("Side button (button 3)", "Nút bên hông (button 3)")),
        (4, tr("Side button (button 4)", "Nút bên hông (button 4)")),
    ]
}

private struct SettingsView: View {
    @ObservedObject var store: MappingStore
    @State private var selection: Target? = .defaults
    @State private var pressed: Int?
    @State private var buttonMonitor: Any?

    private var apps: [(id: String, mapping: AppMapping)] {
        store.mappings.apps.map { ($0.key, $0.value) }.sorted { $0.mapping.name.localizedCompare($1.mapping.name) == .orderedAscending }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 760, height: 380)
        .onAppear(perform: watchButtons)
        .onDisappear {
            if let buttonMonitor { NSEvent.removeMonitor(buttonMonitor) }
            buttonMonitor = nil
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label(tr("All apps (default)", "Mọi app (mặc định)"), systemImage: "square.grid.2x2").tag(Target.defaults)
                Section(tr("Per app", "Theo app")) {
                    ForEach(apps, id: \.id) { app in
                        Label { Text(app.mapping.name) } icon: { AppIcon(bundleID: app.id) }
                            .tag(Target.app(app.id))
                    }
                }
            }
            Divider()
            HStack(spacing: 2) {
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            add(bundleID: app.bundleIdentifier!, name: app.localizedName ?? app.bundleIdentifier!)
                        }
                    }
                    Divider()
                    Button(tr("Choose another app…", "Chọn app khác…"), action: pickApp)
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("Add app", "Thêm app"))
                Button {
                    if case .app(let id) = selection {
                        store.mappings.apps[id] = nil
                        selection = .defaults
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == .defaults || selection == nil)
                .help(tr("Remove app", "Xoá app"))
                Spacer()
            }
            .padding(8)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(mouseButtons, id: \.number) { button in
                    HStack {
                        Text(button.title)
                        Spacer()
                        ActionPicker(action: binding(button.number), placeholder: placeholder(button.number), allowsNative: selection != .defaults)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(pressed == button.number ? Color.accentColor.opacity(0.25) : Color.clear)
                    .animation(.easeOut(duration: 0.2), value: pressed)
                    if button.number != mouseButtons.last?.number { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
            Text(tr(
                "Press a mouse button to see which row it is. F-keys may act as media keys; hold fn while recording, or pick one under Single keys.",
                "Bấm một nút trên chuột để xem nó là dòng nào. Phím F trên bàn phím có thể đang là phím media; giữ fn khi ghi, hoặc chọn trong Phím đơn."
            ))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var title: String {
        switch selection {
        case .app(let id): store.mappings.apps[id]?.name ?? id
        default: tr("All apps", "Mọi app")
        }
    }

    private var subtitle: String {
        switch selection {
        case .app: tr("Buttons left unassigned here use the All apps settings.", "Nút chưa gán ở đây sẽ dùng thiết lập của Mọi app.")
        default: tr(
            "Applies to every app without its own settings. Unassigned buttons keep their normal behaviour.",
            "Áp dụng cho mọi app chưa có thiết lập riêng. Nút chưa gán giữ nguyên chức năng."
        )
        }
    }

    private func placeholder(_ button: Int) -> String {
        guard case .app = selection else { return tr("Unchanged", "Giữ nguyên") }
        let fallback = store.mappings.defaults[String(button)]?.title ?? tr("unchanged", "giữ nguyên")
        return tr("Default (\(fallback))", "Theo mặc định (\(fallback))")
    }

    private func binding(_ button: Int) -> Binding<MouseAction?> {
        let key = String(button)
        return Binding(
            get: {
                switch selection {
                case .app(let id): store.mappings.apps[id]?.buttons[key]
                default: store.mappings.defaults[key]
                }
            },
            set: { action in
                switch selection {
                case .app(let id): store.mappings.apps[id]?.buttons[key] = action
                default: store.mappings.defaults[key] = action
                }
            }
        )
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { store.mappings.apps[$0.bundleIdentifier!] == nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func add(bundleID: String, name: String) {
        if store.mappings.apps[bundleID] == nil {
            store.mappings.apps[bundleID] = AppMapping(name: name)
        }
        selection = .app(bundleID)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID: bundleID, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    }

    private func watchButtons() {
        buttonMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            let number = event.buttonNumber
            pressed = number
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if pressed == number { pressed = nil }
            }
            return event
        }
    }
}

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: "app")
        }
    }
}

private struct Preset {
    let title: String
    let shortcut: Shortcut

    init(_ title: String, _ keyCode: UInt16, _ flags: CGEventFlags = []) {
        self.title = title
        shortcut = Shortcut(keyCode: keyCode, modifiers: flags.rawValue)
    }

    static var common: [Preset] { [

        Preset(tr("Copy", "Sao chép"), 8, .maskCommand),
        Preset(tr("Paste", "Dán"), 9, .maskCommand),
        Preset(tr("Cut", "Cắt"), 7, .maskCommand),
        Preset(tr("Undo", "Hoàn tác"), 6, .maskCommand),
        Preset(tr("Redo", "Làm lại"), 6, [.maskShift, .maskCommand]),
        Preset(tr("Select all", "Chọn tất cả"), 0, .maskCommand),
        Preset(tr("Save", "Lưu"), 1, .maskCommand),
        Preset(tr("Find", "Tìm"), 3, .maskCommand),
        Preset(tr("Back", "Quay lại"), 33, .maskCommand),
        Preset(tr("Forward", "Tiến tới"), 30, .maskCommand),
        Preset(tr("New tab", "Tab mới"), 17, .maskCommand),
        Preset(tr("Close tab", "Đóng tab"), 13, .maskCommand),
        Preset(tr("Reopen closed tab", "Mở lại tab vừa đóng"), 17, [.maskShift, .maskCommand]),
        Preset(tr("Next tab", "Tab tiếp theo"), 48, .maskControl),
        Preset(tr("Previous tab", "Tab trước"), 48, [.maskControl, .maskShift]),
        Preset("Spotlight", 49, .maskCommand),
        Preset(tr("Capture part of the screen", "Chụp một vùng màn hình"), 21, [.maskShift, .maskCommand]),
        Preset(tr("Screenshot tool", "Công cụ chụp màn hình"), 23, [.maskShift, .maskCommand]),
        Preset(tr("Lock screen", "Khoá màn hình"), 12, [.maskControl, .maskCommand]),
        Preset(tr("Zoom in", "Phóng to"), 24, .maskCommand),
        Preset(tr("Zoom out", "Thu nhỏ"), 27, .maskCommand),
    ] }

    static let keys: [Preset] = [
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"), (96, "F5"), (97, "F6"),
        (98, "F7"), (100, "F8"), (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12"),
        (53, "Esc"), (36, "Enter"), (48, "Tab"), (49, "Space"), (51, "Delete"),
        (123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
        (115, "Home"), (119, "End"), (116, "Page Up"), (121, "Page Down"),
    ].map { Preset($0.1, UInt16($0.0)) }
}

private struct ActionPicker: View {
    @Binding var action: MouseAction?
    let placeholder: String
    let allowsNative: Bool
    @State private var recording = false
    @State private var recorder = KeyRecorder()

    var body: some View {
        Menu {
            Button(placeholder) { action = nil }
            if allowsNative {
                Button(MouseAction.native.title) { action = .native }
            }
            Divider()
            Menu(tr("System", "Hệ thống")) {
                ForEach(SystemAction.allCases, id: \.self) { system in
                    Button(system.title) { action = .system(system) }
                }
            }
            Menu(tr("Common shortcuts", "Phím tắt thông dụng")) {
                ForEach(Preset.common, id: \.title) { preset in
                    Button("\(preset.title)   \(preset.shortcut.display)") { action = .shortcut(preset.shortcut) }
                }
            }
            Menu(tr("Single keys", "Phím đơn")) {
                ForEach(Preset.keys, id: \.title) { preset in
                    Button(preset.title) { action = .shortcut(preset.shortcut) }
                }
            }
            Divider()
            Button(tr("Record shortcut…", "Ghi phím tắt…"), action: record)
        } label: {
            Text(recording ? tr("Press a shortcut… (Esc to cancel)", "Nhấn phím tắt… (Esc để huỷ)") : action?.title ?? placeholder)
        }
        .frame(width: 250)
        .onDisappear {
            recorder.stop()
            recording = false
        }
    }

    private func record() {
        recording = recorder.start { shortcut in
            if let shortcut { action = .shortcut(shortcut) }
            recording = false
        }
    }
}
