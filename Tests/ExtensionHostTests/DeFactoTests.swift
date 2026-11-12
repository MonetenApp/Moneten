@testable import ExtensionHost
import Foundation
import Testing

@Suite struct DeFactoTests {
	@Test func urlSafeBase64() {
		#expect(mm(#"{MM.base64urldecode("SGVsbG8"), MM.binToHex(MM.base64urldecode("-_8"))}"#) == .array([.string("Hello"), .string("FBFF")]))
		#expect(mm(#"MM.base64urldecode("S")"#) == .null)
	}

	@Test func elementsWithTagAndContent() {
		#expect(mm(#"""
			(function()
				local top = MM.derdecode(MM.hexToBin("3006020101040100" .. "0500"))
				local inner = MM.derdecode(top[1][2])
				return {#top, top[1][1], MM.binToHex(top[1][2]), top[2][1], top[2][2], inner[1][1], MM.binToHex(inner[1][2]), inner[2][1], MM.binToHex(inner[2][2])}
			end)()
			"""#) == .array([.integer(2), .integer(0x30), .string("020101040100"), .integer(5), .string(""), .integer(2), .string("01"), .integer(4), .string("00")]))
		#expect(mm(#"MM.derdecode(MM.hexToBin("3006020101"))"#) == .null)
	}

	/// The steps of the signed Coinbase extension (f27.lua, lines 140-155) on the SEC1 key of RFC 6979 A.2.5,
	/// as the extension reads the private key that Coinbase hands out.
	@Test func coinbaseReadsAnECKey() {
		let sec1 = "30770201010420\(p256.d)A00A06082A8648CE3D030107A14403420004\(p256.x)\(p256.y)"
		#expect(mm(#"""
			(function()
				local key = MM.base64decode(MM.base64(MM.hexToBin("\#(sec1)")))
				local der = MM.derdecode(MM.derdecode(key)[1][2])
				local d = der[2][2]
				local p = MM.derdecode(der[4][2])[1][2]
				local x = string.sub(p, string.len(p) - 63, string.len(p) - 32)
				local y = string.sub(p, string.len(p) - 31)
				local signature = MM.ecSign({curve = "prime256v1", d = d, x = x, y = y}, "header.payload", "ecdsa sha256")
				local public = {curve = "prime256v1", x = MM.hexToBin("\#(p256.x)"), y = MM.hexToBin("\#(p256.y)")}
				return {MM.binToHex(d), MM.binToHex(x), MM.binToHex(y), signature:byte(1), MM.ecVerify(public, "header.payload", signature, "ecdsa sha256")}
			end)()
			"""#) == .array([.string(p256.d), .string(p256.x), .string(p256.y), .integer(0x30), .boolean(true)]))
	}
}
