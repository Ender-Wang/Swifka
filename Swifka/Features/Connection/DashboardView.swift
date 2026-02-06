import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let l10n = appState.l10n

        if !appState.connectionStatus.isConnected {
            ContentUnavailableView(
                l10n["dashboard.not.connected"],
                systemImage: "network.slash",
                description: Text(l10n["dashboard.not.connected.description"]),
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Stat cards
                    HStack(spacing: 16) {
                        StatCard(
                            title: l10n["dashboard.brokers"],
                            value: "\(appState.brokers.count)",
                            icon: "server.rack",
                            color: .blue,
                        )
                        StatCard(
                            title: l10n["dashboard.topics"],
                            value: "\(appState.topics.count(where: { !$0.isInternal }))",
                            icon: "list.bullet.rectangle",
                            color: .green,
                        )
                        StatCard(
                            title: l10n["dashboard.partitions"],
                            value: "\(appState.totalPartitions)",
                            icon: "square.split.2x2",
                            color: .orange,
                        )
                    }

                    // Broker table
                    GroupBox(l10n["brokers.title"]) {
                        Table(appState.brokers) {
                            TableColumn(l10n["brokers.id"]) { broker in
                                Text("\(broker.id)")
                            }
                            .width(min: 60, ideal: 80)

                            TableColumn(l10n["brokers.host"]) { broker in
                                Text(broker.host)
                            }

                            TableColumn(l10n["brokers.port"]) { broker in
                                Text("\(broker.port)")
                            }
                            .width(min: 60, ideal: 80)
                        }
                        .frame(minHeight: 120)
                    }
                }
                .padding()
            }
            .navigationTitle(l10n["dashboard.title"])
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary),
        )
    }
}
