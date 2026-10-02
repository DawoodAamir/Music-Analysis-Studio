import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
var entries: [[String: String]] = []
func render(_ dimension: Int, _ filename: String, mac: Bool) throws {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: dimension, pixelsHigh: dimension, bitsPerSample: 8,
    samplesPerPixel: mac ? 4 : 3, hasAlpha: mac, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let transform = NSAffineTransform()
  transform.scale(by: CGFloat(dimension) / 1024)
  transform.concat()
  NSColor(calibratedRed: 0.2, green: 0.23, blue: 0.38, alpha: 1).setFill()
  (mac
    ? NSBezierPath(
      roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 200, yRadius: 200)
    : NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024))).fill()
  NSColor(calibratedRed: 0.75, green: 0.8, blue: 0.96, alpha: 1).setFill()
  for (index, height) in [150.0, 280, 440, 580, 360, 220, 120].enumerated() {
    NSBezierPath(
      roundedRect: NSRect(
        x: 245 + Double(index) * 78, y: 512 - height / 2, width: 42, height: height), xRadius: 21,
      yRadius: 21
    ).fill()
  }
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(
    to: output.appendingPathComponent(filename))
}
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = "icon-\(size)-\(scale).png"
    try render(size * scale, name, mac: true)
    entries.append([
      "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name,
    ])
  }
}
try render(1024, "ios-1024.png", mac: false)
entries.append([
  "idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "ios-1024.png",
])
try JSONSerialization.data(
  withJSONObject: ["images": entries, "info": ["version": 1, "author": "xcode"]],
  options: [.prettyPrinted, .sortedKeys]
).write(to: output.appendingPathComponent("Contents.json"))
