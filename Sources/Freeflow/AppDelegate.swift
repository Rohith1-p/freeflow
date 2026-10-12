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
                    if let wave = MenuIcon.wave() {
                        button.image = wave
                    } else {
                        button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Freeflow")
                    }
                    button.contentTintColor = nil
                }
            }
    }

    private var recordingCancellable: AnyCancellable?

    // MARK: - Windows

    @objc func showMainWindow() {
        if mainWindow == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
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

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // keep windows alive for reopen
    }
}
