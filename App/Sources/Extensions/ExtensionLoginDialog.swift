import Domain
import Sync
import SwiftUI

/// Asks for the login data of an extension service, with the fields of its manifest or "Username"
/// and "Password". A secret field hides what the user types and is not offered to the password manager.
/// In a refresh the dialog names the access, as the PIN sheet does: the title has the service, a line has
/// the accounts, and the first field starts with the user ID of the access. "Save Password" is off each time the
/// dialog appears, as "Save PIN" in the PIN sheet, and the broker saves the login data only after the service accepted it.
struct ExtensionLoginDialog: View {
	let broker: SessionBroker
	let prompt: Prompt
	let request: LoginRequest
	@State private var values: [String]
	@State private var save = false

	init(broker: SessionBroker, prompt: Prompt, request: LoginRequest) {
		self.broker = broker
		self.prompt = prompt
		self.request = request
		_values = State(initialValue: request.startValues(userID: prompt.access.loginName))
	}

	var body: some View {
		DialogFrame(title: "Log In to “\(request.service)”") {
			if request.rejected {
				Section {
					Label("The service did not accept the last login data. Check it and enter it again.", systemImage: "exclamationmark.triangle")
						.foregroundStyle(.orange)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			if !prompt.accountNames.isEmpty {
				Section {
					LabeledContent(prompt.accountNames.count == 1 ? "Account" : "Accounts", value: prompt.accountNames.joined(separator: ", "))
				}
			}
			Section {
				ForEach(request.fields.indices, id: \.self) { index in
					let field = request.fields[index]
					if field.isSecret {
						SecureField(field.label, text: $values[index], prompt: Text("Required")).textContentType(nil)
					} else {
						TextField(field.label, text: $values[index], prompt: Text("Required")).textContentType(nil)
					}
				}
				Toggle("Save \(request.secretName)", isOn: $save)
					.toggleStyle(.checkbox)
			} footer: {
				Text("Moneten sends the login data only to the hosts of the extension.").foregroundStyle(.secondary)
			}
		} buttons: {
			Button("Cancel", role: .cancel) { broker.cancel(prompt.id) }.keyboardShortcut(.cancelAction)
			Button("Log In", action: confirm).keyboardShortcut(.defaultAction).disabled(values.contains(where: \.isEmpty))
		}
	}

	private func confirm() {
		guard !values.contains(where: \.isEmpty) else { return }
		broker.answer(.login(values.map(Secret.init), save: save), to: prompt.id)
	}
}
