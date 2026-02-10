import SwiftUI

struct BrokersView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        let l10n = appState.l10n

        Table(sortedBrokers, sortOrder: $appState.brokersSortOrder) {
            TableColumn(l10n["brokers.id"], value: \.id) { broker in
                Text("\(broker.id)")
                    .fontWeight(.medium)
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }
            .width(min: 60, ideal: 100)

            TableColumn(l10n["brokers.host"], value: \.host) { broker in
                Text(broker.host)
                    .padding(.vertical, appState.rowDensity.tablePadding)
            }

            TableColumn(l10n["brokers.port"], value: \.port) { broker in
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

    private var sortedBrokers: [BrokerInfo] {
        appState.brokers.sorted(using: appState.brokersSortOrder)
    }
}
