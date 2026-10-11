import AppKit

let W: CGFloat = 660, H: CGFloat = 400, scale: CGFloat = 2
let img = NSImage(size: NSSize(width: W * scale, height: H * scale))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: scale, y: scale)

// Background: soft light gradient
let bg = NSGradient(colors: [NSColor(calibratedRed: 0.97, green: 0.975, blue: 0.99, alpha: 1),
                             NSColor(calibratedRed: 0.93, green: 0.945, blue: 0.98, alpha: 1)])!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// "drag and drop" text — center, above the arrow (AppKit origin is bottom-left)
let blue = NSColor(calibratedRed: 0.13, green: 0.38, blue: 1.0, alpha: 1)
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
    .foregroundColor: blue, .paragraphStyle: para,
]
let text = "drag and drop"
let textRect = NSRect(x: 180, y: H - 165 - 18, width: 300, height: 36)
text.draw(in: textRect, withAttributes: attrs)

// Curved arrow under the text: from left (near app) curving down then up to the right (Applications)
let ink = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.12, alpha: 1)
ink.setStroke(); ink.setFill()
let path = NSBezierPath()
path.lineWidth = 4.5
path.lineCapStyle = .round
let start = NSPoint(x: 232, y: H - 245)
let end = NSPoint(x: 428, y: H - 212)
path.move(to: start)
path.curve(to: end,
           controlPoint1: NSPoint(x: 290, y: H - 290),
           controlPoint2: NSPoint(x: 380, y: H - 285))
path.stroke()

// Arrowhead at the end, oriented along the final tangent
let tangent = NSPoint(x: end.x - 380, y: end.y - (H - 285))
let angle = atan2(tangent.y, tangent.x)
let headLen: CGFloat = 16, headAngle: CGFloat = .pi / 6.5
let head = NSBezierPath()
head.move(to: end)
head.line(to: NSPoint(x: end.x - headLen * cos(angle - headAngle), y: end.y - headLen * sin(angle - headAngle)))
head.line(to: NSPoint(x: end.x - headLen * cos(angle + headAngle), y: end.y - headLen * sin(angle + headAngle)))
head.close()
head.fill()

img.unlockFocus()

// Write PNG at 144 DPI so Finder renders it crisp at 660x400 points
let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
rep.size = NSSize(width: W, height: H)  // points → 144 dpi for 2x pixels
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "/tmp/dmg-background.png"))
print("wrote /tmp/dmg-background.png")
