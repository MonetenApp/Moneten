import Domain
import Import
import SwiftUI
import Synchronization

@MainActor @Observable
final class FileImport {
	let names: [String]
	/// The index of the file being read.
	var index = 0
	/// The number of transactions being stored, once all files are read.
	var storing: Int?
	@ObservationIgnored nonisolated private let canceled = Mutex(false)
	nonisolated var isCanceled: Bool { canceled.withLock { $0 } }
	/// The file that names another account, which the sheet asks about instead of showing the progress.
	private(set) var question: AccountQuestion?
	@ObservationIgnored var isPresented = false
	@ObservationIgnored private var dismissal: CheckedContinuation<Void, Never>?
	@ObservationIgnored private var waiting: CheckedContinuation<AccountQuestion.Answer?, Never>?
	/// The CSV file that waits for the user, which the sheet shows instead of the progress.
	private(set) var preview: CSVPreviewModel?
	@ObservationIgnored private var choice: CheckedContinuation<TransactionFileImporter.Parsed?, Never>?
	/// Cancels the task that reads the files, which stops the reading of a CSV file at its next row.
	@ObservationIgnored var onCancel: () -> Void = {}

	init(names: [String]) {
		self.names = names
	}

	/// Asks where the file goes, and waits for the answer, or for "Cancel", which gives nil.
	func ask(_ question: AccountQuestion) async -> AccountQuestion.Answer? {
		guard !isCanceled else { return nil }
		return await withCheckedContinuation { continuation in
			waiting = continuation
			self.question = question
		}
	}

	func beginStoring(_ count: Int, resumingAfterCancel: Bool) {
		if resumingAfterCancel { canceled.withLock { $0 = false } }
		storing = count
	}

	func waitForDismissal() async {
		guard isPresented else { return }
		await withCheckedContinuation { dismissal = $0 }
	}

	func sheetDismissed() {
		isPresented = false
		dismissal?.resume()
		dismissal = nil
	}

	func answer(_ choice: AccountQuestion.Answer?) {
		question = nil
		waiting?.resume(returning: choice)
		waiting = nil
	}

	/// Shows the preview and waits for "Import", which gives the transactions of the file, or for
	/// "Cancel", which gives nil.
	func choose(_ preview: CSVPreviewModel) async -> TransactionFileImporter.Parsed? {
		guard !isCanceled else { return nil }
		return await withCheckedContinuation { continuation in
			choice = continuation
			self.preview = preview
		}
	}

	func confirm() {
		guard let preview, let chosen = preview.chosen else { return }
		guard preview.saveProfile() else { return }
		end(chosen)
	}

#if DEBUG
	func confirm(named account: FileAccount) {
		guard var chosen = preview?.chosen else { return }
		chosen.account = account
		end(chosen)
	}
#endif

	/// Leaves out the file in the preview and goes on with the next file.
	func skip() {
		end(nil)
	}

	func cancel() {
		canceled.withLock { $0 = true }
		answer(nil)
		end(nil)
		onCancel()
	}

	private func end(_ result: TransactionFileImporter.Parsed?) {
		preview?.stop()
		preview = nil
		choice?.resume(returning: result)
		choice = nil
	}
}

extension FileImport: Equatable {
	nonisolated static func == (lhs: FileImport, rhs: FileImport) -> Bool { lhs === rhs }
}

struct FileImportSheet: View {
	let run: FileImport

	var body: some View {
		if let question = run.question {
			AccountQuestionView(run: run, question: question)
		} else if let preview = run.preview {
			CSVPreviewView(run: run, model: preview)
		} else {
			progress
		}
	}

	private var progress: some View {
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
		if let n = run.storing { return n == 1 ? String(localized: "Storing one transaction...") : String(localized: "Storing \(n.formatted()) transactions...") }
		return run.names.count == 1 ? String(localized: "Reading \(run.names[0])...") : String(localized: "Reading file \(run.index + 1) of \(run.names.count): \(run.names[run.index])...")
	}
}

/// A CAMT or MT940 file that names another account than the selected one.
struct AccountQuestion {
	enum Answer {
		/// Into the selected account.
		case selected
		/// Into the account that the file names, or into a new offline account when no account has it.
		case named
	}

	let file: String
	let named: FileAccount
	let selected: Account
	/// The account of the app that the file names, or nil when no account has it.
	let other: Account?
}

struct AccountQuestionView: View {
	let run: FileImport
	let question: AccountQuestion

	var body: some View {
		SheetFrame(title: "Import \(question.file)", confirmTitle: question.other.map { "Import into \"\($0.name)\"" } ?? "Import into the selected account",
			width: 560, onCancel: run.cancel, onConfirm: { run.answer(question.other == nil ? .selected : .named); return false }) {
			Button(question.other == nil ? "Create offline account" : "Import into \"\(question.selected.name)\"") {
				run.answer(question.other == nil ? .named : .selected)
			}
		} content: {
			Section {
				Text(message).fixedSize(horizontal: false, vertical: true)
			}
		}
		.interactiveDismissDisabled()
	}

	private var message: String {
		let named = switch question.named {
		case let .iban(iban): String(localized: "the IBAN \(Format.iban(iban))")
		case let .number(bankCode, number, _): bankCode.map { String(localized: "the account number \(number) at the bank code \($0)") } ?? String(localized: "the account number \(number)")
		}
		if let other = question.other {
			return String(localized: "The file names \(named), which belongs to the account \"\(other.name)\". Do you want to import it into \"\(other.name)\" instead of \"\(question.selected.name)\"?")
		}
		return String(localized: "The file names \(named), which no account has. Import it into the selected account \"\(question.selected.name)\", or into a new offline account?")
	}
}
