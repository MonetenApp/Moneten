import Domain
import SwiftUI

/// An entry of the sidebar section "Searches". It shows no count, because that would run every saved search on
/// each drawing of the sidebar.
struct SavedSearchRow: View {
	@Environment(AppModel.self) private var model
	let search: SavedSearch

	var body: some View {
		Label(search.name, systemImage: "magnifyingglass")
			.contextMenu {
				Button("Rename...") { model.sheet = .renameSearch(search.id) }
				Button("Remove") { model.remove(search: search.id) }
			}
	}
}
