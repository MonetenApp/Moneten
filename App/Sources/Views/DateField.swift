import Domain
import SwiftUI

/// The date field of the app (add-localization-and-formatting, tasks 2.7 to 2.12). The date picker of the system
/// edits the day, the month, and the year one at a time and cannot take a day alone, so the field is a text field
/// that reads a date in the order of the region and completes a day or a day and month with `Day(typed:)`.
///
/// The bound day follows the text while the user types, so a click on a button of the sheet uses the completed date
/// even though the field still has the focus. It is nil while the text is not a date, and the sheet then refuses to
/// confirm. When the user leaves the field, it shows the full date, or it marks the text and takes the focus back.
struct DateField: View {
	var title: LocalizedStringKey
	@Binding var day: Day?
	/// A field for a date that lies ahead, such as the scheduled date of a payment, completes forward.
	var expectsFuture = false
	/// Tells the calendar buttons of several fields apart for the debug harness.
	var identifier = "date"

	@State private var text = ""
	/// The text that the field wrote for the bound day. It keeps that day even where `Day(typed:)` cannot read the
	/// format of the region back, such as a year of the Buddhist calendar.
	@State private var shown = ""
	@State private var shownDay: Day?
	@State private var isMarked = false
	@State private var showsCalendar = false
	@FocusState private var hasFocus: Bool

	private func completed(_ text: String) -> Day? {
		Day(typed: text, today: .today(), order: DateOrder(locale: .current), expectsFuture: expectsFuture)
	}

	/// The day of a text. A text that returns to the one the field wrote, such as after Undo, brings its day back.
	private func reading(_ text: String) -> Day? {
		text == shown ? shownDay : completed(text)
	}

	var body: some View {
		LabeledContent(title) {
			HStack(spacing: 4) {
				TextField(title, text: $text)
					.labelsHidden()
					.focused($hasFocus)
					.multilineTextAlignment(.trailing)
					.monospacedDigit()
					.foregroundStyle(isMarked ? Palette.red : Color.primary)
					.help(isMarked ? Text("Not a valid date") : Text(verbatim: ""))
					.padding(.horizontal, 4)
					.overlay {
						if isMarked { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.red, lineWidth: 2) }
					}
					.frame(width: 104)
					.onSubmit(leave)
				Button {
					showsCalendar = true
				} label: {
					Label("Show Calendar", systemImage: "calendar").labelStyle(.iconOnly)
				}
				.buttonStyle(.borderless)
				.help("Show Calendar")
				.accessibilityIdentifier("\(identifier)-calendar")
				.popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
					DateFieldCalendar(title: title, shown: day ?? .today(), pick: pick)
				}
			}
		}
		.onAppear { show(day) }
		.onChange(of: text) {
			day = reading(text)
			if day != nil { isMarked = false }
		}
		.onChange(of: day) {
			// A date from outside the text replaces the text.
			if day != reading(text) { show(day) }
		}
		.onChange(of: hasFocus) { if !hasFocus { leave() } }
	}

	private func show(_ day: Day?) {
		shownDay = day
		shown = day.map(Format.day) ?? ""
		text = shown
	}

	/// Shows the full date, or marks the field and keeps it in editing ("Reject an impossible date").
	private func leave() {
		if text == shown, shownDay != nil {
			isMarked = false
		} else if let day = completed(text) {
			isMarked = false
			show(day)
		} else {
			isMarked = true
			// The calendar takes the focus while it is open, and a date picked there ends the mark.
			guard !showsCalendar else { return }
			DispatchQueue.main.async { hasFocus = true }
		}
	}

	/// A date of the calendar goes into the field. A day of the month on show closes the calendar too, while a move
	/// to another month leaves it open.
	private func pick(_ picked: Day, closes: Bool) {
		// The new text sets the day and ends the mark.
		show(picked)
		if closes { showsCalendar = false }
	}
}

/// The calendar of a date field. It starts at the date of the field, or at today while the field holds no date. It
/// shows the days of the calendar of the user in GMT and gets each day as its noon GMT, so a day that has no local
/// midnight, such as 30 December 2011 in Samoa, still shows and picks as itself.
struct DateFieldCalendar: View {
	var title: LocalizedStringKey
	@State var shown: Day
	var pick: (Day, _ closes: Bool) -> Void

	var body: some View {
		DatePicker(title, selection: Binding(get: { shown.noon }, set: { date in
			let picked = Day(noon: date)
			// The calendar of the system also sets its date when the user moves to another month, and whether
			// its arrows do so is not documented. So every date goes into the field, and only a day of the
			// month on show, which is a click on a day, closes the calendar.
			let closes = picked.year == shown.year && picked.month == shown.month
			shown = picked
			pick(picked, closes)
		}), displayedComponents: .date)
		.datePickerStyle(.graphical)
		.labelsHidden()
		.environment(\.calendar, Day.calendar(like: .current))
		.environment(\.timeZone, Day.calendar(like: .current).timeZone)
		.padding(8)
	}
}
