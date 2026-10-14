import SwiftUI
import AppKit

/// Freeflow design system — Witlore-inspired:
/// sage surfaces, deep ink, warm orange accent. Inter Tight + IBM Plex Mono.
enum Brand {
    // MARK: - Fonts

    private static var fontsRegistered = false

    /// All candidate resource bundles (app Resources + SPM bundle).
    private static var resourceBundles: [Bundle] {
        var found: [Bundle] = [Bundle.main]
        if let r = Bundle.main.resourceURL,
           let b = Bundle(url: r.appendingPathComponent("Freeflow_Freeflow.bundle")) {
            found.append(b)
        }
        if let exe = Bundle.main.executableURL {
            let dev = exe.deletingLastPathComponent().appendingPathComponent("Freeflow_Freeflow.bundle")
            if let b = Bundle(url: dev) { found.append(b) }
        }
        return found
    }

    /// Registers bundled Inter Tight + IBM Plex Mono. Call once at launch.
    static func registerFonts() {
        guard !fontsRegistered else { return }
        fontsRegistered = true
        registerFontsIn(Bundle.main)
        for b in resourceBundles { registerFontsIn(b) }
    }

    private static func registerFontsIn(_ bundle: Bundle) {
        let fm = FileManager.default
        // SPM .copy keeps the "Resources" dir; packaged apps put fonts directly in Contents/Resources
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Fonts"),
            bundle.url(forResource: "Fonts", withExtension: nil, subdirectory: "Resources"),
            bundle.resourceURL,
        ].compactMap { $0 }
        for dir in candidates {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// Inter Tight text.
    static func f(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.custom("Inter Tight", size: size).weight(weight)
    }

    /// IBM Plex Mono labels.
    static func mono(_ size: CGFloat) -> Font {
        Font.custom("IBM Plex Mono", size: size)
    }

    // MARK: - Palette (light/dark adaptive)

    private static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return NSColor(hex: isDark ? dark : light)
        })
    }

    /// Warm orange — buttons, links, accents.
    static let accent = Color(hex: "E8663A")
    static let accentSoft = Color(hex: "E8663A").opacity(0.10)

    /// Deep ink (text, headings).
    static let ink = dynamic(light: "202D28", dark: "E9EFE9")
    static let inkSoft = dynamic(light: "55604D", dark: "9AA79E")

    /// Sage surfaces.
    static let sageBG = dynamic(light: "F2F3EC", dark: "14181A")
    static let card = dynamic(light: "FAFBF7", dark: "1B2220")
    static let line = dynamic(light: "D3D6CA", dark: "2A3230")

    /// Dark capsule (recording pill).
    static let inkDark = Color(hex: "161B19")

    // Legacy aliases used across views (accent swap).
    static let blue = accent
    static let blueSoft = accentSoft
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        let red = Double(r) / 255.0
        let green = Double(g) / 255.0
        let blue = Double(b) / 255.0
        let alpha = Double(a) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}
