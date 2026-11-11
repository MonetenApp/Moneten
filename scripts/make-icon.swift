// Draws the app icon and writes App/Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
// Two Ms for MonetenMoneten on deep blue, the second one higher and brighter, like a rising balance.
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
	NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

/// An M as one line in `r`: up the left leg, down to the middle, up, and down the right leg.
func m(in r: NSRect) -> CGPath {
	let p = CGMutablePath()
	p.addLines(between: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY - r.height * 0.55),
		CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.maxX, y: r.minY)])
	return p
}

/// Fills the stroke of `path` with a vertical gradient, over a soft shadow.
func stroke(_ path: CGPath, width: CGFloat, bottom: NSColor, top: NSColor, in context: CGContext) {
	let outline = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
	context.saveGState()
	context.setShadow(offset: CGSize(width: 0, height: -width * 0.25), blur: width * 0.6, color: color(0x020A24, 0.45).cgColor)
	context.addPath(outline)
	context.setFillColor(bottom.cgColor)
	context.fillPath()
	context.restoreGState()
	context.saveGState()
	context.addPath(outline)
	context.clip()
	let box = outline.boundingBox
	let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom.cgColor, top.cgColor] as CFArray, locations: [0, 1])!
	context.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
	context.restoreGState()
}

func draw(size: CGFloat) -> NSBitmapImageRep {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
		hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	let graphics = NSGraphicsContext(bitmapImageRep: rep)!
	NSGraphicsContext.current = graphics
	let context = graphics.cgContext
	// The body of a macOS icon: 824 of 1024 points with a rounded corner.
	let inset = size * 0.1
	let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
	let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
	NSGradient(colors: [color(0x0A1A45), color(0x113886), color(0x2C78EE)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: shape, angle: 90)
	NSGraphicsContext.saveGraphicsState()
	shape.addClip()
	NSGradient(starting: color(0xFFFFFF, 0.16), ending: color(0xFFFFFF, 0))!
		.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
	NSGraphicsContext.restoreGraphicsState()

	let width = rect.width * 0.082
	let w = rect.width * 0.26, h = rect.height * 0.31
	let gap = rect.width * 0.09
	let rise = rect.height * 0.10
	stroke(m(in: NSRect(x: rect.midX - w - gap / 2, y: rect.midY - h / 2 - rise / 2, width: w, height: h)), width: width,
		bottom: color(0x9CC8FF), top: color(0xFFFFFF), in: context)
	stroke(m(in: NSRect(x: rect.midX + gap / 2, y: rect.midY - h / 2 + rise / 2, width: w, height: h)), width: width,
		bottom: color(0x2EA6FF), top: color(0x8FF0FF), in: context)
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
