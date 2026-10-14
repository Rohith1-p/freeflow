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

/// Custom menu bar icon: bold rounded-square badge with the wave knocked out.
/// Rendered as a TEMPLATE image (pure black + transparency) so macOS
/// adapts it automatically to dark/light menu bars.
enum MenuIcon {
    static func badge() -> NSImage {
        let pt: CGFloat = 20
        let px = pt * 3  // 3x for crisp rendering on any display
        let img = NSImage(size: NSSize(width: px, height: px))
        img.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.scaleBy(x: 3, y: 3)

            // Filled squircle badge
            let badge = CGPath(roundedRect: CGRect(x: 1, y: 1, width: pt - 2, height: pt - 2),
                               cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.addPath(badge)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))  // pure black = template
            ctx.fillPath()

            // Knock the wave out (transparent) with a bold stroke
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 3.2, y: 10.4))
            path.addCurve(to: CGPoint(x: 7.2, y: 6.2),
                          control1: CGPoint(x: 4.6, y: 8.8), control2: CGPoint(x: 5.7, y: 6.0))
            path.addCurve(to: CGPoint(x: 10.0, y: 14.6),
                          control1: CGPoint(x: 7.9, y: 6.6), control2: CGPoint(x: 8.3, y: 14.4))
            path.addCurve(to: CGPoint(x: 13.2, y: 6.6),
                          control1: CGPoint(x: 11.5, y: 14.8), control2: CGPoint(x: 12.0, y: 6.4))
            path.addCurve(to: CGPoint(x: 16.8, y: 9.8),
                          control1: CGPoint(x: 14.8, y: 6.8), control2: CGPoint(x: 15.7, y: 11.2))

            ctx.addPath(path)
            ctx.setLineWidth(2.4)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setBlendMode(.clear)
            ctx.strokePath()
            ctx.setBlendMode(.normal)
        }
        img.unlockFocus()
        img.size = NSSize(width: pt, height: pt)
        img.isTemplate = true  // macOS picks white/black automatically
        return img
    }
}
