import Domain
import Foundation
import Testing
@testable import FinTS

/// The answer with which ING refuses the FinTS login until the user logged in to its online banking (issue #235).
/// The helper recognizes the text at `fints.ing.de` and sends the kind "websiteLogin" (Tools/FinTSHelper/Ing.java). FinTSConnectorTests
/// "Maps the errors of the bank to failures" maps that kind, also in a rejection of the PIN, which shows no PIN sheet.
@Suite("ING")
struct IngTests {
	static let renew = BankMessage(code: "9942", text: "Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen.")
	static let ing = URL(string: "https://fints.ing.de/fints/")!

	@Test("The error quotes the text of ING and says in a separate sentence where to log in")
	func message() {
		#expect(SyncFailure.websiteLoginNeeded(Self.renew).message == """
			ING asks for a login on its website first: Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen.
			Log in once at https://www.ing.de/ with the user name and the password, not with the QR code. About 24 hours later, the login of Moneten works again.
			""")
		#expect(SyncFailure.websiteLoginNeeded(Self.renew).bankMessage?.code == "9942")
	}

	@Test("The PIN stays, and one lock does not pause the automatic refresh (LockedLoginTests counts the locks)")
	func keepsPIN() {
		let failure = SyncFailure.websiteLoginNeeded(Self.renew)
		#expect(!failure.rejectsPIN)
		#expect(!failure.waitsForUser)
		#expect(!failure.dialogResolves)
		#expect(!failure.mayAskForNewSetup)
	}

	static let access = Access(source: .fints(bankCode: "50010517", url: ing), bankName: "ING", loginName: "erneuern")

	@Test("The fake helper of a debug build fails the refresh and the setup login of \"erneuern\" with the answer of ING")
	func fakeHelper() async {
		await #expect(throws: SyncFailure.websiteLoginNeeded(Self.renew)) {
			_ = try await FinTSConnectorTests.fakeConnector.refresh(RefreshRequest(access: Self.access, accounts: [FinTSConnectorTests.giro]), Session())
		}
		await #expect(throws: SyncFailure.websiteLoginNeeded(Self.renew)) {
			_ = try await FinTSConnectorTests.fakeConnector.listAccounts(of: Self.access, state: nil, session: Session())
		}
	}
}
