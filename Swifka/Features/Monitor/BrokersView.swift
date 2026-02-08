import SwiftUI

struct BrokersView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let l10n = appState.l10n

        Table(appState.brokers) {
            TableColumn(l10n["brokers.id"]) { broker in
                Text("\(broker.id)")
                    .fontWeight(.medium)
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }
            .width(min: 60, ideal: 100)

            TableColumn(l10n["brokers.host"]) { broker in
                Text(broker.host)
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }

            TableColumn(l10n["brokers.port"]) { broker in
                Text("\(broker.port)")
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }
            .width(min: 60, ideal: 100)
        }
        .font(.system(size: appState.rowDensity.fontSize))
        .navigationTitle(l10n["brokers.title"])
        .overlay {
            if appState.brokers.isEmpty {
                ContentUnavailableView(
                    l10n["brokers.empty"],
                    systemImage: "server.rack",
                    description: Text(l10n["brokers.empty.description"]),
                )
            }
        }
    }
}
