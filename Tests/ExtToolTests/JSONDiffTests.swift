import ExtensionHost
import Foundation
import Testing
@testable import ext

extension ExtTool {
	@Suite struct JSONDiffTests {
		func value(_ json: String) throws -> LuaValue {
			try JSONDecoder().decode(LuaValue.self, from: Data(json.utf8))
		}

		@Test func amountOfTheFirstTransaction() throws {
			let expected = try value(#"{"accounts": [{"transactions": [{"amount": -89.00, "name": "Rent"}]}]}"#)
			let actual = try value(#"{"accounts": [{"transactions": [{"amount": -98.00, "name": "Rent"}]}]}"#)
			#expect(JSONDiff.differences(expected: expected, actual: actual) == ["/accounts/0/transactions/0/amount: expected -89, got -98"])
		}

		@Test func numbersAreEqualByValue() throws {
			#expect(JSONDiff.differences(expected: try value(#"{"a": -89.00, "b": 2}"#), actual: try value(#"{"a": -89, "b": 2.0}"#)).isEmpty)
		}

		@Test func missingAndExtraValues() throws {
			let expected = try value(#"{"rows": [1, 2], "name": "Giro"}"#)
			let actual = try value(#"{"rows": [1, 2, 3], "owner/name": "Erika"}"#)
			#expect(JSONDiff.differences(expected: expected, actual: actual) == [
				"/name: expected \"Giro\", got nothing",
				"/owner~1name: expected nothing, got \"Erika\"",
				"/rows/2: expected nothing, got 3",
			])
		}
	}
}
