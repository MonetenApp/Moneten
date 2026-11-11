// Draws the app icon and writes App/Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
// One M for Moneten on deep blue. Its right leg ends higher than the left one, like a rising balance.
import AppKit

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
	CGColor(colorSpace: srgb, components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha])!
}

/// Fills the current clip with a vertical gradient from `bottom` to `top` over `box`.
func vertical(_ colors: [UInt32], _ locations: [CGFloat], over box: CGRect, in context: CGContext) {
	let gradient = CGGradient(colorsSpace: srgb, colors: colors.map { color($0) } as CFArray, locations: locations)!
	context.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
}

func fill(_ path: CGPath, _ colors: [UInt32], in context: CGContext) {
	context.saveGState()
	context.addPath(path)
	context.clip()
	vertical(colors, [0, 1], over: path.boundingBox, in: context)
	context.restoreGState()
}

/// An M as one line in `r`: up the left leg to 86 % of the height, down to the middle, up to the full
/// height, and down the right leg.
func m(in r: CGRect) -> CGPath {
	let p = CGMutablePath()
	p.addLines(between: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.minY + r.height * 0.86), CGPoint(x: r.midX, y: r.minY + r.height * 0.30),
		CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.maxX, y: r.minY)])
	return p
}

func draw(size: CGFloat) -> NSBitmapImageRep {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
		hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	let graphics = NSGraphicsContext(bitmapImageRep: rep)!
	NSGraphicsContext.current = graphics
	let context = graphics.cgContext

	// The body of a macOS icon: 824 of 1024 points with a rounded corner, lighter at the top.
	let inset = size * 0.1
	let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
	let shape = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
	context.saveGState()
	context.addPath(shape)
	context.clip()
	vertical([0x0A1A45, 0x123C8C, 0x2F7CF0], [0, 0.55, 1], over: rect, in: context)
	let sheen = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF, 0), color(0xFFFFFF, 0.14)] as CFArray, locations: [0, 1])!
	context.drawLinearGradient(sheen, start: CGPoint(x: rect.midX, y: rect.midY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
	context.restoreGState()

	// The M: a light stroke with round ends over a soft shadow, white at the top.
	let w = rect.width * 0.50, h = rect.height * 0.40
	let lineWidth = rect.width * 0.105
	let letter = m(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2 - rect.height * 0.02, width: w, height: h))
		.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
	context.saveGState()
	context.setShadow(offset: CGSize(width: 0, height: -lineWidth * 0.21), blur: lineWidth * 0.6, color: color(0x020A24, 0.45))
	context.addPath(letter)
	context.setFillColor(color(0xA9D2FF))
	context.fillPath()
	context.restoreGState()
	fill(letter, [0xA9D2FF, 0xFFFFFF], in: context)
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
