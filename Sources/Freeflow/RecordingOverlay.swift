import SwiftUI
import AppKit

/// Floating, click-through, non-focus-stealing recording indicator.
/// Shows while dictating (live mic level) and during transcription.
final class RecordingOverlay {
    private var panel: NSPanel?

    func show(listening: Bool, key: String? = nil) {
        DispatchQueue.main.async { [self] in
            if panel == nil { create() }
            update {
                $0.phase = listening ? .listening : .transcribing
                if listening, let key { $0.keyLabel = key }
            }
            panel?.orderFrontRegardless()
        }
    }

    func updateLevel(_ rms: Float) {
        DispatchQueue.main.async { [self] in
            // Only when visible; cheap no-op otherwise.
            // Gain: raw speech RMS is ~0.01-0.15; scale into a lively 0...1 range.
            guard panel?.isVisible == true else { return }
            update { $0.micLevel = Double(min(1.0, Double(rms) * 9.0)) }
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
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 70),
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
            let midX = screen.frame.midX - 150
            panel.setFrameOrigin(NSPoint(x: midX, y: screen.frame.minY + 100))
        }
        self.panel = panel
    }
}

/// The pill itself.
struct OverlayView: View {
    enum Phase { case listening, transcribing }
    var phase: OverlayView.Phase = .listening
    var keyLabel: String = ""
    // Plain var (NOT @State): we drive it from outside via rootView updates.
    // @State ignores externally injected values after first render — that
    // froze the level bars at their idle height.
    var micLevel: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            switch phase {
            case .listening:
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                LevelBars(level: micLevel)
                    .frame(width: 46)
                Text("Listening")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                if !keyLabel.isEmpty {
                    Text(keyLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.blue)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.92)))
                        .lineLimit(1)
                        .fixedSize()
                }
            case .transcribing:
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
                Text("Transcribing…")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            Capsule().fill(Brand.inkDark.opacity(0.96))
                .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        )
        .overlay(
            Capsule().strokeBorder(Brand.blue.opacity(0.45), lineWidth: 1)
        )
    }
}

/// Animated level bars driven by live mic RMS.
struct LevelBars: View {
    var level: Double  // 0...1, already gain-adjusted

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (6.5 + Double(i) * 2.3) + Double(i) * 1.7
                    let ambient = 0.5 + 0.5 * sin(phase)          // 0...1, always alive
                    let drive = level * (0.6 + 0.4 * ambient)     // voice modulates on top
                    let height = 5.0 + 17.0 * min(1.0, drive)
                    Capsule()
                        .fill(Brand.blue)
                        .frame(width: 4, height: height)
                        .animation(.spring(response: 0.16, dampingFraction: 0.5), value: height)
                }
            }
            .frame(width: 46, height: 24, alignment: .center)
        }
    }
}
