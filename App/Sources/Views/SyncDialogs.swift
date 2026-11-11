import AppKit
import Domain
import Sync
import SwiftUI

/// The dialog for the request on screen: the PIN sheet or "Two-Factor Authentication".
/// The broker decides when it opens and closes, so the buttons answer the broker and never dismiss.
struct SyncDialog: View {
	let broker: SessionBroker
	let prompt: Prompt

	var body: some View {
		switch prompt.request {
		case let .pin(request): PINSheet(broker: broker, prompt: prompt, request: request)
		case let .secondFactor(request): TwoFactorSheet(broker: broker, prompt: prompt, request: request)
		}
	}
}

/// The layout of `SheetFrame`, with buttons that do not dismiss the sheet.
private struct DialogFrame<Content: View, Buttons: View>: View {
	var title: String
	@ViewBuilder var content: Content
	@ViewBuilder var buttons: Buttons

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(title)
				.font(.title3.weight(.semibold))
				.padding(.horizontal, 20)
				.padding(.top, 20)
			SheetForm { content }
			SheetButtons {
				Spacer(minLength: 16)
				buttons
			}
		}
		.frame(width: 460)
	}
}

/// Asks for the PIN of an access. The field hides the characters and is not offered to the password manager.
struct PINSheet: View {
	let broker: SessionBroker
	let prompt: Prompt
	let request: PINRequest
	@State private var pin = ""

	var body: some View {
		DialogFrame(title: "Enter \(request.secretName)") {
			Section {
				LabeledContent(prompt.accountNames.count == 1 ? "Account" : "Accounts", value: prompt.accountNames.joined(separator: ", "))
				LabeledContent("Bank", value: prompt.access.bankName)
				LabeledContent("User ID", value: prompt.access.loginName)
			}
			Section {
				SecureField(request.secretName, text: $pin, prompt: Text("Required"))
					.textContentType(nil)
			}
		} buttons: {
			Button("Cancel", role: .cancel) { broker.cancel(prompt.id) }.keyboardShortcut(.cancelAction)
			Button("OK", action: confirm).keyboardShortcut(.defaultAction).disabled(pin.isEmpty)
		}
	}

	private func confirm() {
		guard !pin.isEmpty else { return }
		broker.answer(.pin(Secret(pin)), to: prompt.id)
	}
}

/// The one dialog for every second factor: it names the system and the purpose, and shows the
/// challenge of the bank without changing it.
struct TwoFactorSheet: View {
	let broker: SessionBroker
	let prompt: Prompt
	let request: SecondFactorRequest
	@State private var input = ""
	@State private var method: TANMethod.ID?
	@State private var medium = ""
	@State private var confirmCancel = false

	var body: some View {
		DialogFrame(title: "Two-Factor Authentication") {
			Section {
				Text(TwoFactorText.reason(request, bank: prompt.access.bankName))
				LabeledContent("User ID", value: prompt.access.loginName)
				if request.loginOnly {
					Text("This TAN is used only for the login and not for the order.").foregroundStyle(.secondary)
				}
			}
			challenge
		} buttons: {
			Button("Cancel", role: .cancel) {
				if case .approveInApp = request.challenge { confirmCancel = true } else { broker.cancel(prompt.id) }
			}
			.keyboardShortcut(.cancelAction)
			if !isWaiting {
				Button("Continue", action: confirm).keyboardShortcut(.defaultAction).disabled(answer == nil)
			}
		}
		.onAppear {
			if case let .chooseTANMethod(methods, current) = request.challenge {
				method = methods.count == 1 ? methods[0].id : methods.first { $0.id == current }?.id
			}
			if case let .chooseTANMedium(media) = request.challenge { medium = media.first ?? "" }
		}
		.alert("Did you cancel the authorization in the app of the bank?", isPresented: $confirmCancel) {
			Button("Yes") { broker.cancel(prompt.id) }
			Button("No", role: .cancel) {}
		} message: {
			Text("Cancel the authorization in the app of the bank first. Otherwise the bank may still carry it out.")
		}
	}

	/// The challenge waits for an approval outside the app, so there is nothing to type.
	private var isWaiting: Bool {
		switch request.challenge {
		case .approveInApp, .openBrowser: true
		default: false
		}
	}

