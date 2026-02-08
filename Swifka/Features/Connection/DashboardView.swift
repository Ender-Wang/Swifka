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
                    .padding(.bottom, 20)

                    // Broker table
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n["brokers.title"])
                            .font(.system(size: 22, weight: .regular, design: .rounded))

                        Grid(alignment: .leading, verticalSpacing: 0) {
                            GridRow {
                                Text(l10n["brokers.id"])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(l10n["brokers.host"])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(l10n["brokers.port"])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)

                            ForEach(appState.brokers) { broker in
                                GridRow {
                                    Text("\(broker.id)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(broker.host)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(broker.port)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.quaternary),
                    )

                    // Topics table
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n["topics.title"])
                            .font(.system(size: 22, weight: .regular, design: .rounded))

                        Grid(alignment: .leading, verticalSpacing: 0) {
                            GridRow {
                                Text(l10n["topics.name"])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(l10n["topics.partitions"])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(l10n["topics.replicas"])
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)

                            ForEach(appState.topics.filter { !$0.isInternal }) { topic in
                                GridRow {
                                    Text(topic.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(topic.partitionCount)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(topic.replicaCount)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.quaternary),
                    )
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
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 14))
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
