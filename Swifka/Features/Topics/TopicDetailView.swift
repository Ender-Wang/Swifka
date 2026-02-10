import SwiftUI

struct TopicDetailView: View {
    @Environment(AppState.self) private var appState
    let topic: TopicInfo

    var body: some View {
        @Bindable var appState = appState
        let l10n = appState.l10n

        Table(sortedPartitions, sortOrder: $appState.partitionsSortOrder) {
            TableColumn(l10n["topic.detail.partition.id"], value: \.partitionId) { partition in
                Text("\(partition.partitionId)")
            }
            .width(min: 50, ideal: 70)

            TableColumn(l10n["topic.detail.leader"], value: \.leader) { partition in
                Text("\(partition.leader)")
            }
            .width(min: 50, ideal: 70)

            TableColumn(l10n["topic.detail.replicas"]) { partition in
                Text(partition.replicas.map(String.init).joined(separator: ", "))
            }
            .width(min: 60, ideal: 90)

            TableColumn(l10n["topic.detail.isr"]) { partition in
                Text(partition.isr.map(String.init).joined(separator: ", "))
            }
            .width(min: 60, ideal: 90)

            TableColumn(l10n["topic.detail.low.watermark"], value: \.lowWatermark) { partition in
                Text(partition.lowWatermark.map(String.init) ?? "-")
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn(l10n["topic.detail.high.watermark"], value: \.highWatermark) { partition in
                Text(partition.highWatermark.map(String.init) ?? "-")
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn(l10n["topic.detail.messages"], value: \.messageCount) { partition in
                Text(partition.messageCount.map(String.init) ?? "-")
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
            .width(min: 60, ideal: 90)
        }
    }

    private var sortedPartitions: [PartitionInfo] {
        topic.partitions.sorted(using: appState.partitionsSortOrder)
    }
}
