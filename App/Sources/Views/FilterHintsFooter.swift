import AppKit
import Domain
import SwiftUI

/// The lines of the active filters, one for each, as text only. A narrow window cuts a line, and its help tag
/// shows the whole text.
struct FilterHintLines: View {
	let hints: [TransactionFilter.Hint]

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			ForEach(hints, id: \.self) { hint in
				Text(hint.text).lineLimit(1).help(hint.text)
			}
		}
		.font(.system(size: 11))
		.foregroundStyle(Palette.secondaryText)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
	}
}

/// Puts `FilterHintLines` below the last row of the transaction table, so that the lines scroll with the rows.
/// A SwiftUI `Table` has no footer, a row for the lines would need a `ForEach` of rows, which builds a view graph
/// for every row, and `.contentMargins` does not reach the scroll view of a table on macOS 15. So this view, in
/// the background of the table, finds the `NSTableView` beside it and puts the lines on its scroll view, where
/// each scroll moves them to the bottom of the last row. A bottom inset of the scroll view lets the list scroll
/// past the last row to the lines. The clip view of macOS 15 ends above that inset and the one of macOS 26 reaches
/// under it, so the lines lie on the scroll view and not in the clip view. No row carries a modifier.
struct FilterHintsFooter: NSViewRepresentable {
	let hints: [TransactionFilter.Hint]
	/// The number of rows, so that a row that comes or goes in place moves the lines.
	let rowCount: Int

	func makeNSView(context: Context) -> FilterHintsAnchor { FilterHintsAnchor() }

	func updateNSView(_ anchor: FilterHintsAnchor, context: Context) { anchor.update(hints: hints, rowCount: rowCount) }

	static func dismantleNSView(_ anchor: FilterHintsAnchor, coordinator: ()) { anchor.detach() }
}

/// The hosting view of the lines. The debug harness finds it by its class.
final class FilterHintsHost: NSHostingView<FilterHintLines> {}

/// The part of the scroll view inside its border, which cuts the lines off where the list ends. A click outside
/// the lines goes to the table.
final class FilterHintsClip: NSView {
	override var isFlipped: Bool { true }

	override func hitTest(_ point: NSPoint) -> NSView? {
		let hit = super.hitTest(point)
		return hit === self ? nil : hit
	}
}

/// A view without content in the background of the table. It finds the table and places the lines.
final class FilterHintsAnchor: NSView {
	private var hints: [TransactionFilter.Hint] = []
	private var rowCount = 0
	private let host = FilterHintsHost(rootView: FilterHintLines(hints: []))
	private let container = FilterHintsClip()
	/// The height of the lines, measured when the hints change.
	private var linesHeight: CGFloat = 0
	private weak var table: NSTableView?
	private var observers: [NSObjectProtocol] = []
	private var insetObservation: NSKeyValueObservation?
	/// The bottom inset that this view wrote last, and the room for the lines in it. SwiftUI writes the insets of
	/// its scroll view again on some updates, for example a change of the selection, and a bottom inset that
	/// differs from the one written here is then the new inset of SwiftUI, to which the room is added again.
	private var writtenBottom: CGFloat?
	private var room: CGFloat = 0
	private var adjustedInsets: Bool?
	private var placeQueued = false
	/// SwiftUI can add the anchor to the window before the table, so the search tries again on a few later turns.
	private var searches = 0

	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	func update(hints: [TransactionFilter.Hint], rowCount: Int) {
		if hints != self.hints {
			host.rootView = FilterHintLines(hints: hints)
			linesHeight = hints.isEmpty ? 0 : host.fittingSize.height
		}
		self.hints = hints
		self.rowCount = rowCount
		placeSoon()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window == nil { detach() } else { placeSoon() }
	}

	override func layout() {
		super.layout()
		placeSoon()
	}

