import Charts
import SwiftUI

struct BrokersView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let l10n = appState.l10n
        let stats = appState.brokerStats

        if stats.isEmpty {
            ContentUnavailableView(
                l10n["brokers.empty"],
                systemImage: "server.rack",
                description: Text(l10n["brokers.empty.description"]),
            )
            .navigationTitle(l10n["brokers.title"])
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Leader distribution chart
                    leaderDistributionChart(stats: stats, l10n: l10n)

                    // Broker cards grid
                    brokerGrid(stats: stats, l10n: l10n)
                }
                .padding()
            }
            .navigationTitle(l10n["brokers.title"])
        }
    }

    // MARK: - Leader Distribution Chart

    private func leaderDistributionChart(stats: [BrokerStats], l10n: L10n) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n["brokers.leader.distribution"])
                .font(.headline)

            Chart(stats) { broker in
                BarMark(
                    x: .value(l10n["brokers.broker"], "Broker \(broker.id)"),
                    y: .value(l10n["brokers.leader.count"], broker.leaderCount),
                )
                .foregroundStyle(.blue)
                .annotation(position: .top) {
                    Text("\(broker.leaderCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Broker Grid

    @ViewBuilder
    private func brokerGrid(stats: [BrokerStats], l10n: L10n) -> some View {
        let columns = [
            GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 16),
        ]

        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(stats) { broker in
                brokerCard(broker: broker, l10n: l10n)
            }
        }
    }

    private func brokerCard(broker: BrokerStats, l10n: L10n) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Broker ID + status dot
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text(l10n["brokers.broker.id"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(broker.id)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                Spacer()
            }

            Divider()

            // Stats grid
            VStack(alignment: .leading, spacing: 8) {
                statRow(
                    label: l10n["brokers.host.port"],
                    value: broker.hostPort,
                )
                statRow(
                    label: l10n["brokers.leader.count"],
                    value: "\(broker.leaderCount)",
                    highlight: true,
                )
                statRow(
                    label: l10n["brokers.replica.count"],
                    value: "\(broker.replicaCount)",
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statRow(label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(highlight ? .headline : .subheadline)
                .fontWeight(highlight ? .semibold : .regular)
                .foregroundStyle(highlight ? .primary : .secondary)
        }
    }
}
