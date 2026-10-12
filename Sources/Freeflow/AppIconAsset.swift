import AppKit
import SwiftUI

/// Safe resource lookup. NEVER use SwiftPM's `Bundle.module` in a shipped
/// app: its generated accessor falls back to a hard-coded path inside the
/// developer's build folder and calls fatalError() when that's missing —
/// which crashed the app on every Mac except the dev machine.
enum AppResources {
    private static let spmBundleName = "Freeflow_Freeflow.bundle"

    /// Candidate bundles, in order: the app's own Resources, the SPM resource
    /// bundle inside Resources (shipped), the SPM bundle next to the
    /// executable (dev builds). All optional — missing is never fatal.
    private static let bundles: [Bundle] = {
        var found: [Bundle] = [Bundle.main]
        if let r = Bundle.main.resourceURL,
           let b = Bundle(url: r.appendingPathComponent(spmBundleName)) {
            found.append(b)
        }
        if let exe = Bundle.main.executableURL {
            let dev = exe.deletingLastPathComponent().appendingPathComponent(spmBundleName)
            if let b = Bundle(url: dev) { found.append(b) }
        }
        return found
    }()

    static func url(_ name: String, ext: String) -> URL? {
        for b in bundles {
            if let u = b.url(forResource: name, withExtension: ext) { return u }
            // SPM copies the Resources dir as-is: look inside "Resources/" too
            if let u = b.url(forResource: name, withExtension: ext, subdirectory: "Resources") { return u }
        }
        return nil
    }
}

/// The Freeflow app icon, for in-app brand marks.
/// PNG first — SwiftUI's renderer can't texture the icns legacy rep types
/// reliably; a plain PNG always renders.
enum AppIconAsset {
    static let image: NSImage? =
        AppResources.url("AppIcon1024", ext: "png").flatMap { NSImage(contentsOf: $0) }
        ?? AppResources.url("AppIcon", ext: "icns").flatMap { NSImage(contentsOf: $0) }
}

/// In-app brand mark: the bundled wave icon, rounded like an app icon.
struct AppIconMark: View {
    var size: CGFloat

    var body: some View {
        if let img = AppIconAsset.image {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        } else {
            Image(systemName: "waveform")
                .font(.system(size: size * 0.5))
                .foregroundStyle(Brand.blue)
                .frame(width: size, height: size)
        }
    }
}

/// Custom menu bar icon: the real wave PNG (transparent background, gradient).
enum MenuIcon {
    static func wave() -> NSImage? {
        guard let url = AppResources.url("menubar-32", ext: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        img.isTemplate = false  // keep the brand gradient colors
        return img
    }
}
