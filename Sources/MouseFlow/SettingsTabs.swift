import AppKit
import SwiftUI
import UniformTypeIdentifiers

private var modifierOptions: [(title: String, raw: Int)] { [
    (tr("Off", "Tắt"), 0),
    ("⌥ Option", Int(CGEventFlags.maskAlternate.rawValue)),
    ("⌃ Control", Int(CGEventFlags.maskControl.rawValue)),
    ("⌘ Command", Int(CGEventFlags.maskCommand.rawValue)),
] }

func modifierBinding(get: @escaping () -> CGEventFlags?, set: @escaping (CGEventFlags?) -> Void) -> Binding<Int> {
    Binding(
        get: { Int(get()?.rawValue ?? 0) },
        set: { set($0 == 0 ? nil : CGEventFlags(rawValue: UInt64($0))) }
    )
}

struct ScrollingTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section {
                Toggle(tr("Smooth scrolling", "Cuộn mượt"), isOn: Binding(get: { settings.smooth }, set: { settings.smooth = $0 }))
                Toggle(tr("Reverse vertical scrolling", "Đảo chiều cuộn dọc"), isOn: Binding(get: { settings.reverseVertical }, set: { settings.reverseVertical = $0 }))
                Toggle(tr("Reverse horizontal scrolling", "Đảo chiều cuộn ngang"), isOn: Binding(get: { settings.reverseHorizontal }, set: { settings.reverseHorizontal = $0 }))
            }
            Section {
                SliderRow(title: tr("Speed", "Tốc độ"), value: Binding(get: { settings.speed }, set: { settings.speed = $0 }),
                          range: 0.5...3.0, step: 0.1) { String(format: "×%.1f", $0) }
                SliderRow(title: tr("Smoothness", "Độ mượt"), value: Binding(get: { settings.duration }, set: { settings.duration = $0 }),
                          range: 0.1...0.6, step: 0.05) { String(format: "%.2f s", $0) }
                SliderRow(title: tr("Fast scroll factor", "Tốc độ khi giữ phím"), value: Binding(get: { settings.dashFactor }, set: { settings.dashFactor = $0 }),
                          range: 1.5...6, step: 0.5) { String(format: "×%.1f", $0) }
            }
            Section {
                ModifierPicker(title: tr("Hold key to scroll fast", "Giữ phím để cuộn nhanh"),
                               selection: modifierBinding(get: { settings.dashModifier }, set: { settings.dashModifier = $0 }))
            }
        }
        .formStyle(.grouped)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step).frame(width: 260)
                Text(format(value)).monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
    }
}

struct ModifierPicker: View {
    let title: String
    @Binding var selection: Int

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(modifierOptions, id: \.raw) { Text($0.title).tag($0.raw) }
        }
    }
}

struct ExcludedAppsTab: View {
    @ObservedObject var settings: Settings
    @State private var selection: String?

    private var apps: [(id: String, name: String)] {
        settings.excludedApps.map { ($0.key, $0.value) }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr(
                "MouseFlow does nothing in these apps: no smooth scrolling, reversal, button mapping or hold keys. Events pass through untouched.",
                "MouseFlow không làm gì trong các app này: không cuộn mượt, không đảo chiều, không gán nút và không dùng phím giữ. Mọi thao tác được giữ nguyên."
            ))
            .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(apps, id: \.id) { app in
                        Label { Text(app.name) } icon: { AppIcon(bundleID: app.id) }.tag(app.id)
                    }
                }
                .overlay {
                    if apps.isEmpty {
                        Text(tr("No excluded apps. Click + to add one.", "Chưa có app nào. Bấm + để thêm."))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    AddAppMenu(skipping: Set(settings.excludedApps.keys)) { id, name in
                        settings.excludedApps[id] = name
                        selection = id
                    }
                    Button {
                        if let selection { settings.excludedApps[selection] = nil }
                        selection = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    .help(tr("Remove app", "Xoá app"))
                    Spacer()
                }
                .padding(8)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
        .padding(20)
    }
}

struct GeneralTab: View {
    let onLanguageChange: (Language) -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    // The state can also change from the menu or System Settings while this window is open.
    private let refresh = NotificationCenter.default.publisher(for: LaunchAtLogin.didChange)
        .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))

    var body: some View {
        Form {
            Picker(tr("Language", "Ngôn ngữ"), selection: Binding(get: { Language.current }, set: onLanguageChange)) {
                ForEach(Language.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle(tr("Launch at login", "Mở cùng macOS"), isOn: Binding(
                get: { launchAtLogin },
                set: {
                    LaunchAtLogin.set($0)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
        .onReceive(refresh) { _ in launchAtLogin = LaunchAtLogin.isEnabled }
    }
}

// Plus button listing running regular apps, with an open panel for anything else.
struct AddAppMenu: View {
    let skipping: Set<String>
    let onPick: (_ bundleID: String, _ name: String) -> Void

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !skipping.contains($0.bundleIdentifier!) && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCompare($1.localizedName ?? "") == .orderedAscending }
    }

    var body: some View {
        Menu {
            ForEach(runningApps, id: \.bundleIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier!) {
                    onPick(app.bundleIdentifier!, app.localizedName ?? app.bundleIdentifier!)
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
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return }
        onPick(bundleID, FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    }
}
