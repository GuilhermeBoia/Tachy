#!/usr/bin/env swift
import AppKit

// MARK: - Tachy App Icon Generator
// Generates a macOS .icns from programmatic drawing (gradient + waveform bars).

let iconsetDir = "AppIcon.iconset"
let icnsPath = "AppIcon.icns"

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

func render(px: Int) -> Data {
    let s = CGFloat(px)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

    // --- Background rounded rect ---
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let cr = s * 0.22
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cr, yRadius: cr)

    // Gradient: warm coral → deep rose
    let gradient = NSGradient(
        starting: NSColor(red: 1.0, green: 0.40, blue: 0.26, alpha: 1.0),
        ending:   NSColor(red: 0.82, green: 0.18, blue: 0.38, alpha: 1.0)
    )!
    gradient.draw(in: bgPath, angle: -50)

    // Subtle darker edge (inner shadow illusion)
    let insetPath = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.01, dy: s * 0.01),
                                 xRadius: cr * 0.95, yRadius: cr * 0.95)
    NSColor.black.withAlphaComponent(0.08).setStroke()
    bgPath.lineWidth = s * 0.015
    bgPath.stroke()
    _ = insetPath // suppress unused warning

    // --- Waveform bars ---
    let barCount = 7
    let heights: [CGFloat] = [0.22, 0.40, 0.60, 0.85, 0.60, 0.40, 0.22]
    let barW = s * 0.07
    let gap = s * 0.04
    let totalW = CGFloat(barCount) * barW + CGFloat(barCount - 1) * gap
    let startX = (s - totalW) / 2.0
    let maxH = s * 0.48

    NSColor.white.withAlphaComponent(0.95).set()

    for i in 0..<barCount {
        let x = startX + CGFloat(i) * (barW + gap)
        let h = maxH * heights[i]
        let y = (s - h) / 2.0
        let barRect = NSRect(x: x, y: y, width: barW, height: h)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barW / 2, yRadius: barW / 2)
        barPath.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// --- Generate iconset ---
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for entry in sizes {
    let data = render(px: entry.px)
    try data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(entry.name).png"))
}

// --- Convert to .icns ---
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try proc.run()
proc.waitUntilExit()

guard proc.terminationStatus == 0 else {
    fputs("iconutil failed with status \(proc.terminationStatus)\n", stderr)
    exit(1)
}

// Cleanup
try? fm.removeItem(atPath: iconsetDir)
print("Generated \(icnsPath)")
