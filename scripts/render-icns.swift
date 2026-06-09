#!/usr/bin/env swift
// Render design/logo/appicon.svg into build/AppIcon.iconset and compile
// to AppIcon.icns. Uses AppKit's native SVG renderer because ImageMagick's
// librsvg path produces garbage (all-black with alpha) for this artwork.
//
// Run:  swift scripts/render-icns.swift

import Foundation
import AppKit

let svgPath = "design/logo/appicon.svg"
let outDir  = "build/AppIcon.iconset"
let icnsOut = "build/AppIcon.icns"

let sizes: [(side: Int, name: String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let svgURL = URL(fileURLWithPath: svgPath)
let svgData = try Data(contentsOf: svgURL)
guard let source = NSImage(data: svgData) else {
    FileHandle.standardError.write("ERROR: AppKit could not parse SVG at \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}
print("Loaded SVG · source size \(source.size)")

for (side, name) in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    ) else { continue }

    bitmap.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    let dest = URL(fileURLWithPath: "\(outDir)/\(name).png")
    try png.write(to: dest)
    print("  \(name).png  (\(side)×\(side))")
}

print("Compiling \(icnsOut) ...")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", outDir, "-o", icnsOut]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed (exit \(task.terminationStatus))\n".data(using: .utf8)!)
    exit(1)
}
print("OK · \(icnsOut)")
