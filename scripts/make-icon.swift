// Draws the app icon and writes App/Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
// A silver coin with one embossed M for Moneten on deep blue.
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

/// An M as one line in `r`: up the left leg, down to the middle, up, and down the right leg.
func m(in r: CGRect) -> CGPath {
	let p = CGMutablePath()
	p.addLines(between: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.minY + r.height * 0.40),
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
	vertical([0x0A1A45, 0x133F92, 0x3482F2], [0, 0.55, 1], over: rect, in: context)
	let sheen = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF, 0), color(0xFFFFFF, 0.14)] as CFArray, locations: [0, 1])!
	context.drawLinearGradient(sheen, start: CGPoint(x: rect.midX, y: rect.midY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
	context.restoreGState()

	// The coin: a rim that is darker at the bottom, a face that is lighter at the top, and a fine line between.
	let d = rect.width * 0.70
	let coin = CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
	context.saveGState()
	context.setShadow(offset: CGSize(width: 0, height: -d * 0.035), blur: d * 0.09, color: color(0x020A24, 0.55))
	context.addEllipse(in: coin)
	context.setFillColor(color(0xC9D6E4))
	context.fillPath()
	context.restoreGState()
	fill(CGPath(ellipseIn: coin, transform: nil), [0x9DB3CC, 0xF8FBFE], in: context)
	let face = coin.insetBy(dx: d * 0.055, dy: d * 0.055)
	fill(CGPath(ellipseIn: face, transform: nil), [0xFAFCFE, 0xC3D2E2], in: context)
	context.addEllipse(in: face)
	context.setStrokeColor(color(0x8FA6C0, 0.55))
	context.setLineWidth(d * 0.008)
	context.strokePath()

	// The M, pressed into the face: a light edge below it and a blue gradient.
	let w = d * 0.50, h = d * 0.42
	let lineWidth = d * 0.12
	let letter = m(in: CGRect(x: coin.midX - w / 2, y: coin.midY - h / 2 - d * 0.005, width: w, height: h))
		.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
	context.saveGState()
	context.setShadow(offset: CGSize(width: 0, height: -lineWidth * 0.10), blur: lineWidth * 0.12, color: color(0xFFFFFF, 0.95))
	context.addPath(letter)
	context.setFillColor(color(0x1A4FA8))
	context.fillPath()
	context.restoreGState()
	fill(letter, [0x0F3480, 0x2B78EE], in: context)
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
