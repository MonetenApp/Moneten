import AppKit
import Domain
import SwiftUI

/// An IBAN in groups of four as selectable text. Copy, a drag of the selected text, and a service get the selected
/// characters without the spaces of the groups (`IBAN.copied(_:)`), so that a pasted IBAN fits a bank form. A `Text`
/// with text selection copies the spaces, because its copy goes through the shared field editor of the window.
struct IBANText: NSViewRepresentable {
	let iban: IBAN

	func makeNSView(context: Context) -> IBANField {
		let field = IBANField(frame: .zero)
		field.isEditable = false
		field.isSelectable = true
		field.isBezeled = false
		field.drawsBackground = false
		field.lineBreakMode = .byClipping
		field.usesSingleLineMode = true
		field.font = .systemFont(ofSize: NSFont.systemFontSize)
		field.textColor = .secondaryLabelColor
		field.setContentHuggingPriority(.required, for: .horizontal)
		field.setContentCompressionResistancePriority(.required, for: .horizontal)
		return field
	}

	func updateNSView(_ field: IBANField, context: Context) {
		field.stringValue = iban.formatted
	}
}

final class IBANField: NSTextField {
	/// A label without its own `draw(_:)` lets AppKit draw its text on another path, which the snapshots of the debug
	/// harness show darker than the `Text` values next to it and than the field editor after a click. With this method,
	/// AppKit draws the cell, and the IBAN has the secondary color of the other values in the screenshots too.
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
	}

	override class var cellClass: AnyClass? {
		get { IBANFieldCell.self }
		set { _ = newValue }
	}
}

/// A selectable text field selects and copies through a field editor. This cell gives the field its own editor in
/// place of the shared one of the window, so that the copy can leave out the spaces.
final class IBANFieldCell: NSTextFieldCell {
	private lazy var editor: IBANFieldEditor = {
		let editor = IBANFieldEditor()
		editor.isFieldEditor = true
		return editor
	}()

	override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

/// AppKit writes the selection with these two methods for Copy, for a drag of selected text, and for a service. The
/// editor offers plain text only, because rich text would carry the spaces too.
final class IBANFieldEditor: NSTextView {
	override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

	override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
		guard types.contains(.string) else { return false }
		pboard.declareTypes([.string], owner: nil)
		return writeSelection(to: pboard, type: .string)
	}

	override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
		guard type == .string else { return false }
		let text = string as NSString
		return pboard.setString(IBAN.copied(selectedRanges.map { text.substring(with: $0.rangeValue) }.joined()), forType: .string)
	}
}
