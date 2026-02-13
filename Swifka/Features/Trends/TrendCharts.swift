import Charts
import SwiftUI

// MARK: - Shared Card Wrapper

struct TrendCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
            content()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary),
        )
    }
}

// MARK: - Cluster Throughput

struct ClusterThroughputChart: View {
    let store: MetricStore
    let l10n: L10n

    var body: some View {
        let data = store.clusterThroughput

        TrendCard(title: l10n["trends.cluster.throughput"]) {
            Chart(data) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("msg/s", point.messagesPerSecond),
                )
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("msg/s", point.messagesPerSecond),
                )
                .foregroundStyle(.blue.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
            .chartYAxisLabel(l10n["trends.messages.per.second"])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                    AxisGridLine()
                }
            }
            .frame(height: 200)
        }
    }
}

// MARK: - Ping Latency

struct PingLatencyChart: View {
    let store: MetricStore
    let l10n: L10n

    var body: some View {
        let data = store.pingHistory

        TrendCard(title: l10n["trends.ping.latency"]) {
            Chart(data) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("ms", point.ms),
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
            }
            .chartYAxisLabel("ms")
            .chartXAxis(.hidden)
            .frame(height: 200)
        }
    }
}

// MARK: - Per-Topic Throughput

struct TopicThroughputChart: View {
    let store: MetricStore
    let l10n: L10n
    @Binding var selectedTopics: Set<String>

    /// Switch to log scale when selected topics span >20× difference in peak throughput.
    /// At 20× ratio the smallest series gets ~12px on a 250px chart — below that, fluctuations are unreadable.
    private var useLogScale: Bool {
        guard selectedTopics.count > 1 else { return false }
        var peaks: [Double] = []
        for topic in selectedTopics {
            let series = store.throughputSeries(for: topic)
            if let peak = series.map(\.messagesPerSecond).max(), peak > 0 {
                peaks.append(peak)
            }
        }
        guard let lo = peaks.min(), let hi = peaks.max(), lo > 0 else { return false }
        return hi / lo > 20
    }

    var body: some View {
        let logScale = useLogScale

        TrendCard(title: l10n["trends.topic.throughput"]) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.knownTopics.filter { !$0.hasPrefix("__") }, id: \.self) { topic in
                        Toggle(topic, isOn: Binding(
                            get: { selectedTopics.contains(topic) },
                            set: { on in
                                if on { selectedTopics.insert(topic) }
                                else { selectedTopics.remove(topic) }
                            },
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            }

            let chart = Chart {
                ForEach(Array(selectedTopics), id: \.self) { topic in
                    let series = store.throughputSeries(for: topic)
                    ForEach(series) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("msg/s", logScale ? max(0.1, point.messagesPerSecond) : point.messagesPerSecond),
                        )
                        .foregroundStyle(by: .value("Topic", topic))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartYAxisLabel(l10n["trends.messages.per.second"])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                    AxisGridLine()
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 250)

            if logScale {
                chart.chartYScale(type: .log)
            } else {
                chart
            }
        }
    }
}

// MARK: - Consumer Group Lag

struct ConsumerGroupLagChart: View {
    let store: MetricStore
    let l10n: L10n
    @Binding var selectedGroups: Set<String>

    /// Switch to log scale when selected groups span >20× difference in peak lag.
    /// At 20× ratio the smallest series gets ~12px on a 250px chart — below that, fluctuations are unreadable.
    private var useLogScale: Bool {
        guard selectedGroups.count > 1 else { return false }
        var peaks: [Double] = []
        for group in selectedGroups {
            let series = store.lagSeries(for: group)
            if let peak = series.map({ Double($0.totalLag) }).max(), peak > 0 {
                peaks.append(peak)
            }
        }
        guard let lo = peaks.min(), let hi = peaks.max(), lo > 0 else { return false }
        return hi / lo > 20
    }

    var body: some View {
        let logScale = useLogScale

        TrendCard(title: l10n["trends.consumer.lag"]) {
            if store.knownGroups.isEmpty {
                ContentUnavailableView {
                    Label(l10n["trends.consumer.lag"], systemImage: "person.3")
                } description: {
                    Text(l10n["trends.not.enough.data.description"])
                }
                .frame(height: 200)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.knownGroups, id: \.self) { group in
                            Toggle(group, isOn: Binding(
                                get: { selectedGroups.contains(group) },
                                set: { on in
                                    if on { selectedGroups.insert(group) }
                                    else { selectedGroups.remove(group) }
                                },
                            ))
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }
                }

                let chart = Chart {
                    ForEach(Array(selectedGroups), id: \.self) { group in
                        let series = store.lagSeries(for: group)
                        ForEach(series) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Lag", logScale ? max(1, point.totalLag) : point.totalLag),
                            )
                            .foregroundStyle(by: .value("Group", group))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartYAxisLabel(l10n["trends.lag.messages"])
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                        AxisGridLine()
                    }
                }
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 250)

                if logScale {
                    chart.chartYScale(type: .log)
                } else {
                    chart
                }
            }
        }
    }
}

// MARK: - ISR Health

struct ISRHealthChart: View {
    let store: MetricStore
    let l10n: L10n

    var body: some View {
        let data = store.isrHealthSeries

        TrendCard(title: l10n["trends.isr.health"]) {
            Chart(data) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Health", point.healthyRatio * 100),
                )
                .foregroundStyle(.green.opacity(0.2))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Health", point.healthyRatio * 100),
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0 ... 100)
            .chartYAxisLabel("%")
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                    AxisGridLine()
                }
            }
            .frame(height: 150)
        }
    }
}
