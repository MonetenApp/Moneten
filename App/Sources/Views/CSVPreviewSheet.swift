import Domain
import Import
import SwiftUI

/// A CSV file that waits for the user to check how the app reads it. Each change of the layout reads
/// the whole file again away from the main actor, because a file of 100 MB takes seconds to split and
/// to read.
@MainActor @Observable
final class CSVPreviewModel {
	let name: String
	let currency: String
	private(set) var file: CSVFile
	var layout: CSVLayout {
		didSet {
			guard layout != oldValue, !isAdopting else { return }
			let dates: [CSVField] = [.bookingDate, .valueDate]
			if dates.contains(where: { layout.columns[$0] != oldValue.columns[$0] }) { detectsDateOrder = true }
			refresh()
		}
	}
	/// The preview of `layout`, or nil while the app reads the file again.
	private(set) var preview: CSVPreview?
	/// Why the file cannot be read with the encoding of `layout`.
	private(set) var problem: String?
	@ObservationIgnored private var reading: Task<Void, Never>?
	/// Set while the model takes the date order that the preview detected, which needs no new reading.
	@ObservationIgnored private var isAdopting = false
	/// Set from a change of a date column until a reading finishes, so that a quick second change, which
	/// cancels the reading, still detects the date order.
	@ObservationIgnored private var detectsDateOrder = false

	init(name: String, file: CSVFile, layout: CSVLayout, currency: String) {
		self.name = name
		self.file = file
		self.layout = layout
		self.currency = currency
		refresh()
	}

	/// The transactions to import, once every row of the file reads in `layout`.
	var chosen: TransactionFileImporter.Parsed? {
		guard let preview, problem == nil, preview.problem == nil, layout.missing.isEmpty, !preview.transactions.isEmpty else { return nil }
		return preview.parsed
	}

	/// Why "Import" is disabled, which the result names for a file that the user skipped.
	var reason: String {
		if let problem { return problem }
		if let failure = preview?.problem { return failure.description }
		if !layout.missing.isEmpty { return "No column is assigned to \(missingFields)." }
		if preview?.transactions.isEmpty == true { return TransactionFileImporter.Failure.empty.description }
		return "The file was skipped."
	}

	/// "the booking date and the amount"
	var missingFields: String {
		layout.missing.map { "the \($0.title.lowercased())" }.joined(separator: " and ")
	}

	/// Whether the dates fit day first and month first, so that the user must check the date format.
	var isDateOrderUncertain: Bool { (preview?.dateOrders.count ?? 0) > 1 }

	func stop() {
		reading?.cancel()
	}

	private func refresh() {
		reading?.cancel()
		preview = nil
		problem = nil
		let current = file, layout = layout, currency = currency, detectingDateOrder = detectsDateOrder
		reading = Task.detached(priority: .userInitiated) { [weak self] in
			do {
				let file = layout.encoding == current.encoding ? current : try CSVFile(data: current.data, encoding: layout.encoding)
				let preview = try file.preview(layout, currency: currency, detectingDateOrder: detectingDateOrder)
				await MainActor.run {
					guard !Task.isCancelled, let self else { return }
					self.file = file
					self.isAdopting = true
					self.layout = preview.layout
					self.isAdopting = false
					self.detectsDateOrder = false
					self.preview = preview
				}
			} catch let failure as TransactionFileImporter.Failure {
				await MainActor.run {
					guard !Task.isCancelled, let self else { return }
					self.problem = failure.description
				}
			} catch {}
		}
	}
}

struct CSVPreviewView: View {
	let run: FileImport
	@Bindable var model: CSVPreviewModel

	var body: some View {
		SheetFrame(title: "Import \(model.name)", confirmTitle: "Import", canConfirm: model.chosen != nil, width: 760,
			onCancel: run.cancel, onConfirm: { run.confirm(); return false }) {
			if run.names.count > 1 {
				Button("Skip File") { run.skip() }
			}
			Text(status).foregroundStyle(.secondary)
		} content: {
			Section {
				Picker("Encoding", selection: $model.layout.encoding) {
					ForEach(CSVEncoding.allCases, id: \.self) { Text($0.title) }
				}
				Picker("Date format", selection: $model.layout.dateOrder) {
					ForEach(DateOrder.allCases, id: \.self) { Text($0.title) }
				}
				if model.isDateOrderUncertain {
					Label("Every date fits both orders. Check that the dates below are right.", systemImage: "exclamationmark.triangle")
						.foregroundStyle(.orange)
				}
				Picker("Decimal separator", selection: $model.layout.decimalMark) {
					Text("Detect").tag(DecimalMark?.none)
					Text("Comma").tag(DecimalMark?.some(.comma))
					Text("Point").tag(DecimalMark?.some(.point))
				}
			}
			Section("Columns") {
				// Two columns side by side, so that a bank file with 17 columns fits without scrolling, and a
				// scroll view from 20 columns on, so that "Import" stays on a laptop screen.
				let titles = Array(model.file.header.enumerated())
				ScrollView {
					Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
						ForEach(Array(stride(from: 0, to: titles.count, by: 2)), id: \.self) { start in
							GridRow {
								ForEach(titles[start..<min(start + 2, titles.count)], id: \.offset) { column, title in
									Text(title.isEmpty ? "Column \(column + 1)" : title)
										.lineLimit(1)
										.truncationMode(.middle)
										.frame(maxWidth: .infinity, alignment: .leading)
									Picker(title, selection: field(of: column)) {
										Text("Not imported").tag(CSVField?.none)
										ForEach(CSVField.allCases, id: \.self) { Text($0.title).tag(CSVField?.some($0)) }
									}
									.labelsHidden()
									.fixedSize()
									.frame(width: 190, alignment: .trailing)
								}
							}
						}
					}
				}
				// The form of the sheet does not scroll, and its setting reaches this scroll view.
				.scrollDisabled(false)
				.frame(height: min(CGFloat((titles.count + 1) / 2) * 32, 320))
			}
			Section("Preview") {
				rows
			}
		}
		.interactiveDismissDisabled()
	}

	private var status: String {
		if model.layout.missing.count > 1 { return "Assign columns to \(model.missingFields)." }
		if !model.layout.missing.isEmpty { return "Assign a column to \(model.missingFields)." }
		guard let preview = model.preview else { return model.problem == nil ? "Reading the file..." : "" }
		let count = preview.transactions.count
		return count == 0 ? "" : count == 1 ? "One transaction" : "\(count) transactions"
	}

	@ViewBuilder private var rows: some View {
		if let problem = model.problem ?? model.preview?.problem?.description {
			Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.red)
		} else if let preview = model.preview, !preview.transactions.isEmpty {
			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
				GridRow {
					Text("Date")
					Text("Name")
					Text("Purpose")
					Text("Amount").gridColumnAlignment(.trailing)
				}
				.foregroundStyle(.secondary)
				ForEach(preview.transactions.prefix(10)) { t in
					GridRow {
						Text(Format.day(t.bookingDate)).monospacedDigit()
						Text(t.name).lineLimit(1)
						Text(t.purpose).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
						AmountText(money: Money(minorUnits: t.amountMinor, currency: t.currency))
					}
				}
			}
		} else if model.preview != nil {
			Text(model.reason).foregroundStyle(.secondary)
		} else {
			ProgressView().controlSize(.small)
		}
	}

	private func field(of column: Int) -> Binding<CSVField?> {
		Binding {
			model.layout.columns.first { $0.value == column }?.key
		} set: {
			model.layout.assign(column, to: $0)
		}
	}
}
