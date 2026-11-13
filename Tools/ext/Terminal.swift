import Domain
import ExtensionHost
import Foundation
import Synchronization

/// Questions and messages on the terminal. Prompts and messages go to standard error, so that
/// standard output holds only the result.
enum Terminal {
	static func error(_ line: String) {
		FileHandle.standardError.write(Data((line + "\n").utf8))
	}

	/// One line of input, or nil at the end of the input.
	static func ask(_ prompt: String) -> String? {
		FileHandle.standardError.write(Data(prompt.utf8))
		return readLine()
	}

	/// Reads a secret without showing it, of any length, such as a pasted captcha token or a login
	/// address with an `id_token`. The terminal reads it byte for byte, because a line of a terminal
	/// holds at most 1024 bytes. Without a terminal, as in a test with a pipe, it reads one line.
	static func askSecret(_ prompt: String) -> String? {
		guard isatty(STDIN_FILENO) == 1, tcgetattr(STDIN_FILENO, &savedTerminal) == 0 else { return ask(prompt) }
		var raw = savedTerminal
		raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
		withUnsafeMutableBytes(of: &raw.c_cc) { characters in
			characters[Int(VMIN)] = 1
			characters[Int(VTIME)] = 0
		}
		for signal in [SIGINT, SIGTERM, SIGHUP] { Darwin.signal(signal, restoreAndExit) }
		tcsetattr(STDIN_FILENO, TCSANOW, &raw)
		defer {
			tcsetattr(STDIN_FILENO, TCSANOW, &savedTerminal)
			for signal in [SIGINT, SIGTERM, SIGHUP] { Darwin.signal(signal, SIG_DFL) }
			FileHandle.standardError.write(Data("\n".utf8))
		}
		FileHandle.standardError.write(Data(prompt.utf8))
		var bytes: [UInt8] = []
		var byte: UInt8 = 0
		while read(STDIN_FILENO, &byte, 1) == 1 {
			switch byte {
			case 0x0A, 0x0D:
				return String(decoding: bytes, as: UTF8.self)
			case 0x7F, 0x08:
				// One character back: its UTF-8 continuation bytes and its first byte.
				while let last = bytes.popLast(), last & 0xC0 == 0x80 {}
			case 0x04 where bytes.isEmpty:
				return nil
			default:
				bytes.append(byte)
			}
		}
		return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
	}
}

/// The settings of the terminal before `askSecret`, which a signal restores before the process ends.
nonisolated(unsafe) private var savedTerminal = termios()

private func restoreAndExit(_ signal: Int32) {
	tcsetattr(STDIN_FILENO, TCSANOW, &savedTerminal)
	Darwin.signal(signal, SIG_DFL)
	raise(signal)
}

/// The answers of a run in the order the script asked for them, and which login fields hide their input.
final class AnswerLog: Sendable {
	private let state = Mutex<(answers: [Fixture.Answer], secretFields: [Bool])>(([], []))

	func append(_ answer: Fixture.Answer) {
		state.withLock { $0.answers.append(answer) }
	}

	func setSecretFields(_ fields: [Bool]) {
		state.withLock { $0.secretFields = fields }
	}

	var answers: [Fixture.Answer] { state.withLock { $0.answers } }
	var secretFields: [Bool] { state.withLock { $0.secretFields } }
}

/// Asks the author in the terminal for everything the app asks in its dialogs. `ext record` passes
/// an `AnswerLog`, which keeps each answer for the fixture.
struct TerminalSession: SyncSession {
	let environment: [String: String]
	let answers: AnswerLog?
	let imageFolder: URL

	func report(_ progress: SyncProgress) async {}

	/// `ext` keeps no PIN, so it has nothing to forget. The run fails with the rejection that the
	/// connector throws after this.
	func rejected(_ failure: SyncFailure) async {}

