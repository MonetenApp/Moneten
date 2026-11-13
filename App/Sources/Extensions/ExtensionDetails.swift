import ExtensionHost
import SwiftUI

/// What the user sees before installing: the services with the labels of their login fields, the hosts,
/// the license, and the folder of the package in the catalog repository.
struct ExtensionDetails: View {
	@Environment(AppModel.self) private var model
	let item: ExtensionLibrary.Item

	var body: some View {
		Form {
			Section {
				LabeledContent("Version", value: item.version ?? "-")
				if !item.kinds.isEmpty { LabeledContent("Fetches", value: item.kinds.map(\.capitalized).formatted(.list(type: .and))) }
				if let badge = item.badge { LabeledContent("State", value: badge) }
				if let note = item.note { Text(note).foregroundStyle(.orange) }
			} header: {
				VStack(alignment: .leading, spacing: 4) {
					Text(item.name).font(.title2.bold()).foregroundStyle(.primary)
					if !item.description.isEmpty { Text(item.description).foregroundStyle(.secondary) }
				}
				.textCase(nil)
			}
			if let manifest = item.manifest {
				Section("Services") {
					ForEach(manifest.services ?? [], id: \.name) { service in
						LabeledContent(service.name, value: service.login.map(\.label).formatted(.list(type: .and)))
					}
				}
				Section("Hosts") {
					if let hosts = manifest.hosts {
						ForEach(hosts, id: \.self) { Text($0.value).monospaced() }
					} else {
						Text("No list of hosts. Moneten asks before each new host.").foregroundStyle(.secondary)
					}
				}
				Section {
					if let license = manifest.license { LabeledContent("License", value: license) }
					if item.isCatalog, let url = URL(string: "https://github.com/MonetenApp/moneten-extensions/tree/main/extensions/\(item.id)") {
						Link("Show in the Catalog Repository", destination: url)
					}
				}
			}
			Section {
				HStack {
					if let action = item.action { ExtensionActionButton(item: item, action: action) }
					Spacer()
					if item.section == .installed {
						Button("Remove...", role: .destructive) { model.extensions.askRemove(item.id) }
					}
				}
			}
		}
		.formStyle(.grouped)
	}
}
