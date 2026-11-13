import AppKit

// Keep the repository banner in sync with the canonical app artwork.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let logoURL = root.appendingPathComponent("Resources/Brand/SortlaneLogo.png")
let bannerURL = root.appendingPathComponent("docs/assets/banner.svg")
guard let logo = NSImage(contentsOf: logoURL),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Cannot read the canonical logo or allocate the banner image")
}
bitmap.size = NSSize(width: 512, height: 512)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
logo.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode the banner logo") }
let banner = try String(contentsOf: bannerURL, encoding: .utf8)
let expression = try NSRegularExpression(pattern: #"href="data:image/png;base64,[^"]+""#)
let range = NSRange(banner.startIndex..., in: banner)
guard expression.numberOfMatches(in: banner, range: range) == 1 else { fatalError("Expected one embedded logo in banner.svg") }
let replacement = "href=\"data:image/png;base64,\(data.base64EncodedString())\""
let updated = expression.stringByReplacingMatches(in: banner, range: range, withTemplate: replacement)
try updated.write(to: bannerURL, atomically: true, encoding: .utf8)
print("Updated docs/assets/banner.svg from Resources/Brand/SortlaneLogo.png")
