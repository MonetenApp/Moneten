import CoreImage
import Domain
import Sync
import SyncTesting
import SwiftUI

/// Made-up requests that show each dialog of a refresh, played by a scripted connector. The previews
/// use them, and so does the debug harness for snapshots, because no bank connector exists yet.
enum SyncDemo {
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.musterbank.example/")!), bankName: "Musterbank", loginName: "erika77")
	static let accounts = [
		AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1234567890"),
		AccountRequest(accountID: UUID(), name: "Savings", remoteID: "1234567891"),
	]

	static func secondFactor(_ challenge: Challenge, purpose: SecondFactorRequest.Purpose = .download, system: SecondFactorRequest.System = .fintsServer,
		loginOnly: Bool = false) -> UserRequest {
		.secondFactor(SecondFactorRequest(purpose: purpose, system: system, loginOnly: loginOnly, challenge: challenge))
	}

	/// The requests by name, in the order of the previews.
	static let requests: [(name: String, request: UserRequest)] = [
		("pin", .pin(PINRequest())),
		("method", secondFactor(.chooseTANMethod([TANMethod(id: "922", name: "pushTAN 2.0"), TANMethod(id: "913", name: "chipTAN QR")], current: nil), purpose: .login)),
		("medium", secondFactor(.chooseTANMedium(["Handy privat", "Handy Firma"]), purpose: .login)),
		("nomedia", secondFactor(.chooseTANMedium([]), purpose: .login)),
		("tan", secondFactor(.enterTAN(prompt: "Bitte geben Sie die TAN für den Auftrag vom 09.11.2026 ein", image: nil))),
		("phototan", secondFactor(.enterTAN(prompt: "Bitte scannen Sie die Grafik mit Ihrer photoTAN-App.", image: qrCode("Moneten photoTAN demo")))),
		("flicker", secondFactor(.flickerCode(prompt: "Halten Sie den TAN-Generator vor die Grafik.", code: FlickerCode(hex: "1784011049304330363034353930")!))),
		("approve", secondFactor(.approveInApp(prompt: "Bitte bestätigen Sie den Vorgang in Ihrer pushTAN-App.", app: "pushTAN", image: nil, step: nil), purpose: .login)),
		("qrapprove", secondFactor(.approveInApp(prompt: "Scannen Sie den Code mit der App der Bank.", app: "Musterbank App", image: qrCode("Moneten QR demo"), step: .init(2, of: 2)),
			purpose: .login, system: .website)),
		("browser", secondFactor(.openBrowser(URL(string: "https://www.musterbank.example/login")!), purpose: .login, system: .website)),
		("order", secondFactor(.enterTAN(prompt: "Bitte geben Sie die TAN ein.", image: nil), purpose: .order("Transfer of 25,00 EUR to Max Mustermann"), loginOnly: true)),
	]

	/// Starts a refresh of the made-up access that asks with the named request and then fetches both accounts.
	@MainActor
	static func start(_ name: String, in coordinator: SyncCoordinator) {
		guard let request = requests.first(where: { $0.name == name })?.request else { return }
		let connector = ScriptedConnector([.ask(request), .progress(.fetching(done: 0, of: 2)), .wait(.seconds(1))] + accounts.map { .fetched($0.accountID) })
		coordinator.refresh(RefreshRequest(access: access, accounts: accounts), with: connector, attended: true)
	}

	/// A QR code as PNG data, in place of the image of a bank.
	private static func qrCode(_ text: String) -> ChallengeImage? {
		guard let filter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data(text.utf8)]), let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
			let png = CIContext().pngRepresentation(of: output, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { return nil }
		return ChallengeImage(png)
	}
}

/// Shows the dialog of one made-up request, as the app shows it during a refresh.
private struct SyncDemoPreview: View {
	let name: String
	@State private var coordinator = SyncCoordinator()

	var body: some View {
		Group {
			if let prompt = coordinator.broker.current {
				SyncDialog(broker: coordinator.broker, prompt: prompt)
			} else {
				ProgressView()
			}
		}
		.task { SyncDemo.start(name, in: coordinator) }
	}
}

#Preview("PIN") { SyncDemoPreview(name: "pin") }
#Preview("Choose TAN method") { SyncDemoPreview(name: "method") }
#Preview("Choose TAN medium") { SyncDemoPreview(name: "medium") }
#Preview("No list of TAN media") { SyncDemoPreview(name: "nomedia") }
#Preview("Enter TAN") { SyncDemoPreview(name: "tan") }
#Preview("photoTAN") { SyncDemoPreview(name: "phototan") }
#Preview("Flicker code") { SyncDemoPreview(name: "flicker") }
#Preview("Approve in app") { SyncDemoPreview(name: "approve") }
#Preview("QR code in app") { SyncDemoPreview(name: "qrapprove") }
#Preview("Browser") { SyncDemoPreview(name: "browser") }
#Preview("Login TAN for an order") { SyncDemoPreview(name: "order") }
