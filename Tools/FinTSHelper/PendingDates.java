import java.util.Date;

import org.kapott.hbci.GV_Result.GVRKUms.UmsLine;

/// The day of a pending MT942 row (issue #374). The ":61:" line of MT942 has a value date and may have an entry date
/// (MMDD), which hbci4java reads as the booking date. Most banks put the day of the request or nothing useful there, so
/// a pending MT942 row takes its value date. The servers of ING, Commerzbank, and HypoVereinsbank send the day on which
/// they expect to book the row as the entry date, so their pending rows take it. Each of these hosts is a rule of its
/// bank group file. A booked row and a CAMT row keep the booking date that hbci4java reads.
final class PendingDates {
	private PendingDates() {
	}

	/// Whether the FinTS server at `host` sends the day on which it expects to book a pending MT942 row as its entry date.
	static boolean expectedDayInEntryDate(String host) {
		return Ing.ing(host) || CommerzbankGroup.commerzbank(host) || HypoVereinsbank.hypoVereinsbank(host);
	}

	/// The day of the row `l` from the server at `host`: the value date of a pending MT942 row, unless the server sends
	/// its expected day as the entry date, and otherwise the booking date. A row without that day takes the other one.
	static Date booked(UmsLine l, boolean pending, String host) {
		boolean valueFirst = pending && !l.isCamt && !expectedDayInEntryDate(host);
		Date first = valueFirst ? l.valuta : l.bdate, second = valueFirst ? l.bdate : l.valuta;
		return first != null ? first : second;
	}
}
