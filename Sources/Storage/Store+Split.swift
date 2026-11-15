import Domain
import Foundation
import GRDB

extension Store {
	public func replaceParts(of transactionID: UUID, with parts: [SplitPart]) throws {
		try queue.write { db in
			let original = try Transaction.find(db, key: transactionID)
			if !parts.isEmpty {
				guard !original.isPending else { throw SplitError.pending }
				guard parts.count > 1 else { throw SplitError.onePart }
				guard parts.allSatisfy({ $0.amountMinor != 0 }) else { throw SplitError.zeroPart }
				guard parts.reduce(Int128(0), { $0 + Int128($1.amountMinor) }) == Int128(original.amountMinor) else {
					throw SplitError.unbalanced
				}
			}
			_ = try SplitPart.filter(Column("transactionID") == transactionID).deleteAll(db)
			for var part in parts {
				part.transactionID = transactionID
				try part.insert(db)
			}
		}
	}
}
