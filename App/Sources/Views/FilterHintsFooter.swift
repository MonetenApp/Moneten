import AppKit
import Domain
import SwiftUI

/// The lines of the active filters, one for each, as text only.
struct FilterHintLines: View {
	let hints: [TransactionFilter.Hint]

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			ForEach(hints, id: \.self) { hint in
				Text(hint.text).lineLimit(1)
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
/// A SwiftUI `Table` has no footer, and a row for the lines would need a `ForEach` of rows, which builds a view
/// graph for every row. So this view, in the background of the table, finds the `NSTableView` behind it and
/// adds the lines to its clip view, which moves them with the rows. A bottom inset of the scroll view lets the
/// list scroll past the last row to the lines. No row carries a modifier.
struct FilterHintsFooter: NSViewRepresentable {
	let hints: [TransactionFilter.Hint]

	func makeNSView(context: Context) -> FilterHintsAnchor { FilterHintsAnchor() }

	func updateNSView(_ anchor: FilterHintsAnchor, context: Context) { anchor.hints = hints }

	static func dismantleNSView(_ anchor: FilterHintsAnchor, coordinator: ()) { anchor.detach() }
}

/// The hosting view of the lines in the clip view. The debug harness finds it by its class.
final class FilterHintsHost: NSHostingView<FilterHintLines> {
	/// Text only: a click goes to the table below.
	override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A view without content in the background of the table. It finds the table and places the lines.
final class FilterHintsAnchor: NSView {
	var hints: [TransactionFilter.Hint] = [] {
		didSet {
			guard hints != oldValue else { return }
			host.rootView = FilterHintLines(hints: hints)
			place()
		}
	}

	private let host = FilterHintsHost(rootView: FilterHintLines(hints: []))
	private weak var table: NSTableView?
	private var observers: [NSObjectProtocol] = []
	/// The bottom inset that this view added to the scroll view, so that `detach` takes back only its own.
	private var addedInset: CGFloat = 0
	/// SwiftUI can add the anchor to the window before the table, so the search tries again on a few later turns.
	private var searches = 0

	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window == nil { detach() } else { attachSoon() }
	}

	override func layout() {
		super.layout()
		if table == nil { attachSoon() }
	}

	private func attachSoon() {
		DispatchQueue.main.async { [weak self] in self?.attach() }
	}

	private func attach() {
		guard table == nil, window != nil else { return }
		guard let found = findTable(), let clip = found.enclosingScrollView?.contentView else {
			searches += 1
			if searches < 20 { attachSoon() }
			return
		}
		table = found
		clip.addSubview(host)
		let center = NotificationCenter.default
		for view in [found, clip] as [NSView] {
			view.postsFrameChangedNotifications = true
			observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.place() }
			})
		}
		place()
	}

	/// The table whose scroll view lies under the middle of this view. The search reads the views of the window
	/// once for each table, because SwiftUI makes a new table for every view and every filter.
	private func findTable() -> NSTableView? {
		guard let content = window?.contentView, bounds.width > 0, bounds.height > 0 else { return nil }
		let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
		func search(_ view: NSView) -> NSTableView? {
			if let table = view as? NSTableView, let scroll = table.enclosingScrollView, scroll.convert(scroll.bounds, to: nil).contains(center) {
				return table
			}
			for sub in view.subviews { if let found = search(sub) { return found } }
			return nil
		}
		return search(content)
	}

	/// Puts the lines below the last row and makes room for them at the end of the list.
	private func place() {
		guard let table, let scroll = table.enclosingScrollView else { return }
		let clip = scroll.contentView
		let rows = table.numberOfRows
		let height = hints.isEmpty ? 0 : host.fittingSize.height
		let lastRow = rows > 0 ? table.rect(ofRow: rows - 1).maxY : 0
		host.isHidden = hints.isEmpty
		host.frame = NSRect(x: table.frame.minX, y: table.frame.minY + lastRow, width: clip.bounds.width, height: height)
		// The table fills the clip view when it has few rows, so the lines need room only below a long list.
		setInset(max(0, lastRow + height - table.frame.height))
	}

	private func setInset(_ inset: CGFloat) {
		guard let scroll = table?.enclosingScrollView, inset != addedInset else { return }
		scroll.automaticallyAdjustsContentInsets = false
		var insets = scroll.contentInsets
		insets.bottom += inset - addedInset
		scroll.contentInsets = insets
		addedInset = inset
	}

	func detach() {
		for observer in observers { NotificationCenter.default.removeObserver(observer) }
		observers = []
		setInset(0)
		host.removeFromSuperview()
		table = nil
		searches = 0
	}
}
