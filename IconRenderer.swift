// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

private struct IconSize {
    let fileName: String
    let pixels: Int
}

private let sizes = [
    IconSize(fileName: "icon_16x16.png", pixels: 16),
    IconSize(fileName: "icon_16x16@2x.png", pixels: 32),
    IconSize(fileName: "icon_32x32.png", pixels: 32),
    IconSize(fileName: "icon_32x32@2x.png", pixels: 64),
    IconSize(fileName: "icon_128x128.png", pixels: 128),
    IconSize(fileName: "icon_128x128@2x.png", pixels: 256),
    IconSize(fileName: "icon_256x256.png", pixels: 256),
    IconSize(fileName: "icon_256x256@2x.png", pixels: 512),
    IconSize(fileName: "icon_512x512.png", pixels: 512),
    IconSize(fileName: "icon_512x512@2x.png", pixels: 1024),
]

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift IconRenderer.swift OUTPUT_ICONSET\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for size in sizes {
    let destination = outputDirectory.appendingPathComponent(size.fileName)
    try renderIcon(pixels: size.pixels, to: destination)
}

private func renderIcon(pixels: Int, to destination: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "UsagePie.IconRenderer", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics

    let scale = CGFloat(pixels)
    let iconRect = CGRect(x: scale * 0.055, y: scale * 0.055,
                          width: scale * 0.89, height: scale * 0.89)
    let cornerRadius = scale * 0.205
    let backgroundPath = NSBezierPath(roundedRect: iconRect,
                                      xRadius: cornerRadius, yRadius: cornerRadius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = scale * 0.035
    shadow.shadowOffset = CGSize(width: 0, height: -scale * 0.018)
    shadow.set()

    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.94, alpha: 1),
        ending: NSColor(calibratedRed: 0.83, green: 0.82, blue: 0.79, alpha: 1)
    )!
    gradient.draw(in: backgroundPath, angle: -90)

    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0)
    NSColor.black.withAlphaComponent(0.13).setStroke()
    backgroundPath.lineWidth = max(1, scale * 0.006)
    backgroundPath.stroke()

    let context = graphics.cgContext
    let center = CGPoint(x: scale / 2, y: scale / 2)
    let outerRadius = scale * 0.325
    let innerRadius = scale * 0.185
    let segmentAngle = CGFloat.pi * 2 / 7
    let gap = max(0.022, scale > 64 ? 0.032 : 0.055)
    let startAt = -CGFloat.pi / 2

    for index in 0..<7 {
        let start = startAt + CGFloat(index) * segmentAngle + gap
        let end = startAt + CGFloat(index + 1) * segmentAngle - gap
        let path = CGMutablePath()
        path.addArc(center: center, radius: outerRadius,
                    startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius,
                    startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()

        let color = index == 0
            ? NSColor(calibratedWhite: 0.58, alpha: 1)
            : NSColor(calibratedRed: 0.985, green: 0.975, blue: 0.945, alpha: 1)
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    let centerRect = CGRect(x: center.x - innerRadius * 0.88,
                            y: center.y - innerRadius * 0.88,
                            width: innerRadius * 1.76,
                            height: innerRadius * 1.76)
    context.setFillColor(NSColor(calibratedWhite: 0.24, alpha: 1).cgColor)
    context.fillEllipse(in: centerRect)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "UsagePie.IconRenderer", code: 2)
    }
    try png.write(to: destination, options: .atomic)
}
