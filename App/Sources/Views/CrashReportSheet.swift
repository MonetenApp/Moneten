import Domain
import SwiftUI

struct CrashReportSheet: View {
	let reports: CrashReportController

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Moneten quit unexpectedly").font(.title2).bold()
			Text("Moneten quit unexpectedly recently. You can report the crash as an issue on GitHub. The report holds no account data. Read it before you send it.")
			ScrollView([.vertical, .horizontal]) {
				Text(reports.pending?.report ?? "")
					.font(.system(.body, design: .monospaced))
					.textSelection(.enabled)
					.padding(12)
			}
			.defaultScrollAnchor(.topLeading)
			.background(.background, in: RoundedRectangle(cornerRadius: 6))
			.overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
			if let error = reports.error { Text(error).foregroundStyle(.red) }
			HStack {
				Button("Don't Report") { reports.decide(.decline) }
				Spacer()
				Button("Copy Report") { reports.decide(.copy) }
				Button("Report on GitHub...") { reports.decide(.github) }
			}
		}
		.padding(24)
		.frame(width: 720, height: 460)
		.interactiveDismissDisabled()
	}
}