	func ask(_ request: UserRequest) async throws -> UserAnswer {
		switch request {
		case let .login(login):
			answers?.setSecretFields(login.fields.map(\.isSecret))
			var values: [Secret] = []
			for (index, field) in login.fields.enumerated() {
				let preset = index == 0 ? environment["EXT_USERNAME"] : index == 1 ? environment["EXT_PASSWORD"] : nil
				guard let value = preset ?? (field.isSecret ? Terminal.askSecret("\(field.label): ") : Terminal.ask("\(field.label): ")) else {
					throw Ext.Failure.run("The input ended before the login data of \(login.service).")
				}
				values.append(Secret(value))
			}
			answers?.append(.login(values.map(\.value)))
			return .login(values)
		case let .allowHost(question):
			let line = Terminal.ask("\(question.extensionName) wants to contact \(question.host). Allow it? [y/N] ")
			let decision: HostDecision = line?.lowercased().hasPrefix("y") == true ? .allowed : .denied
			answers?.append(.host(decision))
			return .host(decision)
		case .pin:
			throw Ext.Failure.run("An extension does not ask for a PIN.")
		case let .secondFactor(factor):
			return try await answer(factor)
		}
	}

	private func answer(_ request: SecondFactorRequest) async throws -> UserAnswer {
		switch request.challenge {
		case let .chooseTANMethod(methods, _):
			Terminal.error("Choose a TAN method:")
			for (index, method) in methods.enumerated() {
				Terminal.error("\(index + 1) \(method.name)" + (method.unavailable.map { " (\($0))" } ?? ""))
			}
			let method = methods[try number(of: methods.count)]
			answers?.append(.tanMethod(method.id))
			return .tanMethod(method.id)
		case let .chooseTANMedium(media):
			for (index, medium) in media.enumerated() { Terminal.error("\(index + 1) \(medium)") }
			let medium = media.isEmpty ? try line("TAN medium: ") : media[try number(of: media.count)]
			answers?.append(.tanMedium(medium))
			return .tanMedium(medium)
		case let .enterTAN(prompt, image):
			Terminal.error(prompt)
			if let image { try show(image) }
			return try tan(request.field.label)
		case let .flickerCode(prompt, code):
			Terminal.error(prompt)
			Terminal.error("Flicker code: \(code.hex)")
			return try tan(request.field.label)
		case let .approveInApp(prompt, _, image, _):
			Terminal.error(prompt)
			if let image { try show(image) }
			Terminal.error("Waiting for approval")
			while true { try await Task.sleep(for: .seconds(3600)) }
		case let .openBrowser(approval):
			Terminal.error("Open this address in a browser and log in:")
			Terminal.error(approval.url.absoluteString)
			while true {
				let pasted = try secretLine("Paste the address that the browser shows at the end of the login: ")
				switch URL(string: pasted.trimmingCharacters(in: .whitespaces)).map({ approval.step(for: $0) }) {
				case let .finish(code)?:
					answers?.append(.tan(code))
					return .tan(Secret(code))
				case let .refuse(message)?: Terminal.error(message)
				// As the login window of the app does: a final address without a code or with another state ends the login.
				case let .fail(message)?: throw SyncFailure.bank(BankMessage(text: message))
				case .load?, nil: Terminal.error("This is not the final address of the login.")
				}
			}
		case let .captcha(captcha):
			Terminal.error("The service asks for a \(captcha.provider.rawValue) captcha with the site key \(captcha.siteKey) on \(captcha.page?.absoluteString ?? "its page").")
			let token = try secretLine("Captcha answer: ")
			answers?.append(.tan(token))
			return .tan(Secret(token))
		}
	}

	private func tan(_ label: String) throws -> UserAnswer {
		let value = try secretLine("\(label): ")
		answers?.append(.tan(value))
		return .tan(Secret(value))
	}

	private func line(_ prompt: String) throws -> String {
		guard let value = Terminal.ask(prompt) else { throw Ext.Failure.run("The input ended before the answer to the challenge.") }
		return value
	}

	/// An answer that the terminal does not show, as a TAN, a captcha answer, or the code in a pasted address.
	private func secretLine(_ prompt: String) throws -> String {
		guard let value = Terminal.askSecret(prompt) else { throw Ext.Failure.run("The input ended before the answer to the challenge.") }
		return value
	}

	private func number(of count: Int) throws -> Int {
		while true {
			let text = try line("Number: ")
			if let number = Int(text.trimmingCharacters(in: .whitespaces)), (1...count).contains(number) { return number - 1 }
			Terminal.error("Type a number from 1 to \(count).")
		}
	}

	private func show(_ image: ChallengeImage) throws {
		try FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
		let suffix = image.data.starts(with: [0xFF, 0xD8]) ? "jpg" : "png"
		let file = imageFolder.appending(path: "challenge-\(UUID().uuidString.prefix(8)).\(suffix)")
		try image.data.write(to: file)
		Terminal.error("The challenge image is in \(file.path)")
	}
}
