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

// MARK: - Rendering Mode Helpers

private extension TrendRenderingMode {
    /// Filter data for live mode; return all data for history (chart handles scrolling).
    func filterData<T>(_ data: [T], by timestamp: KeyPath<T, Date>) -> [T] {
        switch self {
        case let .live(timeDomain):
            data.filter { timeDomain.contains($0[keyPath: timestamp]) }
        case .history:
            data
        }
    }
}

// MARK: - Hover Overlay

/// Tooltip container with timestamp header.
private struct ChartTooltip<Content: View>: View {
    let date: Date
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private func nearest<T>(_ data: [T], to date: Date, by keyPath: KeyPath<T, Date>) -> T? {
    data.min(by: { abs($0[keyPath: keyPath].timeIntervalSince(date)) < abs($1[keyPath: keyPath].timeIntervalSince(date)) })
}

private struct TopicHoverItem: Identifiable {
    let id: String
    let point: ThroughputPoint
}

private struct GroupHoverItem: Identifiable {
    let id: String
    let point: LagPoint
}

/// Color palette matching Swift Charts' default series colors.
private let seriesColors: [Color] = [.blue, .green, .orange, .red, .purple, .pink, .yellow, .cyan, .mint, .indigo]

/// Tracks mouse hover on the chart view and draws a rule line + tooltip
/// via `.chartOverlay`. No marks are injected into the Chart content builder,
/// so the chart's axis scales are never perturbed.
private extension View {
    func hoverOverlay(
        hoverLocation: Binding<CGPoint?>,
        @ViewBuilder tooltip: @escaping (Date) -> some View,
    ) -> some View {
        onContinuousHover { phase in
            switch phase {
            case let .active(location):
                hoverLocation.wrappedValue = location
            case .ended:
                hoverLocation.wrappedValue = nil
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let location = hoverLocation.wrappedValue,
                   let frame = proxy.plotFrame
                {
                    let plotArea = geometry[frame]
                    let plotX = location.x - plotArea.origin.x
                    let plotY = location.y - plotArea.origin.y

                    if plotX >= 0, plotX <= plotArea.width,
                       plotY >= 0, plotY <= plotArea.height,
                       let date: Date = proxy.value(atX: plotX, as: Date.self),
                       let xPos = proxy.position(forX: date)
                    {
                        let screenX = plotArea.origin.x + xPos

                        // Vertical rule line
                        Rectangle()
                            .fill(.secondary.opacity(0.3))
                            .frame(width: 1, height: plotArea.height)
                            .position(x: screenX, y: plotArea.midY)

                        // Tooltip — offset left/right depending on cursor half
                        let tooltipX = screenX > plotArea.midX
                            ? max(screenX - 60, plotArea.minX + 40)
                            : min(screenX + 60, plotArea.maxX - 40)

                        tooltip(date)
                            .fixedSize()
                            .position(x: tooltipX, y: plotArea.minY + 24)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Cluster Throughput

struct ClusterThroughputChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @State private var hoverLocation: CGPoint?

    var body: some View {
        let data = renderingMode.filterData(store.clusterThroughput, by: \.timestamp)

        TrendCard(title: l10n["trends.cluster.throughput"]) {
            let chart = Chart {
                ForEach(data) { point in
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
            }
            .chartYAxisLabel(l10n["trends.messages.per.second"])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                    AxisGridLine()
                }
            }
            .frame(height: 200)

            switch renderingMode {
            case let .live(timeDomain):
                chart.chartXScale(domain: timeDomain)
                    .drawingGroup()
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        if let p = nearest(data, to: date, by: \.timestamp) {
                            ChartTooltip(date: p.timestamp) {
                                HStack(spacing: 4) {
                                    Circle().fill(.blue).frame(width: 8, height: 8)
                                    Text(String(format: "%.1f msg/s", p.messagesPerSecond))
                                        .font(.caption2).bold()
                                }
                            }
                        }
                    }
            case let .history(visibleSeconds):
                chart
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleSeconds)
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        if let p = nearest(data, to: date, by: \.timestamp) {
                            ChartTooltip(date: p.timestamp) {
                                HStack(spacing: 4) {
                                    Circle().fill(.blue).frame(width: 8, height: 8)
                                    Text(String(format: "%.1f msg/s", p.messagesPerSecond))
                                        .font(.caption2).bold()
                                }
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - Ping Latency

struct PingLatencyChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @State private var hoverLocation: CGPoint?

    var body: some View {
        let data = renderingMode.filterData(store.pingHistory, by: \.timestamp)

        TrendCard(title: l10n["trends.ping.latency"]) {
            let chart = Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("ms", point.ms),
                        series: .value("Segment", point.segment),
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxisLabel("ms")
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                    AxisGridLine()
                }
            }
            .frame(height: 200)

            switch renderingMode {
            case let .live(timeDomain):
                chart.chartXScale(domain: timeDomain)
                    .drawingGroup()
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        if let p = nearest(data, to: date, by: \.timestamp) {
                            ChartTooltip(date: p.timestamp) {
                                HStack(spacing: 4) {
                                    Circle().fill(.green).frame(width: 8, height: 8)
                                    Text("\(p.ms) ms")
                                        .font(.caption2).bold()
                                }
                            }
                        }
                    }
            case let .history(visibleSeconds):
                chart
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleSeconds)
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        if let p = nearest(data, to: date, by: \.timestamp) {
                            ChartTooltip(date: p.timestamp) {
                                HStack(spacing: 4) {
                                    Circle().fill(.green).frame(width: 8, height: 8)
                                    Text("\(p.ms) ms")
                                        .font(.caption2).bold()
                                }
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - Per-Topic Throughput

struct TopicThroughputChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @Binding var selectedTopics: [String]
    @State private var hoverLocation: CGPoint?

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

    @ViewBuilder
    private func topicTooltip(_ date: Date) -> some View {
        let items: [TopicHoverItem] = selectedTopics.compactMap { topic in
            let series = renderingMode.filterData(store.throughputSeries(for: topic), by: \.timestamp)
            return nearest(series, to: date, by: \.timestamp).map { TopicHoverItem(id: topic, point: $0) }
        }
        .sorted { $0.point.messagesPerSecond > $1.point.messagesPerSecond }
        if let first = items.first {
            ChartTooltip(date: first.point.timestamp) {
                ForEach(items) { item in
                    let colorIndex = selectedTopics.firstIndex(of: item.id) ?? 0
                    HStack(spacing: 4) {
                        Circle().fill(seriesColors[colorIndex % seriesColors.count]).frame(width: 8, height: 8)
                        Text(String(format: "%@: %.1f msg/s", item.id, item.point.messagesPerSecond))
                            .font(.caption2)
                    }
                }
            }
        }
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
                    let series = renderingMode.filterData(
                        store.throughputSeries(for: topic), by: \.timestamp,
                    )
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
            .chartYAxisLabel(l10n["trends.messages.per.second"])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                    AxisGridLine()
                }
            }
            .chartForegroundStyleScale(domain: selectedTopics, range: Array(seriesColors.prefix(max(selectedTopics.count, 1))))
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 250)

            switch renderingMode {
            case let .live(timeDomain):
                if logScale {
                    chart.chartXScale(domain: timeDomain).chartYScale(type: .log)
                        .drawingGroup()
                        .hoverOverlay(hoverLocation: $hoverLocation) { date in topicTooltip(date) }
                } else {
                    chart.chartXScale(domain: timeDomain)
                        .drawingGroup()
                        .hoverOverlay(hoverLocation: $hoverLocation) { date in topicTooltip(date) }
                }
            case let .history(visibleSeconds):
                if logScale {
                    chart.chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: visibleSeconds)
                        .chartYScale(type: .log)
                        .hoverOverlay(hoverLocation: $hoverLocation) { date in topicTooltip(date) }
                } else {
                    chart.chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: visibleSeconds)
                        .hoverOverlay(hoverLocation: $hoverLocation) { date in topicTooltip(date) }
                }
            }
        }
    }
}

// MARK: - Consumer Group Lag

struct ConsumerGroupLagChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @Binding var selectedGroups: [String]
    @State private var hoverLocation: CGPoint?

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

    @ViewBuilder
    private func groupTooltip(_ date: Date) -> some View {
        let items: [GroupHoverItem] = selectedGroups.compactMap { group in
            let series = renderingMode.filterData(store.lagSeries(for: group), by: \.timestamp)
            return nearest(series, to: date, by: \.timestamp).map { GroupHoverItem(id: group, point: $0) }
        }
        .sorted { $0.point.totalLag > $1.point.totalLag }
        if let first = items.first {
            ChartTooltip(date: first.point.timestamp) {
                ForEach(items) { item in
                    let colorIndex = selectedGroups.firstIndex(of: item.id) ?? 0
                    HStack(spacing: 4) {
                        Circle().fill(seriesColors[colorIndex % seriesColors.count]).frame(width: 8, height: 8)
                        Text("\(item.id): \(item.point.totalLag)")
                            .font(.caption2)
                    }
                }
            }
        }
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
                        let series = renderingMode.filterData(
                            store.lagSeries(for: group), by: \.timestamp,
                        )
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
                .chartYAxisLabel(l10n["trends.lag.messages"])
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                        AxisGridLine()
                    }
                }
                .chartForegroundStyleScale(domain: selectedGroups, range: Array(seriesColors.prefix(max(selectedGroups.count, 1))))
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 250)

