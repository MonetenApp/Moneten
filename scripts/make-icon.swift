// Draws the app icon and writes App/Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
		hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	let inset = size * 0.1
	let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
	let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
	NSGradient(starting: NSColor(red: 0.13, green: 0.55, blue: 0.42, alpha: 1), ending: NSColor(red: 0.05, green: 0.33, blue: 0.27, alpha: 1))!.draw(in: shape, angle: -90)
	// Two stacked coins.
	for (i, offset) in [CGFloat(-0.07), 0.07].enumerated() {
		let d = rect.width * 0.46
		let c = NSRect(x: rect.midX - d / 2 + offset * rect.width, y: rect.midY - d / 2 - offset * rect.width * 0.6, width: d, height: d)
		let coin = NSBezierPath(ovalIn: c)
		(i == 0 ? NSColor(red: 0.93, green: 0.74, blue: 0.25, alpha: 1) : NSColor(red: 0.99, green: 0.84, blue: 0.35, alpha: 1)).setFill()
		coin.fill()
		NSColor(white: 0, alpha: 0.18).setStroke()
		coin.lineWidth = size * 0.008
		coin.stroke()
		if i == 1 {
			let font = NSFont.systemFont(ofSize: d * 0.62, weight: .bold)
			let text = NSAttributedString(string: "€", attributes: [.font: font, .foregroundColor: NSColor(red: 0.55, green: 0.38, blue: 0.05, alpha: 1)])
			let s = text.size()
			text.draw(at: NSPoint(x: c.midX - s.width / 2, y: c.midY - s.height / 2))
		}
	}
	NSGraphicsContext.restoreGraphicsState()
	return rep
}

let base = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
	for scale in [1, 2] {
		let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
		try draw(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
	}
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", base.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print("wrote AppIcon.icns")
