import SwiftUI
import AppKit

/// Floating, click-through, non-focus-stealing recording indicator.
/// Shows while dictating (live mic level) and during transcription.
final class RecordingOverlay {
    private var panel: NSPanel?

    func show(listening: Bool) {
        DispatchQueue.main.async { [self] in
            if panel == nil { create() }
            update { $0.phase = listening ? .listening : .transcribing }
            panel?.orderFrontRegardless()
        }
    }

    func updateLevel(_ rms: Float) {
        DispatchQueue.main.async { [self] in
            // Only when visible; cheap no-op otherwise
            guard panel?.isVisible == true else { return }
            update { $0.micLevel = Double(rms) }
        }
    }

    func hide() {
        DispatchQueue.main.async { [self] in
            panel?.orderOut(nil)
        }
    }

    /// SwiftUI views are values: mutate a copy and reassign through the host.
    private func update(_ transform: (inout OverlayView) -> Void) {
        guard let hosting = panel?.contentView as? NSHostingView<OverlayView> else { return }
        var view = hosting.rootView
        transform(&view)
        hosting.rootView = view
    }

    private func create() {
        let view = OverlayView()
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true          // click-through: never steal clicks
        panel.hasShadow = false
        panel.contentView = hosting
        // Position: bottom-center of the main display
        if let screen = NSScreen.main {
            let midX = screen.frame.midX - 125
            panel.setFrameOrigin(NSPoint(x: midX, y: screen.frame.minY + 96))
        }
        self.panel = panel
    }
}

/// The pill itself.
struct OverlayView: View {
    enum Phase { case listening, transcribing }
    var phase: OverlayView.Phase = .listening
    @State var micLevel: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            switch phase {
            case .listening:
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                LevelBars(level: micLevel)
                    .frame(width: 42)
                Text("Listening…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            case .transcribing:
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Transcribing…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassCapsule()
        .background(
            // Dark tint behind the glass keeps white text readable over any app
            Capsule().fill(Color.black.opacity(0.35))
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        .overlay(
            Capsule().stroke(Brand.blue.opacity(0.5), lineWidth: 1)
        )
    }
}

/// Animated level bars driven by live mic RMS.
struct LevelBars: View {
    var level: Double  // 0...1 raw RMS (typically 0...0.3)
    @State private var tick = 0

    private var normalized: Double {
        min(1, max(0.06, Double(level) * 6))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let wobble = 0.55 + 0.45 * sin(t * (6.0 + Double(i) * 1.7) + Double(i))
                    let height = 10 * normalized * max(0.35, wobble) + 4
                    Capsule()
                        .fill(Brand.blue)
                        .frame(width: 4, height: height)
                }
            }
            .frame(height: 22)
        }
    }
}