	/// Places the lines on the next turn of the run loop, once for any number of calls in this turn. The table
	/// then has its new rows, and a new inset never goes in the drawing that changes the rows (issues #135, #151).
	private func placeSoon() {
		guard !placeQueued else { return }
		placeQueued = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			placeQueued = false
			if table == nil { attach() } else { place() }
		}
	}

	private func attach() {
		guard window != nil else { return }
		guard let found = findTable(), let scroll = found.enclosingScrollView else {
			searches += 1
			if searches < 20 { placeSoon() }
			return
		}
		table = found
		let clip = scroll.contentView
		container.clipsToBounds = true
		container.addSubview(host)
		scroll.addSubview(container)
		let center = NotificationCenter.default
		for view in [found, clip, scroll] as [NSView] {
			view.postsFrameChangedNotifications = true
			observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: nil) { [weak self] _ in
				MainActor.assumeIsolated {
					self?.position()
					self?.placeSoon()
				}
			})
		}
		// Each scroll moves the lines at once, in the same turn as the rows.
		clip.postsBoundsChangedNotifications = true
		observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: nil) { [weak self] _ in
			MainActor.assumeIsolated { self?.position() }
		})
		insetObservation = scroll.observe(\.contentInsets) { [weak self] _, _ in
			DispatchQueue.main.async { self?.placeSoon() }
		}
		place()
	}

	/// The table beside this view: SwiftUI puts the host of a background in front of the host of its content, in
	/// the same parent. The search reads the later siblings of each of a few parents, and the scroll view must
	/// cover this view with the same top, bottom, and right edge, so that a table that SwiftUI is about to remove
	/// does not count. The scroll view can reach under the sidebar on the left, so its left edge can differ.
	private func findTable() -> NSTableView? {
		guard bounds.width > 0, bounds.height > 0 else { return nil }
		let frame = convert(bounds, to: nil)
		func search(_ view: NSView, depth: Int) -> NSTableView? {
			if let scroll = view as? NSScrollView, let table = scroll.documentView as? NSTableView {
				let scrollFrame = scroll.convert(scroll.bounds, to: nil)
				return scrollFrame.minX <= frame.minX + 2 && abs(scrollFrame.maxX - frame.maxX) < 2
					&& abs(scrollFrame.minY - frame.minY) < 2 && abs(scrollFrame.height - frame.height) < 2 ? table : nil
			}
			guard depth > 0 else { return nil }
			for sub in view.subviews { if let found = search(sub, depth: depth - 1) { return found } }
			return nil
		}
		var child: NSView = self
		for _ in 0..<4 {
			guard let parent = child.superview, let index = parent.subviews.firstIndex(of: child) else { return nil }
			for sibling in parent.subviews[(index + 1)...] { if let found = search(sibling, depth: 4) { return found } }
			child = parent
		}
		return nil
	}

	/// The width of the border of the table, which the clip view leaves inside the scroll view, at most 4 points.
	private func border(of scroll: NSScrollView) -> CGFloat {
		min(4, max(0, scroll.contentView.frame.minX - scroll.bounds.minX))
	}

	/// Makes room for the lines at the end of a list that is longer than the window, then places them. The room
	/// comes from fixed sizes only: the height of the rows, of the lines, of the scroll view, and of its border.
	/// It never reads the room that it wrote, so it cannot grow from one layout to the next.
	private func place() {
		guard let table, let scroll = table.enclosingScrollView, container.superview != nil else { return }
		let rows = table.numberOfRows
		let lastRow = rows > 0 ? table.rect(ofRow: rows - 1).maxY : 0
		let border = border(of: scroll)
		let insets = scroll.contentInsets
		// The inset of SwiftUI without the room of the lines.
		let base = insets.bottom == writtenBottom ? insets.bottom - room : insets.bottom
		let visible = scroll.bounds.height - 2 * border - insets.top - base
		let overflow = lastRow + linesHeight - visible
		setRoom(hints.isEmpty || overflow <= 0 ? 0 : min(linesHeight, overflow) + border, in: scroll)
		position()
	}

	/// Moves the lines to the bottom of the last row, in the coordinates of the scroll view, and hides them while
	/// the list does not show that part. It runs on every scroll and changes no inset.
	private func position() {
		guard let table, let scroll = table.enclosingScrollView, container.superview === scroll else { return }
		let clip = scroll.contentView
		let border = border(of: scroll)
		let area = scroll.bounds.insetBy(dx: border, dy: border)
		if container.frame != area { container.frame = area }
		let rows = table.numberOfRows
		let lastRow = rows > 0 ? table.rect(ofRow: rows - 1).maxY : 0
		// The clip view can reach under the sidebar, and its insets keep the rows out of that part.
		let width = clip.bounds.width - scroll.contentInsets.left - scroll.contentInsets.right
		let lines = NSRect(x: table.frame.minX, y: table.frame.minY + lastRow, width: width, height: linesHeight)
		let frame = clip.convert(lines, to: container)
		if host.frame != frame { host.frame = frame }
		host.isHidden = hints.isEmpty || !frame.intersects(container.bounds)
	}

	private func setRoom(_ newRoom: CGFloat, in scroll: NSScrollView) {
		var insets = scroll.contentInsets
		let base = insets.bottom == writtenBottom ? insets.bottom - room : insets.bottom
		room = newRoom
		guard abs(insets.bottom - (base + newRoom)) >= 0.01 else {
			writtenBottom = insets.bottom
			return
		}
		// The scroll view takes a written inset only without the automatic insets, and `detach` turns them back on.
		// The table lies below the toolbar, so its automatic top inset is zero. Should a layout ever put it under
		// the toolbar, the top inset keeps the part that the toolbar covers, which the automatic insets would add.
		if scroll.automaticallyAdjustsContentInsets, let window = scroll.window {
			adjustedInsets = true
			let covered = scroll.convert(scroll.bounds, to: nil).maxY - window.contentLayoutRect.maxY
			insets.top = max(insets.top, covered)
			scroll.automaticallyAdjustsContentInsets = false
		}
		insets.bottom = base + newRoom
		writtenBottom = insets.bottom
		scroll.contentInsets = insets
	}

	func detach() {
		for observer in observers { NotificationCenter.default.removeObserver(observer) }
		observers = []
		insetObservation = nil
		if let scroll = table?.enclosingScrollView {
			setRoom(0, in: scroll)
			if let adjustedInsets { scroll.automaticallyAdjustsContentInsets = adjustedInsets }
		}
		adjustedInsets = nil
		writtenBottom = nil
		room = 0
		container.removeFromSuperview()
		table = nil
		searches = 0
	}
}
