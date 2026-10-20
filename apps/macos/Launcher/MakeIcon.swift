import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.04, y: p * 0.04, width: p * 0.92, height: p * 0.92),
                     xRadius: p * 0.21, yRadius: p * 0.21).fill()
        NSColor(calibratedRed: 0.77, green: 0.83, blue: 0.65, alpha: 1).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: p * 0.17, y: p * 0.17, width: p * 0.66, height: p * 0.66))
        ring.lineWidth = p * 0.025
        ring.stroke()
        NSColor(calibratedRed: 0.77, green: 0.83, blue: 0.65, alpha: 1).setFill()
        let mountain = NSBezierPath()
        mountain.move(to: NSPoint(x: p * 0.24, y: p * 0.33))
        mountain.line(to: NSPoint(x: p * 0.44, y: p * 0.69))
        mountain.line(to: NSPoint(x: p * 0.57, y: p * 0.48))
        mountain.line(to: NSPoint(x: p * 0.66, y: p * 0.60))
        mountain.line(to: NSPoint(x: p * 0.79, y: p * 0.33))
        mountain.close()
        mountain.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
