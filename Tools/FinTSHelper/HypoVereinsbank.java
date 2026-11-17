/// The rules of the FinTS server of HypoVereinsbank, hbci-01.hypovereinsbank.de (issues #243 and #374). Each bank group
/// keeps its rules in a file of its own. A host is the one that hbci4java keeps, with its path, such as
/// "hbci-01.hypovereinsbank.de/bank/hbci".
final class HypoVereinsbank {
	private HypoVereinsbank() {
	}

	/// Whether the host is a server of HypoVereinsbank: its name, as `SavingsBanks.name` reads it, ends in
	/// ".hypovereinsbank.de".
	static boolean hypoVereinsbank(String host) {
		return SavingsBanks.name(host).endsWith(".hypovereinsbank.de");
	}
}
