import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Shiro.iconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func drawIcon(_ pixels: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let bg = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 216, yRadius: 216)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.24, blue: 0.22, alpha: 1), ending: NSColor(calibratedRed: 0.055, green: 0.08, blue: 0.09, alpha: 1))!.draw(in: bg, angle: -90)
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 212, y: 425))
    p.curve(to: NSPoint(x: 227, y: 614), controlPoint1: NSPoint(x: 145, y: 520), controlPoint2: NSPoint(x: 175, y: 570))
    p.curve(to: NSPoint(x: 241, y: 838), controlPoint1: NSPoint(x: 170, y: 781), controlPoint2: NSPoint(x: 171, y: 879))
    p.curve(to: NSPoint(x: 395, y: 679), controlPoint1: NSPoint(x: 299, y: 844), controlPoint2: NSPoint(x: 359, y: 723))
    p.curve(to: NSPoint(x: 628, y: 679), controlPoint1: NSPoint(x: 467, y: 717), controlPoint2: NSPoint(x: 560, y: 711))
    p.curve(to: NSPoint(x: 796, y: 822), controlPoint1: NSPoint(x: 702, y: 780), controlPoint2: NSPoint(x: 764, y: 864))
    p.curve(to: NSPoint(x: 795, y: 604), controlPoint1: NSPoint(x: 867, y: 780), controlPoint2: NSPoint(x: 840, y: 672))
    p.curve(to: NSPoint(x: 821, y: 414), controlPoint1: NSPoint(x: 873, y: 512), controlPoint2: NSPoint(x: 870, y: 467))
    p.curve(to: NSPoint(x: 510, y: 214), controlPoint1: NSPoint(x: 821, y: 264), controlPoint2: NSPoint(x: 711, y: 220))
    p.curve(to: NSPoint(x: 212, y: 425), controlPoint1: NSPoint(x: 324, y: 216), controlPoint2: NSPoint(x: 194, y: 289)); p.close()
    NSGradient(starting: NSColor(calibratedRed: 0.76, green: 0.82, blue: 0.77, alpha: 1), ending: NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.88, alpha: 1))!.draw(in: p, angle: 90)
    NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.13, alpha: 1).setFill()
    for x in [382.0, 628.0] { NSBezierPath(roundedRect: NSRect(x: x, y: 459, width: 34, height: 61), xRadius: 17, yRadius: 17).fill() }
    let smile = NSBezierPath(); smile.move(to: NSPoint(x: 468, y: 408)); smile.curve(to: NSPoint(x: 555, y: 408), controlPoint1: NSPoint(x: 493, y: 378), controlPoint2: NSPoint(x: 533, y: 378)); smile.lineWidth = 13; smile.lineCapStyle = .round; NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.13, alpha: 1).setStroke(); smile.stroke()
    NSColor(calibratedRed: 0.81, green: 0.57, blue: 0.47, alpha: 0.32).setFill()
    for x in [284.0, 663.0] { NSBezierPath(ovalIn: NSRect(x: x, y: 425, width: 82, height: 30)).fill() }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try drawIcon(size).write(to: destination.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size * 2).write(to: destination.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
