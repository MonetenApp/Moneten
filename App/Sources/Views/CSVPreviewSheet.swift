import Domain
import Import
import Storage
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
			// "Auto-create categories" changes nothing that the preview reads.
			var old = oldValue
			old.createsCategories = layout.createsCategories
			guard layout != old, !isAdopting else { return }
			let dates: [CSVField] = [.bookingDate, .valueDate]
			if dates.contains(where: { layout.columns[$0] != oldValue.columns[$0] }) { detectsDateOrder = true }
			refresh()
		}
	}
	/// The preview of `layout`, or nil while the app reads the file again.
	private(set) var preview: CSVPreview?
	/// Why the file cannot be read with the encoding of `layout`.
	private(set) var problem: String?
	/// The saved profiles, and the name under which "Import" saves the settings. An empty name saves none.
	private(set) var profiles: [CSVProfile]
	var profileName: String
	/// The saved profile that the settings come from.
	private(set) var profile: String?
	/// The profile that the file matched, which "Import" renames when the user changed the name. A profile
	/// that the user picks is only a starting point, so a new name leaves it.
	@ObservationIgnored private let matched: String?
	@ObservationIgnored private let store: Store
	@ObservationIgnored private var reading: Task<Void, Never>?
	/// Set while the model takes a layout that needs no new reading or keeps its date order.
	@ObservationIgnored private var isAdopting = false
	/// Set from a change of a date column until a reading finishes, so that a quick second change, which
	/// cancels the reading, still detects the date order.
	@ObservationIgnored private var detectsDateOrder = false

	/// `profile` is the starting point, and `matched` the profile with the header row of the file. A near
	/// match starts from its profile with an empty name, so that "Import" never moves it to another bank.
	init(name: String, file: CSVFile, layout: CSVLayout, currency: String, profiles: [CSVProfile], profile: String?, matched: String?, store: Store) {
		self.name = name
		self.file = file
		self.layout = layout
		self.currency = currency
		self.profiles = profiles
		self.profile = profile
		self.matched = matched
		self.store = store
		profileName = matched ?? ""
		refresh()
	}

	var savedProfile: String? {
		let name = profileName.trimmingCharacters(in: .whitespaces)
		return name.isEmpty || !file.hasHeaderRow ? nil : name
	}

	/// Takes the settings of a saved profile, with each field in the column of the title that the profile had for it.
	func apply(_ name: String?) {
		profile = name
		// A picked profile is a starting point; only the matched one keeps its name, so "Import" never moves another bank's profile.
		profileName = name == matched ? name ?? "" : ""
		guard let saved = profiles.first(where: { $0.name == name }) else { return }
		var next = saved.previewLayout(for: file)
		switch CSVProfile.match(for: file, in: [saved], detected: layout) {
		case .same: break
		case let .changed(_, moved): next = moved
		case .none: next.columns = layout.columns
		}
		isAdopting = true
		layout = next
		isAdopting = false
		detectsDateOrder = false
		refresh()
	}

	func deleteProfile() {
		guard let profile else { return }
		do {
			try store.deleteCSVProfile(named: profile)
			profiles.removeAll { $0.name == profile }
			self.profile = nil
			profileName = ""
		} catch { problem = String(localized: "Could not delete the CSV profile. \(error)") }
	}

	func saveProfile() -> Bool {
		guard let savedProfile else { return true }
		let saved = CSVProfile(name: savedProfile, header: file.header, layout: layout, delimiter: file.delimiter)
		do {
			try store.saveCSVProfile(saved, replacing: profile == matched ? matched : nil)
			profiles.save(saved, matched: matched, applied: profile)
			return true
		} catch {
			problem = String(localized: "Could not save the CSV profile. \(error)")
			return false
		}
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
		if !layout.missing.isEmpty { return String(localized: "No column is assigned to \(missingFields).") }
		if preview?.transactions.isEmpty == true { return TransactionFileImporter.Failure.empty.description }
		return String(localized: "The file was skipped.")
	}

	/// "“Booking date” and “Amount”", with the names that the column menus show.
	var missingFields: String {
		layout.missing.map { String(localized: "“\($0.title)”") }.formatted(.list(type: .and))
	}

	/// Whether the dates fit day first and month first, so that the user must check the date format.
	var isDateOrderUncertain: Bool { (preview?.dateOrders.count ?? 0) > 1 }

	func stop() {
		reading?.cancel()
	}

	private func refresh() {
		reading?.cancel()
		let previous = preview
		preview = nil
		problem = nil
		let current = file, layout = layout, currency = currency, detectingDateOrder = detectsDateOrder
		let parsing = Task.detached(priority: .userInitiated) {
			withExtendedLifetime(previous) {}
			let file = try current.with(layout.encoding)
			let preview = try file.preview(layout, currency: currency, detectingDateOrder: detectingDateOrder)
			return (file, preview)
		}
		reading = Task { @MainActor [weak self] in
			await withTaskCancellationHandler {
				do {
					let (file, preview) = try await parsing.value
					guard !Task.isCancelled, let self else { return }
					self.file = file
					self.isAdopting = true
					var read = preview.layout
					read.createsCategories = self.layout.createsCategories
					self.layout = read
					self.isAdopting = false
					self.detectsDateOrder = false
					self.preview = preview
				} catch let failure as TransactionFileImporter.Failure {
					guard !Task.isCancelled, let self else { return }
					self.problem = failure.description
				} catch {}
			} onCancel: {
				parsing.cancel()
			}
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
				Picker("Profile", selection: Binding { model.profile } set: { model.apply($0) }) {
					Text("None").tag(String?.none)
					ForEach(model.profiles, id: \.name) { Text($0.name).tag(String?.some($0.name)) }
				}
				if !model.file.hasHeaderRow {
					Text("A file without a header row cannot be saved as a profile.").foregroundStyle(.secondary)
				} else {
					LabeledContent("Save as profile") {
						HStack {
							TextField("Save as profile", text: $model.profileName, prompt: Text("Name"))
								.labelsHidden()
								.textFieldStyle(.roundedBorder)
								.frame(width: 220)
							Button("Delete Profile", role: .destructive) { model.deleteProfile() }
								.disabled(model.profile == nil)
						}
					}
				}
			}
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
				if model.layout.columns[.category] != nil {
					Toggle("Auto-create categories", isOn: $model.layout.createsCategories)
						.toggleStyle(.checkbox)
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
		if model.layout.missing.count > 1 { return String(localized: "Assign columns to \(model.missingFields).") }
		if !model.layout.missing.isEmpty { return String(localized: "Assign a column to \(model.missingFields).") }
		guard let preview = model.preview else { return model.problem == nil ? String(localized: "Reading the file...") : "" }
		let count = preview.transactions.count
		return count == 0 ? "" : count == 1 ? String(localized: "One transaction") : String(localized: "\(count) transactions")
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