                switch renderingMode {
                case let .live(timeDomain):
                    if logScale {
                        chart.chartXScale(domain: timeDomain).chartYScale(type: .log)
                            .drawingGroup()
                            .hoverOverlay(hoverLocation: $hoverLocation) { date in groupTooltip(date) }
                    } else {
                        chart.chartXScale(domain: timeDomain)
                            .drawingGroup()
                            .hoverOverlay(hoverLocation: $hoverLocation) { date in groupTooltip(date) }
                    }
                case let .history(visibleSeconds):
                    if logScale {
                        chart.chartScrollableAxes(.horizontal)
                            .chartXVisibleDomain(length: visibleSeconds)
                            .chartYScale(type: .log)
                            .hoverOverlay(hoverLocation: $hoverLocation) { date in groupTooltip(date) }
                    } else {
                        chart.chartScrollableAxes(.horizontal)
                            .chartXVisibleDomain(length: visibleSeconds)
                            .hoverOverlay(hoverLocation: $hoverLocation) { date in groupTooltip(date) }
                    }
                }
            }
        }
    }
}

// MARK: - Per-Topic Lag

struct TopicLagChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @Binding var selectedTopics: [String]
    @State private var hoverLocation: CGPoint?

    /// Switch to log scale when selected topics span >20× difference in peak lag.
    private var useLogScale: Bool {
        let active = selectedTopics.filter { store.knownLagTopics.contains($0) }
        guard active.count > 1 else { return false }
        var peaks: [Double] = []
        for topic in active {
            let series = store.topicLagSeries(for: topic)
            if let peak = series.map({ Double($0.totalLag) }).max(), peak > 0 {
                peaks.append(peak)
            }
        }
        guard let lo = peaks.min(), let hi = peaks.max(), lo > 0 else { return false }
        return hi / lo > 20
    }

    @ViewBuilder
    private func topicLagTooltip(_ date: Date) -> some View {
        let lagTopics = store.knownLagTopics.filter { !$0.hasPrefix("__") }
        let active = selectedTopics.filter { lagTopics.contains($0) }
        let items: [GroupHoverItem] = active.compactMap { topic in
            let series = renderingMode.filterData(store.topicLagSeries(for: topic), by: \.timestamp)
            return nearest(series, to: date, by: \.timestamp).map { GroupHoverItem(id: topic, point: $0) }
        }
        .sorted { $0.point.totalLag > $1.point.totalLag }
        if let first = items.first {
            ChartTooltip(date: first.point.timestamp) {
                ForEach(items) { item in
                    let colorIndex = active.firstIndex(of: item.id) ?? 0
                    HStack(spacing: 4) {
                        Circle().fill(seriesColors[colorIndex % seriesColors.count]).frame(width: 8, height: 8)
                        Text("\(item.id): \(item.point.totalLag)")
                            .font(.caption2)
                    }
                }
            }
        }
    }

    var body: some View {
        let logScale = useLogScale
        let lagTopics = store.knownLagTopics.filter { !$0.hasPrefix("__") }

        TrendCard(title: l10n["trends.topic.lag"]) {
            if lagTopics.isEmpty {
                ContentUnavailableView {
                    Label(l10n["trends.topic.lag"], systemImage: "chart.line.downtrend.xyaxis")
                } description: {
                    Text(l10n["trends.not.enough.data.description"])
                }
                .frame(height: 200)
            } else {
                let allSelected = lagTopics.allSatisfy { selectedTopics.contains($0) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(lagTopics, id: \.self) { topic in
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
                                selectedTopics.removeAll { lagTopics.contains($0) }
                            } else {
                                for topic in lagTopics where !selectedTopics.contains(topic) {
                                    selectedTopics.append(topic)
                                }
                            }
                        } label: {
                            Image(systemName: allSelected ? "checklist.unchecked" : "checklist.checked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                let activeSeries = selectedTopics.filter { lagTopics.contains($0) }

                let chart = Chart {
                    ForEach(activeSeries, id: \.self) { topic in
                        let series = renderingMode.filterData(
                            store.topicLagSeries(for: topic), by: \.timestamp,
                        )
                        ForEach(series) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Lag", logScale ? max(1, point.totalLag) : point.totalLag),
                                series: .value("Series", "\(topic)-\(point.segment)"),
                            )
                            .foregroundStyle(by: .value("Topic", topic))
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
                .chartForegroundStyleScale(domain: activeSeries, range: Array(seriesColors.prefix(max(activeSeries.count, 1))))
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 250)

                switch renderingMode {
                case let .live(timeDomain):
                    if logScale {
                        chart.chartXScale(domain: timeDomain).chartYScale(type: .log)
                            .drawingGroup()
                            .hoverOverlay(hoverLocation: $hoverLocation) { date in topicLagTooltip(date) }
                    } else {
                        chart.chartXScale(domain: timeDomain)
                            .drawingGroup()
                            .hoverOverlay(hoverLocation: $hoverLocation) { date in topicLagTooltip(date) }
                    }
                case let .history(visibleSeconds):
                    if logScale {
                        chart.chartScrollableAxes(.horizontal)
                            .chartXVisibleDomain(length: visibleSeconds)
                            .chartYScale(type: .log)
                            .hoverOverlay(hoverLocation: $hoverLocation) { date in topicLagTooltip(date) }
                    } else {
                        chart.chartScrollableAxes(.horizontal)
                            .chartXVisibleDomain(length: visibleSeconds)
                            .hoverOverlay(hoverLocation: $hoverLocation) { date in topicLagTooltip(date) }
                    }
                }
            }
        }
    }
}

// MARK: - Per-Partition Lag

struct PartitionLagChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @Binding var selectedTopics: [String]

    var body: some View {
        let lagTopics = Array(store.knownPartitionsByTopic.keys).sorted().filter { !$0.hasPrefix("__") }

        TrendCard(title: l10n["trends.partition.lag"]) {
            if lagTopics.isEmpty {
                ContentUnavailableView {
                    Label(l10n["trends.partition.lag"], systemImage: "chart.bar.xaxis")
                } description: {
                    Text(l10n["trends.not.enough.data.description"])
                }
                .frame(height: 200)
            } else {
                let allSelected = lagTopics.allSatisfy { selectedTopics.contains($0) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(lagTopics, id: \.self) { topic in
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
                                selectedTopics.removeAll { lagTopics.contains($0) }
                            } else {
                                for topic in lagTopics where !selectedTopics.contains(topic) {
                                    selectedTopics.append(topic)
                                }
                            }
                        } label: {
                            Image(systemName: allSelected ? "checklist.unchecked" : "checklist.checked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Each topic gets its own isolated sub-chart with independent hover state
                let activeTopics = selectedTopics.filter { lagTopics.contains($0) }
                ForEach(activeTopics, id: \.self) { topic in
                    let partitionKeys = store.knownPartitionsByTopic[topic] ?? []
                    if !partitionKeys.isEmpty {
                        PartitionSubChart(
                            store: store,
                            l10n: l10n,
                            renderingMode: renderingMode,
                            topic: topic,
                            partitionKeys: partitionKeys,
                        )
                    }
                }

                if activeTopics.isEmpty {
                    Text(l10n["trends.partition.lag.select"])
                        .foregroundStyle(.secondary)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Isolated sub-chart for a single topic's partition lag.
/// Each instance owns its own `@State hoverLocation`, so hovering on one
/// topic's chart does not invalidate other topics' charts.
private struct PartitionSubChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    let topic: String
    let partitionKeys: [String]
    @State private var hoverLocation: CGPoint?

    private var labels: [String] {
        partitionKeys.map { "P" + ($0.split(separator: ":").last.map(String.init) ?? $0) }
    }

    @ViewBuilder
    private func partitionTooltip(_ date: Date) -> some View {
        let items: [(key: String, label: String, point: LagPoint)] = partitionKeys.compactMap { key in
            let series = renderingMode.filterData(store.partitionLagSeries(for: key), by: \.timestamp)
            guard let point = nearest(series, to: date, by: \.timestamp) else { return nil }
            let label = "P" + (key.split(separator: ":").last.map(String.init) ?? key)
            return (key: key, label: label, point: point)
        }
        .sorted { $0.point.totalLag > $1.point.totalLag }
        if let first = items.first {
            ChartTooltip(date: first.point.timestamp) {
                ForEach(items, id: \.key) { item in
                    let colorIndex = partitionKeys.firstIndex(of: item.key) ?? 0
                    HStack(spacing: 4) {
                        Circle().fill(seriesColors[colorIndex % seriesColors.count]).frame(width: 8, height: 8)
                        Text("\(item.label): \(item.point.totalLag)")
                            .font(.caption2)
                    }
                }
            }
        }
    }

    var body: some View {
        let labels = labels
        let colorRange = Array(seriesColors.prefix(max(labels.count, 1)))

        VStack(alignment: .leading, spacing: 4) {
            Text(topic)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            let chart = Chart {
                ForEach(partitionKeys.indices, id: \.self) { idx in
                    let key = partitionKeys[idx]
                    let label = labels[idx]
                    let series = renderingMode.filterData(
                        store.partitionLagSeries(for: key), by: \.timestamp,
                    )
                    ForEach(series) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Lag", point.totalLag),
                            series: .value("Series", "\(label)-\(point.segment)"),
                        )
                        .foregroundStyle(by: .value("Partition", label))
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
            .chartForegroundStyleScale(domain: labels, range: colorRange)
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 200)

            switch renderingMode {
            case let .live(timeDomain):
                chart.chartXScale(domain: timeDomain)
                    .drawingGroup()
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        partitionTooltip(date)
                    }
            case let .history(visibleSeconds):
                chart.chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleSeconds)
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        partitionTooltip(date)
                    }
            }
        }
    }
}

// MARK: - ISR Health

struct ISRHealthChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @State private var hoverLocation: CGPoint?

    var body: some View {
        let data = renderingMode.filterData(store.isrHealthSeries, by: \.timestamp)

        TrendCard(title: l10n["trends.isr.health"]) {
            let chart = Chart {
                ForEach(data) { point in
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

            switch renderingMode {
            case let .live(timeDomain):
                chart.chartXScale(domain: timeDomain)
                    .drawingGroup()
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        if let p = nearest(data, to: date, by: \.timestamp) {
                            ChartTooltip(date: p.timestamp) {
                                HStack(spacing: 4) {
                                    Circle().fill(.green).frame(width: 8, height: 8)
                                    Text(String(format: "%.1f%%", p.healthyRatio * 100))
                                        .font(.caption2).bold()
                                }
                            }
                        }
                    }
            case let .history(visibleSeconds):
                chart
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleSeconds)
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        if let p = nearest(data, to: date, by: \.timestamp) {
                            ChartTooltip(date: p.timestamp) {
                                HStack(spacing: 4) {
                                    Circle().fill(.green).frame(width: 8, height: 8)
                                    Text(String(format: "%.1f%%", p.healthyRatio * 100))
                                        .font(.caption2).bold()
                                }
                            }
                        }
                    }
            }
        }
    }
}
