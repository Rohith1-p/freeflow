import SwiftUI
import AppKit
import ServiceManagement
import AVFoundation
import AVFAudio
import ApplicationServices

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    @MainActor
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = Store.shared
    @State private var capturing = false
    @State private var monitor: Any?
    @State private var loginEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appearanceCard
                permissionsCard
                inputModeCard
                hotkeyCard
                startupCard
                modelCard
                aboutCard
            }
            .padding(.top, 40)   // clear the traffic lights (fullSizeContentView)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.sageBG)
        .onAppear {
            loginEnabled = SMAppService.mainApp.status == .enabled
            pollPermissions()
        }
        .onChange(of: loginEnabled) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                loginEnabled = SMAppService.mainApp.status == .enabled
            }
        }
        .onDisappear { if let m = monitor { NSEvent.removeMonitor(m) } }
    }

    // MARK: - Section card pieces

    private func sectionCard(icon: String, title: String, subtitle: String,
                             @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Brand.accentSoft)
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 14)
    }

    private func settingRow(title: String, detail: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 4)
    }

    private var hairline: some View {
        Divider().opacity(0.5)
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        sectionCard(icon: "circle.lefthalf.filled", title: "Appearance",
                    subtitle: "Choose how Freeflow looks.") {
            settingRow(title: "Theme", detail: "Freeflow follows your macOS look by default.") {
                Picker("", selection: Binding(
                    get: { AppTheme(rawValue: store.settings.theme) ?? .system },
                    set: { newValue in
                        store.settings.theme = newValue.rawValue
                        newValue.apply()
                    })) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .labelsHidden()
                .tint(Brand.accent)
            }
        }
    }

    // MARK: - Permissions (live status)

    @State private var micGranted = false
    @State private var axGranted = false
    @State private var permTimer: Timer?

    private func pollPermissions() {
        micGranted = OnboardingView.micAuthorized()
        axGranted = AXIsProcessTrusted()
        permTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            micGranted = OnboardingView.micAuthorized()
            axGranted = AXIsProcessTrusted()
        }
    }

    private func statusBadge(_ granted: Bool) -> some View {
        Label(granted ? "Granted" : "Not Granted",
              systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(granted ? .green : .red)
    }

    private var permissionsCard: some View {
        sectionCard(icon: "lock.shield", title: "Permissions",
                    subtitle: "Required for dictation, hotkey, and paste.") {
            settingRow(title: "Microphone",
                       detail: "Needed to capture your voice while the key is held.") {
                if micGranted {
                    statusBadge(true)
                } else if micDenied {
                    grantButton("Open Settings", action: openMicSettings)
                } else {
                    grantButton("Request Access", action: requestMicPermission)
                }
            }
            hairline
            settingRow(title: "Accessibility",
                       detail: "Global dictation key and pasting at the cursor.") {
                if axGranted {
                    statusBadge(true)
                } else {
                    grantButton("Open Settings", action: openAccessibilitySettings)
                }
            }
        }
    }

    private func grantButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Brand.inkDark))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var micDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .denied
    }

    private func requestMicPermission() {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    micGranted = granted || OnboardingView.micAuthorized()
                }
            }
        }
        state.pokeMicrophone()  // the reliable trigger for the system prompt
    }

    private func openMicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Input mode

    private var inputModeCard: some View {
        sectionCard(icon: "dot.radiowaves.left.and.right", title: "Input mode",
                    subtitle: "How you trigger dictation.") {
            Picker("", selection: Binding(
                get: { store.settings.inputMode },
                set: { newMode in
                    store.settings.inputMode = newMode
                    if newMode == .holdAndSpeak && state.isStreaming {
                        state.stopFreeflowSpeech()   // switching away stops the stream
                    }
                })) {
                ForEach(InputMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Brand.accent)

            Text(store.settings.inputMode.caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            hairline
            Toggle("Remove filler words (um, uh)", isOn: $store.settings.removeFillers)
                .font(.system(size: 13, weight: .medium))
                .tint(Brand.accent)
            Text("Applies to both modes. Filler words are stripped before text is pasted.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Hotkey

    private var hotkeyCard: some View {
        sectionCard(icon: "keyboard", title: "Dictation key",
                    subtitle: "Hold this key while speaking.") {
            settingRow(title: currentKeyName, detail: capturing ? "Press any key now · esc cancels"
                                                               : "Click Change, then press the key.") {
                Button {
                    beginCapture()
                } label: {
                    Text(capturing ? "Listening…" : "Change")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(
                            capturing ? Brand.accent : Brand.inkDark))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(capturing ? Brand.accent : Color.clear, lineWidth: 2)
                    .padding(-4)
            )
        }
    }

    private var currentKeyName: String {
        KeyNames.name(forCode: store.settings.hotkeyKeyCode)
    }

    private func beginCapture() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let code = UInt64(event.keyCode)
            DispatchQueue.main.async {
                if code != 53 {  // esc cancels
                    store.settings.hotkeyKeyCode = code
                    state.restartHotkey()
                }
                capturing = false
                if let m = self.monitor { NSEvent.removeMonitor(m); self.monitor = nil }
            }
            return nil
        }
    }

    // MARK: - Startup & general

    private var startupCard: some View {
        sectionCard(icon: "power", title: "Startup",
                    subtitle: "How Freeflow starts on your Mac.") {
            settingRow(title: "Your name",
                       detail: "Used in the greeting on your dashboard.") {
                TextField("Your name", text: $store.settings.userName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
            }
            hairline
            settingRow(title: "Launch at login",
                       detail: "Start Freeflow automatically when you sign in.") {
                Toggle("", isOn: $loginEnabled)
                    .labelsHidden()
                    .tint(Brand.accent)
            }
            hairline
            settingRow(title: "Save dictations to history",
                       detail: "Keep a local log you can browse and copy.") {
                Toggle("", isOn: Binding(
                    get: { store.settings.showInHistory },
                    set: { store.settings.showInHistory = $0 }))
                    .labelsHidden()
                    .tint(Brand.accent)
            }
        }
    }

    // MARK: - Model

    private var modelCard: some View {
        sectionCard(icon: "brain", title: "Speech model",
                    subtitle: "Parakeet TDT — runs on the Neural Engine.") {
            HStack {
                switch state.transcriber.state {
                case .ready:
                    Label("Ready — works offline", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                case .downloading(let p):
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Downloading… \(Int(p * 100))%").font(.system(size: 12))
                        ProgressView(value: p).tint(Brand.accent)
                    }
                case .compiling:
                    Label("Compiling for Neural Engine…", systemImage: "gearshape.2")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                case .failed:
                    Label("Not downloaded", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                default:
                    Label("Not downloaded", systemImage: "arrow.down.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if !state.transcriber.isReady {
                    Button("Download") { Task { await state.transcriber.prepare() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Brand.accent)
                }
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        sectionCard(icon: "info.circle", title: "About",
                    subtitle: "Freeflow 2.0.0 — native Swift.") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Everything runs on your Mac. No cloud, no account.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Engine: Parakeet TDT via FluidAudio (Apache-2.0) · MIT licensed")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }
}
