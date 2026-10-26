import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    let state = AppState()
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)  // Dock icon + menu bar icon
        AppTheme(rawValue: Store.shared.settings.theme)?.apply()
        NSLog("[Freeflow] accent = \(Brand.accent)")
        // Guarantee the wave shows in the Dock even if the icns is odd
        if let icon = AppIconAsset.image {
            NSApp.applicationIconImage = icon
        }
        installStatusItem()
        state.startEngine()

        // Warm the model in the background after launch
        Task { await state.transcriber.prepare() }

        // Always show the main window on launch — users expect to see the app
        showMainWindow()

        // In-app triggers for note sessions
        NotificationCenter.default.addObserver(forName: .init("FreeflowToggleNotes"), object: nil, queue: .main) { [weak self] _ in
            self?.toggleNotes()
        }

    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // stay alive in the menu bar
    }

    // MARK: - Status bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "FreeflowStatusItem"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Freeflow")
            button.image?.isTemplate = true
        } else {
            NSLog("[Freeflow] WARNING: status item has no button")
        }
        statusItem = item
        let menu = NSMenu()

        let mainItem = NSMenuItem(title: "Open Freeflow", action: #selector(showMainWindow), keyEquivalent: "")
        mainItem.target = self
        menu.addItem(mainItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let notesItem = NSMenuItem(title: "Start Note Session", action: #selector(toggleNotes), keyEquivalent: "n")
        notesItem.target = self
        menu.addItem(notesItem)

        let copyRecentItem = NSMenuItem(title: "Copy Last Dictation", action: #selector(copyRecent), keyEquivalent: "c")
        copyRecentItem.target = self
        menu.addItem(copyRecentItem)

        menu.addItem(.separator())

        let statusLine = NSMenuItem(title: "Hold ⌃ Control and speak", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Freeflow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item

        // Menu bar icon reacts to recording state
        recordingCancellable = state.$isRecording
            .combineLatest(state.$keyIsDown)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording, keyDown in
                guard let button = self?.statusItem?.button else { return }
                if recording || keyDown {
                    button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording")
                    button.contentTintColor = .systemRed
                } else {
                    button.image = MenuIcon.badge()
                    button.contentTintColor = nil
                }
            }
    }

    private var recordingCancellable: AnyCancellable?

    // MARK: - Windows

    @objc func showMainWindow() {
        if mainWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
            win.title = "Freeflow"
            win.titlebarAppearsTransparent = true
            win.titlebarSeparatorStyle = .none
            win.backgroundColor = .clear
            win.isMovableByWindowBackground = true
            win.contentView = NSHostingView(rootView: RootView(state: state))
            win.center()
            win.delegate = self
            win.isReleasedWhenClosed = false
            mainWindow = win
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Settings now live INSIDE the main window (sidebar navigation).
    @objc func showSettings() {
        UIRouter.shared.page = .settings
        showMainWindow()
    }

    /// Single save path: stops the engine, persists the session, hides the window.
    private func finishNotesSession() {
        guard state.notes.isRunning else { return }
        let lines = state.notes.stop()
        if !lines.isEmpty {
            let session = NoteSession(
                id: UUID(),
                startedAt: state.notes.sessionStartedAt ?? Date(),
                durationSeconds: state.notes.elapsed,
                lines: lines)
            state.store.addNote(session)
        }
    }

    @objc func toggleNotes() {
        if state.notes.isRunning {
            finishNotesSession()
        } else {
            guard state.transcriber.isReady else {
                state.lastError = "Model still loading — try again in a moment"
                return
            }
            state.notes.transcriber = state.transcriber
            Task { await state.notes.start() }
            UIRouter.shared.page = .notes
            showMainWindow()
        }
    }

    /// Copies the most recent dictation to the clipboard — recovery path
    /// when a paste didn't land in the target app.
    @objc func copyRecent() {
        guard let last = Store.shared.entries.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.text, forType: .string)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // keep windows alive for reopen
    }
}
