import AppKit
import SwiftUI

/// The Freeflow app icon (bundled), for in-app brand marks.
enum AppIconAsset {
    static let image: NSImage? = Bundle.module
        .url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }
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
        guard let url = Bundle.module.url(forResource: "menubar-32", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        img.isTemplate = false  // keep the brand gradient colors
        return img
    }
}
