import SwiftUI
import AppKit
import AVFoundation
import AVFAudio
import ApplicationServices

/// Freeflow brand palette: blue + black.
enum Brand {
    static let blue = Color(red: 0.13, green: 0.38, blue: 1.0)      // #2166FF
    static let blueSoft = Color(red: 0.13, green: 0.38, blue: 1.0).opacity(0.10)
    static let ink = Color(nsColor: .labelColor)                     // black
    static let inkDark = Color(red: 0.07, green: 0.07, blue: 0.09)   // near-black buttons
}

/// First-run flow: sidebar + content, 5 steps.
struct OnboardingView: View {
    @ObservedObject var state: AppState

    enum Step: Int, CaseIterable {
        case welcome = 0, permissions, model, trykey, ready
        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .permissions: return "Permissions"
            case .model: return "Speech Model"
            case .trykey: return "Try It"
            case .ready: return "Ready"
            }
        }
        var caption: String {
            switch self {
            case .welcome: return "A quick intro to Freeflow"
            case .permissions: return "Two system permissions"
            case .model: return "One-time 465 MB download"
            case .trykey: return "Test your dictation key"
            case .ready: return "Start dictating"
            }
        }
        var icon: String {
            switch self {
            case .welcome: return "hand.wave"
            case .permissions: return "lock.open"
            case .model: return "brain"
            case .trykey: return "keyboard"
            case .ready: return "checkmark.seal"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var micGranted = false
    @State private var axGranted = false
    @State private var micTimer: Timer?
    @State private var axTimer: Timer?
    @State private var capturedKey: UInt64?
    @State private var capturingKey = false
    @State private var keyMonitor: Any?
    @State private var practiceText = "Click here, hold ⌃ Control, and speak — your words land right here.\n"
    @ObservedObject private var store = Store.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 740, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { pollPermissions() }
        .onDisappear {
            micTimer?.invalidate(); axTimer?.invalidate()
            cancelCapture()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AppIconMark(size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Freeflow").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("First-time setup").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 20)

            Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.blue)
                .padding(.bottom, 12)

            ForEach(Step.allCases, id: \.self) { s in
                stepRow(s)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                modelStatusCard
                Label("Audio stays on your Mac.", systemImage: "lock.shield")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 212)
            }

    private func stepRow(_ s: Step) -> some View {
        let isDone = (s == .permissions && micGranted && axGranted)
            || (s == .model && state.transcriber.isReady)
            || (step.rawValue > s.rawValue && s != .welcome)
        let isCurrent = s == step

        return HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Brand.blue : (isDone ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1)))
                    .frame(width: 24, height: 24)
                Image(systemName: isDone ? "checkmark" : s.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isCurrent ? .white : (isDone ? .green : .secondary))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Brand.ink : .secondary)
                Text(s.caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            if isCurrent { RoundedRectangle(cornerRadius: 9).fill(Brand.blueSoft) }
        }
    }

    @ViewBuilder
    private var modelStatusCard: some View {
        HStack(spacing: 8) {
            switch state.transcriber.state {
            case .downloading(let p):
                ProgressView(value: p).tint(Brand.blue)
                Text("\(Int(p * 100))%").font(.system(size: 10, weight: .semibold).monospacedDigit())
            case .compiling:
                ProgressView().controlSize(.mini)
                Text("Compiling…").font(.system(size: 11, weight: .semibold))
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 13))
                Text("Model ready").font(.system(size: 11, weight: .semibold))
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 13))
                Text("Model needs attention").font(.system(size: 11, weight: .semibold))
            default:
                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary).font(.system(size: 13))
                Text("Model not downloaded").font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chipSurface(cornerRadius: 9)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed layout: every page is sized to fit — no scrolling.
            switch step {
            case .welcome: welcomePage
            case .permissions: permissionsPage
            case .model: modelPage
            case .trykey: tryKeyPage
            case .ready: readyPage
            }

            Spacer(minLength: 0)

            Divider()
            HStack {
                if step != .welcome {
                    Button("Back") { step = Step(rawValue: step.rawValue - 1)! }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if step != .ready { nextButton }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        let enabled = canAdvance
        Button {
            advance()
        } label: {
            HStack(spacing: 6) {
                Text("Continue")
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(enabled ? Brand.inkDark : Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var canAdvance: Bool {
        switch step {
        case .model: return state.transcriber.isReady
        default: return true
        }
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(alignment: .center, spacing: 0) {
            ZStack {
                rings.frame(width: 128, height: 128)
                ZStack {
                    Circle().fill(Brand.blueSoft).frame(width: 62, height: 62)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(Brand.blue)
                }
            }
            .padding(.top, 2)

            Text("Welcome to Freeflow")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .padding(.top, 10)
            Text("Hold a key, speak, and your words appear wherever your cursor is — in any app.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 3)

            HStack(alignment: .top, spacing: 12) {
                featureCard(icon: "text.cursor", title: "Dictate anywhere",
                            body: "Your words land at the cursor, in any app.")
                featureCard(icon: "lock.shield.fill", title: "Private by default",
                            body: "Speech runs on-device. Nothing leaves your Mac.")
                featureCard(icon: "bolt.fill", title: "Instant results",
                            body: "Neural Engine transcription in a blink.")
            }
            .padding(.top, 18)

            Text("Setup takes under a minute: two permissions, one key, one download.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 16)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .leading) {
                rings.opacity(0.6).frame(width: 150, height: 150).offset(x: 330, y: -20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thanks for trusting Freeflow")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Your audio and transcripts stay on this Mac.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)

            permissionCard(
                icon: "mic.fill", tag: "Required",
                title: "Hear you while you dictate",
                detail: micDenied
                    ? "Microphone access was denied. Enable it in System Settings, then come back."
                    : "Freeflow listens only while you hold your dictation key.",
                granted: micGranted,
                action: micDenied ? "Open Microphone Settings" : "Request Access",
                actionFn: micDenied ? openMicSettings : requestMic
            )
            permissionCard(
                icon: "keyboard", tag: "Required",
                title: "Use your dictation key and type into any app",
                detail: "Notice the key from any app and paste your words at the cursor.",
                granted: axGranted,
                action: "Open Settings", actionFn: openAccessibility
            )

            Label("Freeflow never asks for screen recording, contacts, or your calendar.",
                  systemImage: "checkmark.shield")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modelPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .leading) {
                rings.opacity(0.6).frame(width: 150, height: 150).offset(x: 330, y: -20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download the speech model")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Parakeet runs on your Mac's Neural Engine — then it works offline forever.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                switch state.transcriber.state {
                case .idle, .loading:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Preparing download…").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                case .downloading(let p):
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: p).tint(Brand.blue)
                        HStack {
                            Text("Downloading Parakeet v3 (~465 MB)")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(p * 100))%")
                                .font(.system(size: 13).monospacedDigit().weight(.semibold))
                        }
                    }
                case .compiling(let model):
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Compiling \(model) for the Neural Engine…")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                case .ready:
                    Label("Model ready — dictation works offline.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                case .failed(let msg):
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Download failed: \(msg)", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13)).foregroundStyle(.red)
                        Button("Retry") { Task { await state.transcriber.prepare() } }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: 12)

            Text("You can keep going through setup while it downloads.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tryKeyPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .leading) {
                rings.opacity(0.6).frame(width: 150, height: 150).offset(x: 330, y: -20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try your dictation key")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Press the real key — it lights up when Freeflow hears it, even outside this window.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)

            // Key test card
            VStack(spacing: 0) {
                HStack {
                    Label("Press your dictation key", systemImage: "scope")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    keyStatusBadge
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                keycap
                    .padding(.vertical, 10)

                HStack {
                    if capturingKey {
                        Button("Cancel") { cancelCapture() }
                            .buttonStyle(.bordered).controlSize(.small)
                        Text("Press any key now · esc cancels")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    } else {
                        Button { beginKeyCapture() } label: {
                            Label("Edit shortcut", systemImage: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        Text("or use the recommended key below")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .card(cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(state.keyIsDown ? Brand.blue : Color.clear, lineWidth: 2)
            )
            .animation(.easeOut(duration: 0.12), value: state.keyIsDown)

            HStack(spacing: 12) {
                Button {
                    applyKey(59)
                    capturedKey = 59
                } label: {
                    Text("Use ⌃ Control (recommended)")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.blueSoft))
                        .foregroundStyle(Brand.blue)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            // Practice box
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("①").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.blue)
                    Text("Dictate into this box").font(.system(size: 13, weight: .semibold))
                    if state.isRecording {
                        Text("● listening").font(.system(size: 10, weight: .semibold)).foregroundStyle(.red)
                    }
                }
                TextEditor(text: $practiceText)
                    .font(.system(size: 14))
                    .frame(height: 52)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            }
        }
    }

    private var readyPage: some View {
        VStack(alignment: .center, spacing: 0) {
            ZStack {
                rings.frame(width: 150, height: 150)
                ZStack {
                    Circle().fill(Color.green.opacity(0.12))
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.green)
                }
                .frame(width: 88, height: 88)
            }
            .padding(.top, 16)

            Text("You're all set!")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .padding(.top, 10)
            Text("Hold \(KeyNames.name(forCode: currentKey)) anywhere and speak —\nyour words land at your cursor.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            // Summary chips
            HStack(spacing: 10) {
                summaryChip(icon: "keyboard", title: "Your key",
                            value: KeyNames.name(forCode: currentKey))
                summaryChip(icon: "brain", title: "Model",
                            value: state.transcriber.isReady ? "Parakeet · ready" : "downloading…")
                summaryChip(icon: "lock.shield", title: "Privacy",
                            value: "On-device only")
            }
            .padding(.top, 18)

            Button {
                finishSetup()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("Start Dictating")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 34).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Brand.blue))
                .shadow(color: Brand.blue.opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.top, 22)

            Text("Freeflow lives in your menu bar — click the mic icon anytime.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentKey: UInt64 {
        capturedKey ?? store.settings.hotkeyKeyCode
    }

    private func finishSetup() {
        applyKey(currentKey)
        store.settings.completedOnboarding = true
        // NOTE: do NOT close the window — RootView switches to MainView
        // in place, so the app stays visible. Closing the last window of an
        // accessory app with no status item can terminate the run loop.
    }

    // MARK: - Shared pieces

    private func featureCard(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Brand.blueSoft).frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Brand.blue)
            }
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(body).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card(cornerRadius: 11)
    }

    private func summaryChip(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .chipSurface(cornerRadius: 10)
    }

    private func permissionCard(icon: String, tag: String, title: String, detail: String,
                                granted: Bool, action: String, actionFn: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(granted ? Color.green.opacity(0.12) : Brand.blueSoft)
                    .frame(width: 34, height: 34)
                Image(systemName: granted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 14))
                    .foregroundStyle(granted ? .green : Brand.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(tag)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                        .foregroundStyle(.secondary)
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button(action: actionFn) {
                    Text(action)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Brand.inkDark))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .chipSurface(cornerRadius: 10)
    }

    private var keyStatusBadge: some View {
        Group {
            if capturingKey {
                Label("Listening for key…", systemImage: "scope")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.blue)
            } else if state.keyIsDown {
                Label("Heard it!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
            } else if capturedKey != nil {
                Label("Your key works", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
            }
        }
        .transition(.opacity)
    }

    /// A keycap-style visual that fills blue while the key is held.
    private var keycap: some View {
        let lit = state.keyIsDown
        return VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(lit ? Brand.blue : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(lit ? Brand.blue : Color.secondary.opacity(0.4), lineWidth: 2)
                    )
                    .shadow(color: lit ? Brand.blue.opacity(0.45) : .black.opacity(0.12),
                            radius: lit ? 16 : 4, y: lit ? 0 : 2)
                    .frame(width: 150, height: 62)
                VStack(spacing: 2) {
                    Text(KeyNames.name(forCode: currentKey))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(lit ? "● talking" : "hold to talk")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(lit ? .white.opacity(0.85) : .secondary)
                }
                .foregroundStyle(lit ? .white : Brand.ink)
            }
            .animation(.easeOut(duration: 0.1), value: lit)
            Text("This is your key — hold it while speaking, release when done.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private var rings: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(Brand.blue.opacity(0.10 - Double(i) * 0.02), lineWidth: 1)
                    .frame(width: CGFloat(60 + i * 46), height: CGFloat(60 + i * 46))
            }
        }
    }

    // MARK: - Actions & polling

    private func pollPermissions() {
        micTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
        axTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            axGranted = AXIsProcessTrusted()
        }
    }

    private var micDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .denied
    }

    private func openMicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestMic() {
        // Modern API (macOS 14+); falls back to the legacy call.
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { _ in
                DispatchQueue.main.async {
                    micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                }
            }
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                }
            }
        }
    }

    private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func beginKeyCapture() {
        capturingKey = true
        // Modifiers (Control/Option/Shift/Cmd/fn) arrive as flagsChanged, NOT keyDown
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let code = UInt64(event.keyCode)
            let isEsc = code == 53
            DispatchQueue.main.async {
                if isEsc {
                    cancelCapture()
                } else {
                    capturedKey = code
                    applyKey(code)
                    capturingKey = false
                }
                if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
            }
            return nil  // consume so the key doesn't type into the practice box
        }
    }

    private func cancelCapture() {
        capturingKey = false
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func applyKey(_ code: UInt64) {
        state.store.settings.hotkeyKeyCode = code
        state.restartHotkey()
    }
}
