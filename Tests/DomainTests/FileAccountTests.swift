import Domain
import Foundation
import Testing

@Suite("Account of an imported file")
struct FileAccountTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02 1203 0000 0000 2020 51")
	let savings = Account(position: 1, name: "Savings", kind: .savings, source: .offline, accountNumber: "0012345678", bankCode: "12030000")

	@Test("A file that names the IBAN of another account goes to that account after a question")
	func wrongAccountSelected() {
		let file = FileAccount.iban("DE02120300000000202051")
		#expect(file.destination(selected: savings, accounts: [giro, savings], currency: "EUR") == .other(giro))
		#expect(file.destination(selected: giro, accounts: [giro, savings], currency: "EUR") == .selected)
	}

	@Test("A file that names an IBAN that no account has asks for the selected account or a new offline account")
	func unknownIBAN() {
		#expect(FileAccount.iban("DE02120300000000202051").destination(selected: savings, accounts: [savings], currency: "EUR") == .unknown)
	}

	@Test("An account number with its bank code matches the account number of an account or the number inside a German IBAN")
	func accountNumber() {
		let number = FileAccount.number(bankCode: "12030000", account: "12345678")
		#expect(number.destination(selected: giro, accounts: [giro, savings], currency: "EUR") == .other(savings))
		let inIBAN = FileAccount.number(bankCode: "12030000", account: "202051")
		#expect(inIBAN.destination(selected: savings, accounts: [giro, savings], currency: "EUR") == .other(giro))
		let otherBank = FileAccount.number(bankCode: "10010010", account: "202051")
		#expect(otherBank.destination(selected: savings, accounts: [giro, savings], currency: "EUR") == .unknown)
	}

	@Test("A closed account still takes the file that names it")
	func closedAccount() {
		var closed = giro
		closed.isClosed = true
		#expect(FileAccount.iban("DE02120300000000202051").destination(selected: savings, accounts: [closed, savings], currency: "EUR") == .other(closed))
	}

	@Test("A German IBAN matches an account that has only the bank code and the account number inside it")
	func ibanToNumber() {
		let old = Account(position: 2, name: "Old Giro", kind: .giro, source: .offline, accountNumber: "202051", bankCode: "12030000")
		#expect(FileAccount.iban("DE02120300000000202051").destination(selected: savings, accounts: [savings, old], currency: "EUR") == .other(old))
	}

	@Test("A new offline account for a file takes the IBAN or the bank code and the account number of the file")
	func offlineAccount() {
		let group = UUID()
		let byIBAN = FileAccount.iban("DE02120300000000202051").offlineAccount(groupID: group, position: 3, currency: "EUR")
		#expect(byIBAN.name == "DE02 1203 0000 0000 2020 51")
		#expect(byIBAN.iban == "DE02120300000000202051")
		#expect(byIBAN.groupID == group && byIBAN.position == 3 && byIBAN.currency == "EUR")
		#expect(byIBAN.source == .offline && byIBAN.kind == .giro)
		let byNumber = FileAccount.number(bankCode: "12030000", account: "0099887766").offlineAccount(groupID: nil, position: 0, currency: "USD")
		#expect(byNumber.name == "Account 0099887766")
		#expect(byNumber.bankCode == "12030000" && byNumber.accountNumber == "0099887766" && byNumber.iban == nil)
		#expect(byNumber.currency == "USD")
	}

	@Test("The bank code of a file must fit the bank code inside the IBAN of an account that has no bank code of its own")
	func bankCodeFromIBAN() {
		let mixed = Account(position: 2, name: "Mixed", kind: .giro, source: .offline, iban: "DE02120300000000202051", accountNumber: "202051")
		let otherBank = FileAccount.number(bankCode: "10010010", account: "202051")
		#expect(otherBank.destination(selected: savings, accounts: [savings, mixed], currency: "EUR") == .unknown)
		#expect(FileAccount.number(bankCode: "12030000", account: "202051").destination(selected: savings, accounts: [savings, mixed], currency: "EUR") == .other(mixed))
	}

	@Test("An account without a bank code does not take a file that names a bank, so an exact match elsewhere wins")
	func weakMatch() {
		let bare = Account(position: 3, name: "Extension", kind: .giro, source: .offline, accountNumber: "202051")
		#expect(FileAccount.iban("DE02120300000000202051").destination(selected: bare, accounts: [bare, giro], currency: "EUR") == .other(giro))
		#expect(FileAccount.number(bankCode: nil, account: "202051").destination(selected: bare, accounts: [bare, giro], currency: "EUR") == .selected)
	}

	@Test("Of two accounts with the number of a file, the one in the currency of the file that is not a portfolio takes it")
	func sharedNumber() {
		let euro = Account(position: 4, name: "Broker EUR", kind: .portfolio, source: .offline, currency: "EUR", accountNumber: "1234567")
		let dollar = Account(position: 5, name: "Broker USD", kind: .giro, source: .offline, currency: "USD", accountNumber: "1234567")
		let file = FileAccount.number(bankCode: nil, account: "1234567")
		#expect(file.destination(selected: giro, accounts: [giro, euro, dollar], currency: "USD") == .other(dollar))
		#expect(file.destination(selected: giro, accounts: [giro, euro], currency: "USD") == .other(euro))
	}

	@Test("An IBAN that an account holds as its account number matches")
	func ibanAsNumber() {
		let listed = Account(position: 6, name: "Listed", kind: .giro, source: .offline, accountNumber: "DE02 1203 0000 0000 2020 51")
		#expect(FileAccount.iban("DE02120300000000202051").destination(selected: listed, accounts: [listed], currency: "EUR") == .selected)
	}

	@Test("A selected portfolio gives way to the cash account of the same number in the currency of the file")
	func selectedPortfolio() {
		let portfolio = Account(position: 7, name: "Depot", kind: .portfolio, source: .offline, accountNumber: "1234567")
		let cash = Account(position: 8, name: "Cash", kind: .giro, source: .offline, accountNumber: "1234567")
		let file = FileAccount.number(bankCode: nil, account: "1234567")
		#expect(file.destination(selected: portfolio, accounts: [portfolio, cash], currency: "EUR") == .other(cash))
		#expect(file.destination(selected: cash, accounts: [portfolio, cash], currency: "EUR") == .selected)
	}

	@Test("A German IBAN matches the bank code and account number of an account whose IBAN is empty")
	func emptyIBAN() {
		let listed = Account(position: 6, name: "Listed", kind: .giro, source: .offline, iban: "", accountNumber: "202051", bankCode: "12030000")
		#expect(FileAccount.iban("DE02120300000000202051").destination(selected: listed, accounts: [listed], currency: "EUR") == .selected)
	}

	@Test("A bank code and account number match an account that holds its German IBAN as the account number")
	func numberToIBANAsNumber() {
		let listed = Account(position: 6, name: "Listed", kind: .giro, source: .offline, accountNumber: "DE02120300000000202051")
		#expect(FileAccount.number(bankCode: "12030000", account: "0000202051").destination(selected: listed, accounts: [listed], currency: "EUR") == .selected)
	}
}
