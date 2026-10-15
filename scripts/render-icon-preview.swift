// Renders the compiled app icon (Liquid Glass, as Finder shows it) to a PNG for the README.
// Usage: swift scripts/render-icon-preview.swift <dir with Assets.car and AppIcon.icns> <output.png>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: render-icon-preview.swift <compiled-icon-dir> <output.png>")
    exit(64)
}
let fileManager = FileManager.default
// Icon Services renders icons for app bundles, so wrap the compiled assets in a throwaway one.
let app = fileManager.temporaryDirectory.appending(path: "MacMDIconPreview-\(UUID().uuidString).app")
defer { try? fileManager.removeItem(at: app) }
let resources = app.appending(path: "Contents/Resources")
try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
try fileManager.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
try fileManager.copyItem(at: URL(filePath: "/usr/bin/true"), to: app.appending(path: "Contents/MacOS/preview"))
for name in ["Assets.car", "AppIcon.icns"] {
    try fileManager.copyItem(at: URL(filePath: arguments[1]).appending(path: name), to: resources.appending(path: name))
}
let info: [String: Any] = [
    "CFBundleExecutable": "preview", "CFBundleIconName": "AppIcon", "CFBundleIconFile": "AppIcon",
    "CFBundleIdentifier": "io.github.rodanr.macmd.iconpreview.\(UUID().uuidString)", "CFBundlePackageType": "APPL",
]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: app.appending(path: "Contents/Info.plist"))

let size = 512
let icon = NSWorkspace.shared.icon(forFile: app.path)
guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: arguments[2]))
print("Wrote \(arguments[2])")