	@ViewBuilder private var challenge: some View {
		switch request.challenge {
		case let .chooseTANMethod(methods, _):
			Section {
				if methods.count == 1 {
					LabeledContent("TAN method", value: methods[0].name)
				} else {
					Picker("Choose TAN method", selection: $method) {
						if !methods.contains(where: { $0.id == method }) { Text("None").tag(TANMethod.ID?.none) }
						ForEach(methods) { Text($0.name).tag(Optional($0.id)) }
					}
				}
			}
		case let .chooseTANMedium(media):
			Section {
				if media.isEmpty {
					TextField("TAN medium", text: $medium, prompt: Text("Required"))
				} else {
					Picker("TAN medium", selection: $medium) {
						ForEach(media, id: \.self) { Text($0).tag($0) }
					}
				}
			} footer: {
				if media.isEmpty {
					Text("The list of TAN media could not be fetched. Type the name of the medium as you registered it at the bank.").foregroundStyle(.secondary)
				}
			}
		case let .enterTAN(text, image):
			Section {
				ChallengeText(text: text)
				if let image { ChallengeImageView(image: image) }
				tanField
			}
		case let .flickerCode(text, code):
			Section {
				ChallengeText(text: text)
				FlickerView(code: code, running: input.isEmpty)
				tanField
			}
		case let .approveInApp(text, app, image, step):
			Section {
				ChallengeText(text: text)
				if let image { ChallengeImageView(image: image) }
				if let step { Text("Code \(step.number) of \(step.of)").foregroundStyle(.secondary) }
				Waiting(text: app.map { "Waiting for the approval in “\($0)”..." } ?? "Waiting for the approval in the app of the bank...")
			}
		case let .openBrowser(url):
			Section {
				Text("Continue in your browser. The dialog closes when the login is complete.")
				Button("Open in Browser") { NSWorkspace.shared.open(url) }
				Waiting(text: "Waiting for the browser...")
			}
		}
	}

	private var tanField: some View {
		TextField("TAN", text: $input, prompt: Text("Required"))
			.textContentType(nil)
	}

	/// The answer that "Continue" sends, or nil while it is incomplete.
	private var answer: UserAnswer? {
		switch request.challenge {
		case .chooseTANMethod: method.map(UserAnswer.tanMethod)
		case .chooseTANMedium: medium.isEmpty ? nil : .tanMedium(medium)
		case .enterTAN, .flickerCode: input.isEmpty ? nil : .tan(Secret(input))
		case .approveInApp, .openBrowser: nil
		}
	}

	private func confirm() {
		if let answer { broker.answer(answer, to: prompt.id) }
	}
}

enum TwoFactorText {
	/// For example "The FinTS server of “Musterbank” needs a confirmation to allow the download of transactions."
	static func reason(_ request: SecondFactorRequest, bank: String) -> String {
		let system = switch request.system {
		case .fintsServer: "The FinTS server"
		case .website: "The website"
		case .apiServer: "The API server"
		}
		let purpose = switch request.purpose {
		case .login: "to allow the login"
		case .download: "to allow the download of transactions"
		case let .order(description): "to send the order “\(description)”"
		}
		return "\(system) of “\(bank)” needs a confirmation \(purpose)."
	}
}

/// The text of the bank, exactly as it came, so the user can compare it with the TAN device.
private struct ChallengeText: View {
	let text: String

	var body: some View {
		Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
	}
}

private struct ChallengeImageView: View {
	let image: ChallengeImage

	var body: some View {
		if let picture = NSImage(data: image.data) {
			Image(nsImage: picture)
				.resizable()
				.interpolation(.none)
				.scaledToFit()
				.frame(width: 220, height: 220)
				.frame(maxWidth: .infinity)
		} else {
			Text("The bank sent an image that cannot be shown.").foregroundStyle(.secondary)
		}
	}
}

private struct Waiting: View {
	let text: String

	var body: some View {
		HStack(spacing: 8) {
			ProgressView().controlSize(.small)
			Text(text).foregroundStyle(.secondary)
		}
	}
}

/// The flicker code of the optical chipTAN: five bars between two marks for the TAN generator.
/// It moves one frame per tick, so a late tick delays the code but never skips a clock step. It
/// stops while the user types the TAN.
struct FlickerView: View {
	let code: FlickerCode
	var running: Bool
	@State private var frame = 0

	var body: some View {
		let frames = code.frames
		Canvas { gc, size in
			let bar = size.width / 5
			gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
			for (i, on) in frames[frame % frames.count].enumerated() where on {
				gc.fill(Path(CGRect(x: CGFloat(i) * bar + bar * 0.1, y: 14, width: bar * 0.8, height: size.height - 14)), with: .color(.white))
			}
			for x in [bar / 2, size.width - bar / 2] {
				var mark = Path()
				mark.move(to: CGPoint(x: x - 6, y: 2))
				mark.addLine(to: CGPoint(x: x + 6, y: 2))
				mark.addLine(to: CGPoint(x: x, y: 11))
				gc.fill(mark, with: .color(.white))
			}
		}
		.frame(width: 240, height: 110)
		.frame(maxWidth: .infinity)
		.accessibilityLabel("Flicker code")
		.task(id: running) {
			// 20 frames per second, two frames for each half byte.
			while running, !Task.isCancelled {
				try? await Task.sleep(for: .milliseconds(50))
				frame += 1
			}
		}
	}
}
