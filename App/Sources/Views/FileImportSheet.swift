import SwiftUI

/// A running import of files, which the import sheet shows. The files are read one after the other, and
/// "Cancel" stops at the file being read: what that file holds is never stored.
@MainActor @Observable
final class FileImport {
	let names: [String]
	/// The index of the file being read.
	var index = 0
	/// The number of transactions being stored, once all files are read.
	var storing: Int?
	private(set) var isCanceled = false
	/// Cancels the task that reads the files, which stops the reading of a CSV file at its next row.
	@ObservationIgnored var onCancel: () -> Void = {}

	init(names: [String]) {
		self.names = names
	}

	func cancel() {
		isCanceled = true
		onCancel()
	}
}

extension FileImport: Equatable {
	nonisolated static func == (lhs: FileImport, rhs: FileImport) -> Bool { lhs === rhs }
}

struct FileImportSheet: View {
	let run: FileImport

	var body: some View {
		SheetFrame(title: "Import Transactions", confirmTitle: nil, onCancel: run.cancel, onConfirm: { false }) {
			Section {
				VStack(alignment: .leading, spacing: 8) {
					Text(status)
						.lineLimit(1)
						.truncationMode(.middle)
					if run.names.count == 1 || run.storing != nil {
						ProgressView().progressViewStyle(.linear)
					} else {
						ProgressView(value: Double(run.index), total: Double(run.names.count))
					}
				}
			}
		}
		.interactiveDismissDisabled()
	}

	private var status: String {
		if let n = run.storing { return n == 1 ? "Storing one transaction..." : "Storing \(n.formatted()) transactions..." }
		return run.names.count == 1 ? "Reading \(run.names[0])..." : "Reading file \(run.index + 1) of \(run.names.count): \(run.names[run.index])..."
	}
}
