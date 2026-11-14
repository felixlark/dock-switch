import AppKit
// Reproducible identity: a split window with three adjustment sliders.
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.30, blue: 0.78, alpha: 1), ending: NSColor(srgbRed: 0.16, green: 0.66, blue: 0.98, alpha: 1))!.draw(in: tile, angle: 70)
    NSColor.white.setStroke()
    let window = NSBezierPath(roundedRect: NSRect(x: 218, y: 250, width: 588, height: 524), xRadius: 46, yRadius: 46)
    window.lineWidth = 34; window.stroke()
    let lines = NSBezierPath(); lines.lineWidth = 28; lines.lineCapStyle = .round
    lines.move(to: NSPoint(x: 218, y: 666)); lines.line(to: NSPoint(x: 806, y: 666))
    lines.move(to: NSPoint(x: 410, y: 250)); lines.line(to: NSPoint(x: 410, y: 666))
    for y in [558, 458, 358] { lines.move(to: NSPoint(x: 490, y: y)); lines.line(to: NSPoint(x: 728, y: y)) }
    lines.stroke()
    NSColor.white.setFill()
    for (x,y) in [(558,558),(658,458),(588,358)] { NSBezierPath(ovalIn: NSRect(x:x-27,y:y-27,width:54,height:54)).fill() }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size).png"))
}
