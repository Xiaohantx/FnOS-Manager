import AppKit

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourcePath = projectRoot.appendingPathComponent("Resources/logo_source.jpg").path
guard let srcImage = NSImage(contentsOfFile: sourcePath),
      let srcTiff = srcImage.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcTiff),
      let srcCG = srcRep.cgImage else {
    fatalError("Failed to load source logo image")
}

// Crop exact squircle region (102, 102, 820, 820) from 1024x1024 image
let cropRect = CGRect(x: 102, y: 102, width: 820, height: 820)
guard let croppedCG = srcCG.cropping(to: cropRect) else {
    fatalError("Failed to crop source logo")
}
let croppedNSImage = NSImage(cgImage: croppedCG, size: NSSize(width: 820, height: 820))

func renderTransparentSquircleIcon(canvasSize: Int, insetRatio: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasSize,
        pixelsHigh: canvasSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvasSize, height: canvasSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(canvasSize)
    let margin = s * insetRatio
    let boxSize = s - margin * 2.0
    let boxRect = NSRect(x: margin, y: margin, width: boxSize, height: boxSize)
    let cornerRadius = boxSize * 0.225

    let clipPath = NSBezierPath(roundedRect: boxRect, xRadius: cornerRadius, yRadius: cornerRadius)
    clipPath.addClip()

    croppedNSImage.draw(
        in: boxRect,
        from: NSRect(x: 0, y: 0, width: 820, height: 820),
        operation: .sourceOver,
        fraction: 1.0
    )

    // Subtle crisp inner highlight border
    NSColor(calibratedRed: 0.35, green: 0.85, blue: 1.0, alpha: 0.38).setStroke()
    clipPath.lineWidth = max(1.0, s * 0.014)
    clipPath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// 1. Save full-bleed transparent squircle PNG for in-app LogoBadgeView
let projectDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDir = projectDir.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

let appLogoData = renderTransparentSquircleIcon(canvasSize: 512, insetRatio: 0.0)
try! appLogoData.write(to: resourcesDir.appendingPathComponent("AppLogo.png"))

// 2. Generate macOS .iconset and compile into Resources/AppIcon.icns
let iconsetURL = URL(fileURLWithPath: "/tmp/fnOS.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, s) in sizes {
    let png = renderTransparentSquircleIcon(canvasSize: s, insetRatio: 0.08)
    try! png.write(to: iconsetURL.appendingPathComponent(name))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetURL.path, "-o", resourcesDir.appendingPathComponent("AppIcon.icns").path]
try! proc.run()
proc.waitUntilExit()
print("Successfully generated Resources/AppLogo.png and Resources/AppIcon.icns")
