import Domain
import Foundation

/// The sidebar section "Searches" (add-transaction-search-and-filters, task 1.20). Each change goes to the
/// database first and to `savedSearches` only after the write succeeds, as a change of the ledger does.
extension AppModel {
	/// Whether the search field and the filter bar hold something to save.
	var canSaveSearch: Bool { store != nil && SavedSearch.canSave(period: period, filter: filter) }

	/// Saves the search field and the filter bar on screen under `name`, as the last entry of "Searches".
	func saveSearch(name: String) {
		guard let store else { return }
		let search = SavedSearch(name: name, position: (savedSearches.map(\.position).max() ?? -1) + 1, period: period, filter: filter)
		do {
			try store.save(search)
			savedSearches.append(search)
		} catch {
			alert = AlertMessage(title: "Could not save the search.", message: String(describing: error))
		}
	}

	func rename(search id: UUID, to name: String) {
		guard let store, let index = savedSearches.firstIndex(where: { $0.id == id }) else { return }
		var search = savedSearches[index]
		search.name = name
		do {
			try store.save(search)
			savedSearches[index] = search
		} catch {
			alert = AlertMessage(title: "Could not rename the search.", message: String(describing: error))
		}
	}

	/// Removes the entry and changes no transaction. The search field and the filter bar stay as they are.
	func remove(search id: UUID) {
		guard let store else { return }
		do {
			try store.deleteSavedSearch(id)
			savedSearches.removeAll { $0.id == id }
			if selection == .search(id) { select(nil) }
		} catch {
			alert = AlertMessage(title: "Could not remove the search.", message: String(describing: error))
		}
	}

	/// Puts a saved search into the search field and the filter bar, like a choice by hand, so leaving it keeps
	/// them by the rule for every view, and a pin that is on saves them.
	func applySavedSearch(_ id: UUID) {
		guard let saved = savedSearches.first(where: { $0.id == id }) else { return }
		choose(period: saved.bar.period)
		filter = saved.filter(in: ledger)
	}
}
