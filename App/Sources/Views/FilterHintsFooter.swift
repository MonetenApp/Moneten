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
		.foregroundStyle(.secondary)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.horizontal, 16)
		.padding(.vertical, 8)
	}
}

/// Puts `FilterHintLines` below the last row of the transaction table, so that the lines scroll with the rows.
/// A SwiftUI `Table` has no footer, a row for the lines would need a `ForEach` of rows, which builds a view graph
/// for every row, and `.contentMargins` does not reach the scroll view of a table on macOS 15. So this view, in
/// the background of the table, finds the `NSTableView` beside it and adds the lines to its clip view, which
/// moves them with the rows. A bottom inset of the scroll view lets the list scroll past the last row to the
/// lines. No row carries a modifier.
struct FilterHintsFooter: NSViewRepresentable {
	let hints: [TransactionFilter.Hint]
	/// The number of rows, so that a row that comes or goes in place moves the lines.
	let rowCount: Int

	func makeNSView(context: Context) -> FilterHintsAnchor { FilterHintsAnchor() }

	func updateNSView(_ anchor: FilterHintsAnchor, context: Context) { anchor.update(hints: hints, rowCount: rowCount) }

	static func dismantleNSView(_ anchor: FilterHintsAnchor, coordinator: ()) { anchor.detach() }
}

/// The hosting view of the lines in the clip view. The debug harness finds it by its class.
final class FilterHintsHost: NSHostingView<FilterHintLines> {}

/// A view without content in the background of the table. It finds the table and places the lines.
final class FilterHintsAnchor: NSView {
	private var hints: [TransactionFilter.Hint] = []
	private var rowCount = 0
	private let host = FilterHintsHost(rootView: FilterHintLines(hints: []))
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
		if hints != self.hints { host.rootView = FilterHintLines(hints: hints) }
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
		clip.addSubview(host)
		let center = NotificationCenter.default
		for view in [found, clip] as [NSView] {
			view.postsFrameChangedNotifications = true
			observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.placeSoon() }
			})
		}
		insetObservation = scroll.observe(\.contentInsets) { [weak self] _, _ in
			DispatchQueue.main.async { self?.placeSoon() }
		}
		place()
	}

	/// The table beside this view: SwiftUI puts the host of a background in front of the host of its content, in
	/// the same parent. The search reads the later siblings of each of a few parents, and the frame of the scroll
	/// view must match this view, so that a table that SwiftUI is about to remove does not count.
	private func findTable() -> NSTableView? {
		guard bounds.width > 0, bounds.height > 0 else { return nil }
		let frame = convert(bounds, to: nil)
		func search(_ view: NSView, depth: Int) -> NSTableView? {
			if let scroll = view as? NSScrollView, let table = scroll.documentView as? NSTableView {
				let scrollFrame = scroll.convert(scroll.bounds, to: nil)
				return abs(scrollFrame.minX - frame.minX) < 2 && abs(scrollFrame.minY - frame.minY) < 2
					&& abs(scrollFrame.width - frame.width) < 2 && abs(scrollFrame.height - frame.height) < 2 ? table : nil
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

	/// Puts the lines below the last row and makes room for them at the end of the list.
	private func place() {
		guard let table, let scroll = table.enclosingScrollView, host.superview != nil else { return }
		let clip = scroll.contentView
		let rows = table.numberOfRows
		let height = hints.isEmpty ? 0 : host.fittingSize.height
		let lastRow = rows > 0 ? table.rect(ofRow: rows - 1).maxY : 0
		host.isHidden = hints.isEmpty
		let frame = NSRect(x: table.frame.minX, y: table.frame.minY + lastRow, width: clip.bounds.width, height: height)
		if host.frame != frame { host.frame = frame }
		// The table fills the clip view when it has few rows, so the lines need room only below a long list.
		setRoom(max(0, lastRow + height - table.frame.height), in: scroll)
	}

	private func setRoom(_ newRoom: CGFloat, in scroll: NSScrollView) {
		var insets = scroll.contentInsets
		let base = insets.bottom == writtenBottom ? insets.bottom - room : insets.bottom
		room = newRoom
		guard insets.bottom != base + newRoom else {
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
		host.removeFromSuperview()
		table = nil
		searches = 0
	}
}
