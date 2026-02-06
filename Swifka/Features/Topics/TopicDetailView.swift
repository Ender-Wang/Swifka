import SwiftUI

struct TopicDetailView: View {
    @Environment(AppState.self) private var appState
    let topic: TopicInfo

    var body: some View {
        let l10n = appState.l10n

        Table(topic.partitions) {
            TableColumn(l10n["topic.detail.partition.id"]) { partition in
                Text("\(partition.partitionId)")
            }
            .width(min: 50, ideal: 70)

            TableColumn(l10n["topic.detail.leader"]) { partition in
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

            TableColumn(l10n["topic.detail.low.watermark"]) { partition in
                Text(partition.lowWatermark.map(String.init) ?? "-")
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn(l10n["topic.detail.high.watermark"]) { partition in
                Text(partition.highWatermark.map(String.init) ?? "-")
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn(l10n["topic.detail.messages"]) { partition in
                Text(partition.messageCount.map(String.init) ?? "-")
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
            .width(min: 60, ideal: 90)
        }
    }
}
