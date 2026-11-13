import ExtensionHost
import SwiftUI

/// The questions of the Extensions window: the warning before a file install, an update that asks for
/// new rights, and a removal that names the accounts of the extension.
struct UpdateConfirmation: View {
	@Environment(AppModel.self) private var model
	@Environment(\.dismiss) private var dismiss
	let question: ExtensionLibrary.Question

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			switch question {
			case let .fileWarning(_, package, name), let .allow(name, package):
				Text("\(name) is not from the catalog").font(.headline)
				Text("The script receives the login data of the service. Nobody from the Moneten project has reviewed it. Install it only when you trust its author.")
				hosts(of: package)
				Text("The extension stays marked \"Unverified\".").foregroundStyle(.secondary)
			case let .review(_, name, version, hosts, fields):
				Text("Update \(name) to version \(version)?").font(.headline)
				Text("This version asks for more than the installed one. The installed version is no longer in the catalog, so its accounts can be refreshed only after this update.")
				if !hosts.isEmpty {
					Text("New hosts it contacts:")
					ForEach(hosts, id: \.self) { Text($0).monospaced() }
				}
				if !fields.isEmpty {
					Text("New login fields: \(fields.formatted(.list(type: .and)))")
				}
			case let .remove(_, name, accounts):
				Text("Remove \(name)?").font(.headline)
				if accounts.isEmpty {
					Text("No account uses \(name).")
				} else {
					Text("These accounts use \(name). They keep their data and can no longer be refreshed:")
					ForEach(accounts, id: \.self) { Text($0).bold() }
				}
			}
			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button(confirmTitle) {
					model.extensions.confirm(question)
					dismiss()
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 440)
	}

	private var confirmTitle: String {
		switch question {
		case .fileWarning: "Install"
		case .allow: "Continue"
		case .review: "Install Update"
		case .remove: "Remove"
		}
	}

	@ViewBuilder
	private func hosts(of package: ExtensionPackage) -> some View {
		if let hosts = package.manifest?.hosts {
			Text("It may contact these hosts without asking:")
			ForEach(hosts, id: \.self) { Text($0.value).monospaced() }
		} else {
			Text("It has no list of hosts, so Moneten asks you before each new host.")
		}
	}
}
