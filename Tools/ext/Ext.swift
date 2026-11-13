import ExtensionHost
import Foundation

/// The command line of `ext`: which command, which files, and which options.
enum Ext {
	static let version = "0.1.0"
	/// Starts this binary as the host process of a session, as the app starts `MonetenExtensionHost`.
	static let hostArgument = "_host"

	static let help = """
		Usage: ext <command> [options]

		Runs, records, and tests a Moneten web banking extension outside the app.

		Commands:
		  run <script>                        Run the script and print the result as JSON.
		  record <script> <fixture>           Run the script and save its HTTP traffic without secrets.
		  test <script> <fixture> <expected>  Replay the fixture without network and compare the result.

		Options:
		  --service <name>   The service to use when the script has several.
		  --storage <file>   The LocalStorage file of run. Default: <script>.storage.json next to the script.
		  --fresh            Start run with an empty LocalStorage.
		  --trust <file>     Trust this certificate (PEM or DER) for HTTPS in run and record, for a test server.
		  --keep-random      Let record keep random values that only the replay needs, also after the script used
		                     a key that ext cannot trace to a random value. Use it only for values such as a PKCE verifier.
		  --update           Write the result of test to the expected file.
		  -h, --help         Show this help.
		  --version          Show the version of ext and of the API.

		<script> is a .lua file, with an optional manifest of the same base name, or a package folder with manifest.json.
		EXT_USERNAME and EXT_PASSWORD fill the first two login fields without a question. Set EXT_PASSWORD with
		read -s EXT_PASSWORD && export EXT_PASSWORD, never on the command line, which the shell history keeps.

		Exit status: 0 success, 1 test difference, 2 script or login error, 64 wrong arguments.

		"""

	enum Command: Equatable {
		case run(script: String, storage: String?, fresh: Bool, trust: String?)
		case record(script: String, fixture: String, trust: String?, keepRandom: Bool)
		case test(script: String, fixture: String, expected: String, update: Bool)
		case help
		case version
	}

	struct Invocation: Equatable {
		let command: Command
		let service: String?
	}

	/// Why a command stopped. Each has its exit status and one line for standard error.
	enum Failure: Error, Equatable {
		case usage(String)
		case run(String)
		case difference

		var status: Int32 {
			switch self {
			case .usage: 64
			case .run: 2
			case .difference: 1
			}
		}
	}

	static func parse(_ arguments: [String]) throws(Failure) -> Invocation {
		var positional: [String] = []
		var options: [String: String] = [:]
		var flags: Set<String> = []
		var index = 0
		while index < arguments.count {
			let argument = arguments[index]
			index += 1
			switch argument {
			case "-h", "--help", "--version", "--fresh", "--update", "--keep-random":
				flags.insert(argument == "-h" ? "--help" : argument)
			case "--service", "--storage", "--trust":
				guard index < arguments.count else { throw .usage("\(argument) needs a value.") }
				options[argument] = arguments[index]
				index += 1
			case let option where ["--service=", "--storage=", "--trust="].contains(where: option.hasPrefix):
				let parts = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
				guard parts.count == 2, !parts[1].isEmpty else { throw .usage("\(parts[0]) needs a value.") }
				options[String(parts[0])] = String(parts[1])
			case let option where option.hasPrefix("-") && option != "-":
				throw .usage("Unknown option \(option). See ext --help.")
			default:
				positional.append(argument)
			}
		}
		if flags.contains("--help") || positional == ["help"] { return Invocation(command: .help, service: nil) }
		if flags.contains("--version") { return Invocation(command: .version, service: nil) }
		guard let name = positional.first else { throw .usage("Name a command: run, record, or test. See ext --help.") }
		let files = Array(positional.dropFirst())
		func allow(_ allowed: Set<String>) throws(Failure) {
			let given = flags.union(options.keys).subtracting(["--service"])
			if let other = given.subtracting(allowed).sorted().first { throw .usage("ext \(name) has no option \(other).") }
		}
		func count(_ needed: Int, _ names: String) throws(Failure) {
			guard files.count == needed else { throw .usage("ext \(name) needs \(names).") }
		}
		let command: Command
		switch name {
		case "run":
			try allow(["--storage", "--fresh", "--trust"])
			try count(1, "<script>")
			command = .run(script: files[0], storage: options["--storage"], fresh: flags.contains("--fresh"), trust: options["--trust"])
		case "record":
			try allow(["--trust", "--keep-random"])
			try count(2, "<script> <fixture>")
			command = .record(script: files[0], fixture: files[1], trust: options["--trust"], keepRandom: flags.contains("--keep-random"))
		case "test":
			try allow(["--update"])
			try count(3, "<script> <fixture> <expected>")
			command = .test(script: files[0], fixture: files[1], expected: files[2], update: flags.contains("--update"))
		default:
			throw .usage("Unknown command \(name). See ext --help.")
		}
		return Invocation(command: command, service: options["--service"])
	}

	/// The certificates of a PEM file, or the one certificate of a DER file.
	static func certificates(_ path: String?) throws(Failure) -> [Data] {
		guard let path else { return [] }
		guard let data = try? Data(contentsOf: URL(filePath: path)) else { throw .usage("\(path) cannot be read.") }
		guard let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN CERTIFICATE-----") else { return [data] }
		var certificates: [Data] = []
		for match in text.matches(of: /-----BEGIN CERTIFICATE-----([^-]+)-----END CERTIFICATE-----/) {
			guard let der = Data(base64Encoded: match.output.1.filter { !$0.isWhitespace }) else {
				throw .usage("\(path) holds a certificate whose Base64 is broken.")
			}
			certificates.append(der)
		}
		guard !certificates.isEmpty else { throw .usage("\(path) holds no complete certificate.") }
		return certificates
	}

	static func main(_ arguments: [String]) async -> Int32 {
		do {
			let invocation = try parse(arguments)
			switch invocation.command {
			case .help:
				print(help, terminator: "")
			case .version:
				print("ext \(version), API version \(extensionAPIVersion)")
			case let .run(script, storage, fresh, trust):
				try await RunCommand(script: script, service: invocation.service, storage: storage, fresh: fresh, trust: trust).execute()
			case let .record(script, fixture, trust, keepRandom):
				try await RecordCommand(script: script, fixture: fixture, service: invocation.service, trust: trust, keepRandom: keepRandom).execute()
			case let .test(script, fixture, expected, update):
				try await TestCommand(script: script, fixture: fixture, expected: expected, service: invocation.service, update: update).execute()
			}
			return 0
		} catch let failure as Failure {
			if case let .usage(message) = failure { Terminal.error(message) }
			if case let .run(message) = failure { Terminal.error(message) }
			return failure.status
		} catch {
			Terminal.error("\(error)")
			return 2
		}
	}
}
