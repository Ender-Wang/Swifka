import Charts
import SwiftUI

// MARK: - Shared Card Wrapper

struct TrendCard<Content: View> {
    let title: String
    @ViewBuilder let content: () -> Content
}

extension TrendCard: View {
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

// MARK: - Chip Toggle Style

struct ChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    configuration.isOn ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear),
                    in: Capsule(),
                )
                .foregroundStyle(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .overlay(Capsule().strokeBorder(configuration.isOn ? AnyShapeStyle(.tint.opacity(0.4)) : AnyShapeStyle(.quaternary)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cluster Throughput

struct ClusterThroughputChart: View {
    let store: MetricStore
    let l10n: L10n
    let timeDomain: ClosedRange<Date>

    var body: some View {
        let data = store.clusterThroughput.filter { timeDomain.contains($0.timestamp) }

        TrendCard(title: l10n["trends.cluster.throughput"]) {
            Chart(data) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("msg/s", point.messagesPerSecond),
                    series: .value("Segment", point.segment),
                )
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("msg/s", point.messagesPerSecond),
                    series: .value("Segment", point.segment),
                )
                .foregroundStyle(.blue.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: timeDomain)
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
    let timeDomain: ClosedRange<Date>

    var body: some View {
        let data = store.pingHistory.filter { timeDomain.contains($0.timestamp) }

        TrendCard(title: l10n["trends.ping.latency"]) {
            Chart(data) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("ms", point.ms),
                    series: .value("Segment", point.segment),
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: timeDomain)
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
    let timeDomain: ClosedRange<Date>
    @Binding var selectedTopics: [String]

    /// Switch to log scale when selected topics span >20× difference in peak throughput.
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
            let userTopics = store.knownTopics.filter { !$0.hasPrefix("__") }
            let allSelected = userTopics.allSatisfy { selectedTopics.contains($0) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(userTopics, id: \.self) { topic in
                        Toggle(topic, isOn: Binding(
                            get: { selectedTopics.contains(topic) },
                            set: { on in
                                if on { selectedTopics.append(topic) }
                                else { selectedTopics.removeAll { $0 == topic } }
                            },
                        ))
                        .toggleStyle(ChipToggleStyle())
                    }

                    Divider().frame(height: 16)

                    Button {
                        if allSelected {
                            selectedTopics.removeAll()
                        } else {
                            selectedTopics = userTopics
                        }
                    } label: {
                        Image(systemName: allSelected ? "checklist.unchecked" : "checklist.checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            let chart = Chart {
                ForEach(selectedTopics, id: \.self) { topic in
                    let series = store.throughputSeries(for: topic)
                        .filter { timeDomain.contains($0.timestamp) }
                    ForEach(series) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("msg/s", logScale ? max(0.1, point.messagesPerSecond) : point.messagesPerSecond),
                            series: .value("Series", "\(topic)-\(point.segment)"),
                        )
                        .foregroundStyle(by: .value("Topic", topic))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartXScale(domain: timeDomain)
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
    let timeDomain: ClosedRange<Date>
    @Binding var selectedGroups: [String]

    /// Switch to log scale when selected groups span >20× difference in peak lag.
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
                let allGroupsSelected = store.knownGroups.allSatisfy { selectedGroups.contains($0) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.knownGroups, id: \.self) { group in
                            Toggle(group, isOn: Binding(
                                get: { selectedGroups.contains(group) },
                                set: { on in
                                    if on { selectedGroups.append(group) }
                                    else { selectedGroups.removeAll { $0 == group } }
                                },
                            ))
                            .toggleStyle(ChipToggleStyle())
                        }

                        Divider().frame(height: 16)

                        Button {
                            if allGroupsSelected {
                                selectedGroups.removeAll()
                            } else {
                                selectedGroups = store.knownGroups
                            }
                        } label: {
                            Image(systemName: allGroupsSelected ? "checklist.unchecked" : "checklist.checked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                let chart = Chart {
                    ForEach(selectedGroups, id: \.self) { group in
                        let series = store.lagSeries(for: group)
                            .filter { timeDomain.contains($0.timestamp) }
                        ForEach(series) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Lag", logScale ? max(1, point.totalLag) : point.totalLag),
                                series: .value("Series", "\(group)-\(point.segment)"),
                            )
                            .foregroundStyle(by: .value("Group", group))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartXScale(domain: timeDomain)
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
    let timeDomain: ClosedRange<Date>

    var body: some View {
        let data = store.isrHealthSeries.filter { timeDomain.contains($0.timestamp) }

        TrendCard(title: l10n["trends.isr.health"]) {
            Chart(data) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Health", point.healthyRatio * 100),
                    series: .value("Segment", point.segment),
                )
                .foregroundStyle(.green.opacity(0.2))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Health", point.healthyRatio * 100),
                    series: .value("Segment", point.segment),
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: timeDomain)
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
