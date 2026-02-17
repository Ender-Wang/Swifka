import Charts
import SwiftUI

// MARK: - Chart Reveal Animation

private struct ChartRevealModifier: ViewModifier {
    let trigger: Int
    let delay: Double

    @State private var progress: CGFloat = 0
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .chartPlotStyle { plotArea in
                plotArea.mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: progress >= 1 ? nil : geo.size.width * progress)
                    }
                }
            }
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                animateReveal()
            }
            .onChange(of: trigger) {
                animateReveal()
            }
    }

    private func animateReveal() {
        progress = 0
        let start = CACurrentMediaTime()
        let animDelay = delay
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            let elapsed = CACurrentMediaTime() - start
            guard elapsed >= animDelay else { return }
            let t = min((elapsed - animDelay) / 0.6, 1.0)
            progress = t // linear
            if t >= 1 { timer.invalidate() }
        }
    }
}

extension View {
    func chartReveal(trigger: Int, delay: Double = 0) -> some View {
        modifier(ChartRevealModifier(trigger: trigger, delay: delay))
    }
}

// MARK: - Per-Series Reveal Animation

@Observable
private final class SeriesRevealState {
    var progress: [String: CGFloat] = [:]
    var fadeOpacity: [String: CGFloat] = [:]
    @ObservationIgnored private var timers: [String: Timer] = [:]
    @ObservationIgnored private var fadeTimers: [String: Timer] = [:]
    @ObservationIgnored private var generation = 0

    func ensureRevealed(_ keys: [String]) {
        let gen = generation
        for key in keys where progress[key] == nil {
            // Cancel any ongoing fade-out for this key (re-added)
            fadeTimers[key]?.invalidate()
            fadeTimers.removeValue(forKey: key)
            fadeOpacity.removeValue(forKey: key)

            progress[key] = 0
            let start = CACurrentMediaTime()
            timers[key] = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { timer.invalidate(); return }
                    guard self.generation == gen else { timer.invalidate(); return }
                    let t = min((CACurrentMediaTime() - start) / 0.6, 1.0)
                    self.progress[key] = CGFloat(t)
                    if t >= 1 {
                        timer.invalidate()
                        self.timers.removeValue(forKey: key)
                    }
                }
            }
        }
    }

    func reset() {
        generation += 1
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
        for timer in fadeTimers.values {
            timer.invalidate()
        }
        fadeTimers.removeAll()
        progress.removeAll()
        fadeOpacity.removeAll()
    }

    func clip<T>(_ data: [T], for key: String) -> [T] {
        guard let p = progress[key] else { return [] }
        guard p < 1, !data.isEmpty else { return data }
        return Array(data.prefix(max(1, Int(ceil(Double(data.count) * Double(p))))))
    }

    /// Returns selected series + any actively fading series.
    /// Automatically starts fade-out for series removed from selection.
    func displayedSeries(selected: [String]) -> [String] {
        let selectedSet = Set(selected)
        // Auto-start fade for series no longer selected
        for key in progress.keys where !selectedSet.contains(key) && fadeOpacity[key] == nil {
            timers[key]?.invalidate()
            timers.removeValue(forKey: key)
            progress[key] = 1.0
            startFadeOut(key)
        }
        var result = selected
        for key in fadeOpacity.keys where !selectedSet.contains(key) {
            result.append(key)
        }
        return result
    }

    /// Per-series fade opacity (1.0 for normal, fading to 0 on removal).
    func opacity(for key: String) -> Double {
        guard progress[key] != nil else { return 0 }
        return Double(fadeOpacity[key] ?? 1.0)
    }

    private func startFadeOut(_ key: String) {
        fadeTimers[key]?.invalidate()
        fadeOpacity[key] = 1.0
        let start = CACurrentMediaTime()
        fadeTimers[key] = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min((CACurrentMediaTime() - start) / 0.3, 1.0)
                self.fadeOpacity[key] = 1.0 - CGFloat(t)
                if t >= 1 {
                    timer.invalidate()
                    self.fadeTimers.removeValue(forKey: key)
                    self.fadeOpacity.removeValue(forKey: key)
                    self.progress.removeValue(forKey: key)
                }
            }
        }
    }
}

// MARK: - Shared Card Wrapper

struct TrendCard<Content: View> {
    let title: String
    let onExport: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(title: String, onExport: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.onExport = onExport
        self.content = content
    }
}

extension TrendCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                Spacer()
                if let onExport {
                    ExportButton(action: onExport)
                }
            }
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

// MARK: - Export Button

private struct ExportButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @Environment(AppState.self) private var appState

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(4)
                .background(
                    isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 4),
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(appState.l10n["common.export.xlsx"])
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
    let clusterName: String
    let database: MetricDatabase?
    let clusterId: UUID?
    let historyRange: (from: Date, to: Date)?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        let data = renderingMode.filterData(store.clusterThroughput, by: \.timestamp)

        TrendCard(
            title: "\(l10n["trends.cluster.throughput"]) (\(l10n["trends.messages.per.second"]))",
            onExport: {
                Task {
                    let exportData: [ThroughputPoint]
                    if case .history = renderingMode, let db = database, let cid = clusterId, let range = historyRange {
                        let raw = try await db.loadSnapshots(clusterId: cid, from: range.from, to: range.to)
                        let temp = MetricStore(capacity: .max)
                        temp.loadHistorical(raw)
                        exportData = temp.clusterThroughput
                    } else {
                        exportData = store.clusterThroughput
                    }
                    let fmt = ChartExporter.iso8601Formatter()
                    let sorted = exportData.sorted { $0.timestamp < $1.timestamp }
                    let sheets = [XLSXWriter.Sheet(
                        name: "ClusterThroughput",
                        headers: ["Timestamp", "MessagesPerSecond"],
                        rows: sorted.map { [fmt.string(from: $0.timestamp), String(format: "%.2f", $0.messagesPerSecond)] },
                    )]
                    let xlsxData = XLSXWriter.build(sheets: sheets)
                    let filename = ChartExporter.xlsxFilename(clusterName: clusterName, chartType: .clusterThroughput, dataPoints: exportData.map(\.timestamp))
                    ChartExporter.saveXLSX(data: xlsxData, defaultFilename: filename)
                }
            },
        ) {
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
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v, format: .number.notation(.compactName))
                        }
                    }
                    AxisGridLine()
                }
            }
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
                    .chartReveal(trigger: store.dataEpoch)
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
                    .chartReveal(trigger: store.dataEpoch)
            }
        }
    }
}

// MARK: - Ping Latency

struct PingLatencyChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    let clusterName: String
    let database: MetricDatabase?
    let clusterId: UUID?
    let historyRange: (from: Date, to: Date)?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        let data = renderingMode.filterData(store.pingHistory, by: \.timestamp)

        TrendCard(
            title: "\(l10n["trends.ping.latency"]) (ms)",
            onExport: {
                Task {
                    let exportData: [PingPoint]
                    if case .history = renderingMode, let db = database, let cid = clusterId, let range = historyRange {
                        let raw = try await db.loadSnapshots(clusterId: cid, from: range.from, to: range.to)
                        let temp = MetricStore(capacity: .max)
                        temp.loadHistorical(raw)
                        exportData = temp.pingHistory
                    } else {
                        exportData = store.pingHistory
                    }
                    let fmt = ChartExporter.iso8601Formatter()
                    let sorted = exportData.sorted { $0.timestamp < $1.timestamp }
                    let sheets = [XLSXWriter.Sheet(
                        name: "PingLatency",
                        headers: ["Timestamp", "Milliseconds"],
                        rows: sorted.map { [fmt.string(from: $0.timestamp), "\($0.ms)"] },
                    )]
                    let xlsxData = XLSXWriter.build(sheets: sheets)
                    let filename = ChartExporter.xlsxFilename(clusterName: clusterName, chartType: .pingLatency, dataPoints: exportData.map(\.timestamp))
                    ChartExporter.saveXLSX(data: xlsxData, defaultFilename: filename)
                }
            },
        ) {
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
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v, format: .number.notation(.compactName))
                        }
                    }
                    AxisGridLine()
                }
            }
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
                    .chartReveal(trigger: store.dataEpoch)
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
                    .chartReveal(trigger: store.dataEpoch)
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
    let clusterName: String
    let database: MetricDatabase?
    let clusterId: UUID?
    let historyRange: (from: Date, to: Date)?
    @State private var hoverLocation: CGPoint?
    @State private var reveal = SeriesRevealState()

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

        TrendCard(
            title: "\(l10n["trends.topic.throughput"]) (\(l10n["trends.messages.per.second"]))",
            onExport: {
                let topics = selectedTopics
                Task {
                    let sourceStore: MetricStore
                    if case .history = renderingMode, let db = database, let cid = clusterId, let range = historyRange {
                        let raw = try await db.loadSnapshots(clusterId: cid, from: range.from, to: range.to)
                        let temp = MetricStore(capacity: .max)
                        temp.loadHistorical(raw)
                        sourceStore = temp
                    } else {
                        sourceStore = store
                    }
                    let fmt = ChartExporter.iso8601Formatter()
                    var allDates: [Date] = []
                    let sheets: [XLSXWriter.Sheet] = topics.map { topic in
                        let series = sourceStore.throughputSeries(for: topic)
                            .sorted { $0.timestamp < $1.timestamp }
                        allDates.append(contentsOf: series.map(\.timestamp))
                        return XLSXWriter.Sheet(
                            name: topic,
                            headers: ["Timestamp", "MessagesPerSecond"],
                            rows: series.map { [fmt.string(from: $0.timestamp), String(format: "%.2f", $0.messagesPerSecond)] },
                        )
                    }
                    let xlsxData = XLSXWriter.build(sheets: sheets)
                    let filename = ChartExporter.xlsxFilename(clusterName: clusterName, chartType: .topicThroughput, dataPoints: allDates)
                    ChartExporter.saveXLSX(data: xlsxData, defaultFilename: filename)
                }
            },
        ) {
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

            let displayed = reveal.displayedSeries(selected: selectedTopics)
            let chart = Chart {
                ForEach(displayed, id: \.self) { topic in
                    let series = reveal.clip(
                        renderingMode.filterData(
                            store.throughputSeries(for: topic), by: \.timestamp,
                        ),
                        for: topic,
                    )
                    ForEach(series) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("msg/s", logScale ? max(0.1, point.messagesPerSecond) : point.messagesPerSecond),
                            series: .value("Series", "\(topic)-\(point.segment)"),
                        )
                        .foregroundStyle(by: .value("Topic", topic))
                        .interpolationMethod(.catmullRom)
                        .opacity(reveal.opacity(for: topic))
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v, format: .number.notation(.compactName))
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                    AxisGridLine()
                }
            }
            .chartForegroundStyleScale(domain: displayed, range: Array(seriesColors.prefix(max(displayed.count, 1))))
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 250)
            .onAppear { reveal.ensureRevealed(selectedTopics) }
            .onChange(of: selectedTopics) { _, newValue in
                reveal.ensureRevealed(newValue)
            }
            .onChange(of: store.dataEpoch) {
                reveal.reset()
                reveal.ensureRevealed(selectedTopics)
            }

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
    let clusterName: String
    let database: MetricDatabase?
    let clusterId: UUID?
    let historyRange: (from: Date, to: Date)?
    @State private var hoverLocation: CGPoint?
    @State private var reveal = SeriesRevealState()

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

        TrendCard(
            title: "\(l10n["trends.consumer.lag"]) (\(l10n["trends.lag.messages"]))",
            onExport: {
                let groups = selectedGroups
                Task {
                    let sourceStore: MetricStore
                    if case .history = renderingMode, let db = database, let cid = clusterId, let range = historyRange {
                        let raw = try await db.loadSnapshots(clusterId: cid, from: range.from, to: range.to)
                        let temp = MetricStore(capacity: .max)
                        temp.loadHistorical(raw)
                        sourceStore = temp
                    } else {
                        sourceStore = store
                    }
                    let fmt = ChartExporter.iso8601Formatter()
                    var allDates: [Date] = []
                    let sheets: [XLSXWriter.Sheet] = groups.map { group in
                        let series = sourceStore.lagSeries(for: group)
                            .sorted { $0.timestamp < $1.timestamp }
                        allDates.append(contentsOf: series.map(\.timestamp))
                        return XLSXWriter.Sheet(
                            name: group,
                            headers: ["Timestamp", "Lag"],
                            rows: series.map { [fmt.string(from: $0.timestamp), "\($0.totalLag)"] },
                        )
                    }
                    let xlsxData = XLSXWriter.build(sheets: sheets)
                    let filename = ChartExporter.xlsxFilename(clusterName: clusterName, chartType: .consumerGroupLag, dataPoints: allDates)
                    ChartExporter.saveXLSX(data: xlsxData, defaultFilename: filename)
                }
            },
        ) {
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

                let displayed = reveal.displayedSeries(selected: selectedGroups)
                let chart = Chart {
                    ForEach(displayed, id: \.self) { group in
                        let series = reveal.clip(
                            renderingMode.filterData(
                                store.lagSeries(for: group), by: \.timestamp,
                            ),
                            for: group,
                        )
                        ForEach(series) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Lag", logScale ? max(1, point.totalLag) : point.totalLag),
                                series: .value("Series", "\(group)-\(point.segment)"),
                            )
                            .foregroundStyle(by: .value("Group", group))
                            .interpolationMethod(.catmullRom)
                            .opacity(reveal.opacity(for: group))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(v, format: .number.notation(.compactName))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                        AxisGridLine()
                    }
                }
                .chartForegroundStyleScale(domain: displayed, range: Array(seriesColors.prefix(max(displayed.count, 1))))
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 250)
                .onAppear { reveal.ensureRevealed(selectedGroups) }
                .onChange(of: selectedGroups) { _, newValue in
                    reveal.ensureRevealed(newValue)
                }
                .onChange(of: store.dataEpoch) {
                    reveal.reset()
                    reveal.ensureRevealed(selectedGroups)
                }

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
    let clusterName: String
    let database: MetricDatabase?
    let clusterId: UUID?
    let historyRange: (from: Date, to: Date)?
    @State private var hoverLocation: CGPoint?
    @State private var reveal = SeriesRevealState()

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

        TrendCard(
            title: "\(l10n["trends.topic.lag"]) (\(l10n["trends.lag.messages"]))",
            onExport: {
                let topics = selectedTopics.filter { lagTopics.contains($0) }
                Task {
                    let sourceStore: MetricStore
                    if case .history = renderingMode, let db = database, let cid = clusterId, let range = historyRange {
                        let raw = try await db.loadSnapshots(clusterId: cid, from: range.from, to: range.to)
                        let temp = MetricStore(capacity: .max)
                        temp.loadHistorical(raw)
                        sourceStore = temp
                    } else {
                        sourceStore = store
                    }
                    let fmt = ChartExporter.iso8601Formatter()
                    var allDates: [Date] = []
                    let sheets: [XLSXWriter.Sheet] = topics.map { topic in
                        let series = sourceStore.topicLagSeries(for: topic)
                            .sorted { $0.timestamp < $1.timestamp }
                        allDates.append(contentsOf: series.map(\.timestamp))
                        return XLSXWriter.Sheet(
                            name: topic,
                            headers: ["Timestamp", "Lag"],
                            rows: series.map { [fmt.string(from: $0.timestamp), "\($0.totalLag)"] },
                        )
                    }
                    let xlsxData = XLSXWriter.build(sheets: sheets)
                    let filename = ChartExporter.xlsxFilename(clusterName: clusterName, chartType: .topicLag, dataPoints: allDates)
                    ChartExporter.saveXLSX(data: xlsxData, defaultFilename: filename)
                }
            },
        ) {
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
                let displayed = reveal.displayedSeries(selected: activeSeries)

                let chart = Chart {
                    ForEach(displayed, id: \.self) { topic in
                        let series = reveal.clip(
                            renderingMode.filterData(
                                store.topicLagSeries(for: topic), by: \.timestamp,
                            ),
                            for: topic,
                        )
                        ForEach(series) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Lag", logScale ? max(1, point.totalLag) : point.totalLag),
                                series: .value("Series", "\(topic)-\(point.segment)"),
                            )
                            .foregroundStyle(by: .value("Topic", topic))
                            .interpolationMethod(.catmullRom)
                            .opacity(reveal.opacity(for: topic))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(v, format: .number.notation(.compactName))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                        AxisGridLine()
                    }
                }
                .chartForegroundStyleScale(domain: displayed, range: Array(seriesColors.prefix(max(displayed.count, 1))))
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 250)
                .onAppear { reveal.ensureRevealed(activeSeries) }
                .onChange(of: selectedTopics) { _, newValue in
                    let newActive = newValue.filter { lagTopics.contains($0) }
                    reveal.ensureRevealed(newActive)
                }
                .onChange(of: store.dataEpoch) {
                    reveal.reset()
                    reveal.ensureRevealed(activeSeries)
                }

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

// MARK: - Partition Owner

/// Lightweight owner info for partition chart labels.
struct PartitionOwner {
    let clientId: String
    let memberId: String
}

// MARK: - Per-Partition Lag

struct PartitionLagChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @Binding var selectedTopics: [String]
    let partitionOwnerMap: [String: PartitionOwner]
    let clusterName: String
    let database: MetricDatabase?
    let clusterId: UUID?
    let historyRange: (from: Date, to: Date)?

    var body: some View {
        let lagTopics = Array(store.knownPartitionsByTopic.keys).sorted().filter { !$0.hasPrefix("__") }

        TrendCard(
            title: "\(l10n["trends.partition.lag"]) (\(l10n["trends.lag.messages"]))",
            onExport: {
                let topics = selectedTopics.filter { lagTopics.contains($0) }
                Task {
                    let sourceStore: MetricStore
                    if case .history = renderingMode, let db = database, let cid = clusterId, let range = historyRange {
                        let raw = try await db.loadSnapshots(clusterId: cid, from: range.from, to: range.to)
                        let temp = MetricStore(capacity: .max)
                        temp.loadHistorical(raw)
                        sourceStore = temp
                    } else {
                        sourceStore = store
                    }
                    let fmt = ChartExporter.iso8601Formatter()
                    var allDates: [Date] = []
                    let sheets: [XLSXWriter.Sheet] = topics.flatMap { topic -> [XLSXWriter.Sheet] in
                        let partitionKeys = sourceStore.knownPartitionsByTopic[topic] ?? []
                        return partitionKeys.map { key in
                            let series = sourceStore.partitionLagSeries(for: key)
                                .sorted { $0.timestamp < $1.timestamp }
                            allDates.append(contentsOf: series.map(\.timestamp))
                            let pNum = key.split(separator: ":").last.map(String.init) ?? "?"
                            return XLSXWriter.Sheet(
                                name: "\(topic) P\(pNum)",
                                headers: ["Timestamp", "Lag"],
                                rows: series.map { [fmt.string(from: $0.timestamp), "\($0.totalLag)"] },
                            )
                        }
                    }
                    let xlsxData = XLSXWriter.build(sheets: sheets)
                    let filename = ChartExporter.xlsxFilename(clusterName: clusterName, chartType: .partitionLag, dataPoints: allDates)
                    ChartExporter.saveXLSX(data: xlsxData, defaultFilename: filename)
                }
            },
        ) {
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
                ForEach(Array(activeTopics.enumerated()), id: \.element) { index, topic in
                    let partitionKeys = store.knownPartitionsByTopic[topic] ?? []
                    if !partitionKeys.isEmpty {
                        PartitionSubChart(
                            store: store,
                            l10n: l10n,
                            renderingMode: renderingMode,
                            topic: topic,
                            partitionKeys: partitionKeys,
                            partitionOwnerMap: partitionOwnerMap,
                            revealDelay: Double(index) * 0.08,
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
    let partitionOwnerMap: [String: PartitionOwner]
    let revealDelay: Double
    @State private var hoverLocation: CGPoint?

    /// Legend label: "P0 · clientId · ...last8" when owned, "P0 (no consumer)" when unowned.
    private var labels: [String] {
        partitionKeys.map { key in
            let pNum = "P" + (key.split(separator: ":").last.map(String.init) ?? key)
            guard let owner = partitionOwnerMap[key] else {
                return "\(pNum) (no consumer)"
            }
            let idSuffix = owner.memberId.count > 8
                ? "...\(owner.memberId.suffix(8))"
                : owner.memberId
            return "\(pNum) · \(owner.clientId) · \(idSuffix)"
        }
    }

    @ViewBuilder
    private func partitionTooltip(_ date: Date) -> some View {
        let items: [(key: String, label: String, owner: PartitionOwner?, point: LagPoint)] = partitionKeys.compactMap { key in
            let series = renderingMode.filterData(store.partitionLagSeries(for: key), by: \.timestamp)
            guard let point = nearest(series, to: date, by: \.timestamp) else { return nil }
            let pNum = "P" + (key.split(separator: ":").last.map(String.init) ?? key)
            return (key: key, label: pNum, owner: partitionOwnerMap[key], point: point)
        }
        .sorted { $0.point.totalLag > $1.point.totalLag }
        if let first = items.first {
            ChartTooltip(date: first.point.timestamp) {
                ForEach(items, id: \.key) { item in
                    let colorIndex = partitionKeys.firstIndex(of: item.key) ?? 0
                    HStack(spacing: 4) {
                        Circle().fill(seriesColors[colorIndex % seriesColors.count]).frame(width: 8, height: 8)
                        if let owner = item.owner {
                            Text("\(item.label) (\(owner.clientId) · \(owner.memberId)): \(item.point.totalLag)")
                                .font(.caption2)
                        } else {
                            Text("\(item.label) (no consumer): \(item.point.totalLag)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
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
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v, format: .number.notation(.compactName))
                        }
                    }
                    AxisGridLine()
                }
            }
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
                    .chartReveal(trigger: store.dataEpoch, delay: revealDelay)
            case let .history(visibleSeconds):
                chart.chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleSeconds)
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        partitionTooltip(date)
                    }
                    .chartReveal(trigger: store.dataEpoch, delay: revealDelay)
            }
        }
    }
}

// MARK: - Per-Consumer Member Lag

struct ConsumerMemberLagChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    @Binding var selectedGroups: [String]
    let consumerGroups: [ConsumerGroupInfo]
    let clusterName: String
    let database: MetricDatabase?
    let clusterId: UUID?
    let historyRange: (from: Date, to: Date)?

    var body: some View {
        // Use store.knownGroups for stable chip list (not consumerGroups which updates every refresh)
        let groupNames = store.knownGroups

        TrendCard(
            title: "\(l10n["trends.consumer.member.lag"]) (\(l10n["trends.lag.messages"]))",
            onExport: {
                let activeGroups = selectedGroups.compactMap { name in
                    consumerGroups.first { $0.name == name }
                }
                Task {
                    let sourceStore: MetricStore
                    if case .history = renderingMode, let db = database, let cid = clusterId, let range = historyRange {
                        let raw = try await db.loadSnapshots(clusterId: cid, from: range.from, to: range.to)
                        let temp = MetricStore(capacity: .max)
                        temp.loadHistorical(raw)
                        sourceStore = temp
                    } else {
                        sourceStore = store
                    }
                    let fmt = ChartExporter.iso8601Formatter()
                    var allDates: [Date] = []
                    let sheets: [XLSXWriter.Sheet] = activeGroups.flatMap { group -> [XLSXWriter.Sheet] in
                        aggregateMemberLag(group: group, store: sourceStore).map { member in
                            let sorted = member.series.sorted { $0.timestamp < $1.timestamp }
                            allDates.append(contentsOf: sorted.map(\.timestamp))
                            return XLSXWriter.Sheet(
                                name: "\(group.name) - \(member.clientId)",
                                headers: ["Timestamp", "Lag"],
                                rows: sorted.map { [fmt.string(from: $0.timestamp), "\($0.totalLag)"] },
                            )
                        }
                    }
                    let xlsxData = XLSXWriter.build(sheets: sheets)
                    let filename = ChartExporter.xlsxFilename(clusterName: clusterName, chartType: .consumerMemberLag, dataPoints: allDates)
                    ChartExporter.saveXLSX(data: xlsxData, defaultFilename: filename)
                }
            },
        ) {
            if groupNames.isEmpty {
                ContentUnavailableView {
                    Label(l10n["trends.consumer.member.lag"], systemImage: "person.2")
                } description: {
                    Text(l10n["trends.not.enough.data.description"])
                }
                .frame(height: 200)
            } else {
                let allSelected = groupNames.allSatisfy { selectedGroups.contains($0) }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(groupNames, id: \.self) { group in
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
                            if allSelected {
                                selectedGroups.removeAll { groupNames.contains($0) }
                            } else {
                                for group in groupNames where !selectedGroups.contains(group) {
                                    selectedGroups.append(group)
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

                // Resolve live member data only for selected groups
                let activeGroups = selectedGroups.compactMap { name in
                    consumerGroups.first { $0.name == name }
                }

                ForEach(Array(activeGroups.enumerated()), id: \.element.id) { index, group in
                    if !group.members.isEmpty {
                        MemberSubChart(
                            store: store,
                            l10n: l10n,
                            renderingMode: renderingMode,
                            group: group,
                            revealDelay: Double(index) * 0.08,
                        )
                    }
                }

                if activeGroups.isEmpty {
                    Text(l10n["trends.consumer.member.lag.select"])
                        .foregroundStyle(.secondary)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Member Lag Aggregation

/// Aggregate partition lag into per-member time series for a consumer group.
/// Shared between `MemberSubChart` (rendering) and `ConsumerMemberLagChart` (CSV export).
func aggregateMemberLag(
    group: ConsumerGroupInfo,
    store: MetricStore,
) -> [(clientId: String, memberId: String, series: [LagPoint])] {
    group.members.map { member in
        var keys: [String] = []
        for assignment in member.assignments {
            for partition in assignment.partitions {
                keys.append("\(assignment.topic):\(partition)")
            }
        }
        keys.sort()

        var timestampMap: [Date: (total: Int64, segment: Int)] = [:]
        for key in keys {
            for point in store.partitionLagSeries(for: key) {
                if let existing = timestampMap[point.timestamp] {
                    timestampMap[point.timestamp] = (existing.total + point.totalLag, point.segment)
                } else {
                    timestampMap[point.timestamp] = (point.totalLag, point.segment)
                }
            }
        }

        let points = timestampMap.map { ($0.key, $0.value.total, $0.value.segment) }
            .sorted { $0.0 < $1.0 }
            .map { ts, lag, seg in
                LagPoint(timestamp: ts, group: member.memberId, totalLag: lag, segment: seg)
            }

        return (clientId: member.clientId, memberId: member.memberId, series: points)
    }
}

/// Isolated sub-chart for a single consumer group's per-member lag.
/// Each instance owns its own `@State hoverLocation`, so hovering on one
/// group's chart does not invalidate other groups' charts.
private struct MemberSubChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    let group: ConsumerGroupInfo
    let revealDelay: Double
    @State private var hoverLocation: CGPoint?

    /// Partition keys per member, sorted.
    private var memberPartitionKeys: [(member: GroupMemberInfo, keys: [String])] {
        group.members.map { member in
            var keys: [String] = []
            for assignment in member.assignments {
                for partition in assignment.partitions {
                    keys.append("\(assignment.topic):\(partition)")
                }
            }
            keys.sort()
            return (member: member, keys: keys)
        }
    }

    /// Aggregate lag series per member, computed via shared helper.
    private var memberLagSeries: [(memberId: String, series: [LagPoint])] {
        aggregateMemberLag(group: group, store: store).map { (memberId: $0.memberId, series: $0.series) }
    }

    /// Build legend labels. If all clientIds are unique within the group, use clientId + partitions.
    /// Otherwise add memberId suffix for disambiguation.
    private var labels: [String] {
        let items = memberPartitionKeys
        let clientIdCounts = Dictionary(grouping: items.map(\.member.clientId), by: { $0 }).mapValues(\.count)
        let needsDisambiguation = clientIdCounts.values.contains { $0 > 1 }

        return items.map { item in
            let partitionDesc = compactPartitionLabel(item.keys)
            if needsDisambiguation {
                let idSuffix = item.member.memberId.count > 8
                    ? "...\(item.member.memberId.suffix(8))"
                    : item.member.memberId
                return "\(item.member.clientId) · \(idSuffix) · \(partitionDesc)"
            } else {
                return "\(item.member.clientId) · \(partitionDesc)"
            }
        }
    }

    /// Compact partition description: "orders:P0,P1 · payments:P0" or "P0,P1,P2" if single topic.
    private func compactPartitionLabel(_ keys: [String]) -> String {
        // Group by topic
        var byTopic: [String: [String]] = [:]
        for key in keys {
            if let colonIdx = key.lastIndex(of: ":") {
                let topic = String(key[key.startIndex ..< colonIdx])
                let pNum = "P" + String(key[key.index(after: colonIdx)...])
                byTopic[topic, default: []].append(pNum)
            }
        }

        if byTopic.count == 1, let (_, partitions) = byTopic.first {
            let list = partitions.joined(separator: ",")
            if partitions.count > 6 {
                return partitions.prefix(3).joined(separator: ",") + "…+\(partitions.count - 3)"
            }
            return list
        }

        // Multiple topics — show topic:partitions
        return byTopic.sorted(by: { $0.key < $1.key }).map { topic, partitions in
            let list = partitions.count > 4
                ? partitions.prefix(2).joined(separator: ",") + "…+\(partitions.count - 2)"
                : partitions.joined(separator: ",")
            return "\(topic):\(list)"
        }.joined(separator: " · ")
    }

    @ViewBuilder
    private func memberTooltip(_ date: Date) -> some View {
        let items = memberPartitionKeys
        let allSeries = memberLagSeries
        let clientIdCounts = Dictionary(grouping: items.map(\.member.clientId), by: { $0 }).mapValues(\.count)
        let needsDisambiguation = clientIdCounts.values.contains { $0 > 1 }
        let labels = labels

        let hoverItems: [(idx: Int, label: String, member: GroupMemberInfo, point: LagPoint)] = items.indices.compactMap { idx in
            let series = renderingMode.filterData(allSeries[idx].series, by: \.timestamp)
            guard let point = nearest(series, to: date, by: \.timestamp) else { return nil }
            return (idx: idx, label: labels[idx], member: items[idx].member, point: point)
        }
        .sorted { $0.point.totalLag > $1.point.totalLag }

        if let first = hoverItems.first {
            ChartTooltip(date: first.point.timestamp) {
                ForEach(hoverItems, id: \.idx) { item in
                    let colorIndex = item.idx
                    HStack(spacing: 4) {
                        Circle().fill(seriesColors[colorIndex % seriesColors.count]).frame(width: 8, height: 8)
                        if needsDisambiguation {
                            Text("\(item.member.clientId) · \(item.member.memberId): \(item.point.totalLag)")
                                .font(.caption2)
                        } else {
                            Text("\(item.member.clientId): \(item.point.totalLag)")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        let labels = labels
        let allSeries = memberLagSeries
        let colorRange = Array(seriesColors.prefix(max(labels.count, 1)))

        VStack(alignment: .leading, spacing: 4) {
            Text(group.name)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            let chart = Chart {
                ForEach(labels.indices, id: \.self) { idx in
                    let label = labels[idx]
                    let series = renderingMode.filterData(allSeries[idx].series, by: \.timestamp)
                    ForEach(series) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Lag", point.totalLag),
                            series: .value("Series", "\(label)-\(point.segment)"),
                        )
                        .foregroundStyle(by: .value("Member", label))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v, format: .number.notation(.compactName))
                        }
                    }
                    AxisGridLine()
                }
            }
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
                        memberTooltip(date)
                    }
                    .chartReveal(trigger: store.dataEpoch, delay: revealDelay)
            case let .history(visibleSeconds):
                chart.chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleSeconds)
                    .hoverOverlay(hoverLocation: $hoverLocation) { date in
                        memberTooltip(date)
                    }
                    .chartReveal(trigger: store.dataEpoch, delay: revealDelay)
            }
        }
    }
}

// MARK: - ISR Health

struct ISRHealthChart: View {
    let store: MetricStore
    let l10n: L10n
    let renderingMode: TrendRenderingMode
    let clusterName: String
    let database: MetricDatabase?
    let clusterId: UUID?
    let historyRange: (from: Date, to: Date)?
    @State private var hoverLocation: CGPoint?

    var body: some View {
        let data = renderingMode.filterData(store.isrHealthSeries, by: \.timestamp)

        TrendCard(
            title: "\(l10n["trends.isr.health"]) (%)",
            onExport: {
                Task {
                    let exportData: [ISRHealthPoint]
                    if case .history = renderingMode, let db = database, let cid = clusterId, let range = historyRange {
                        let raw = try await db.loadSnapshots(clusterId: cid, from: range.from, to: range.to)
                        let temp = MetricStore(capacity: .max)
                        temp.loadHistorical(raw)
                        exportData = temp.isrHealthSeries
                    } else {
                        exportData = store.isrHealthSeries
                    }
                    let fmt = ChartExporter.iso8601Formatter()
                    let sorted = exportData.sorted { $0.timestamp < $1.timestamp }
                    let sheets = [XLSXWriter.Sheet(
                        name: "ISRHealth",
                        headers: ["Timestamp", "HealthPercent"],
                        rows: sorted.map { [fmt.string(from: $0.timestamp), String(format: "%.2f", $0.healthyRatio * 100)] },
                    )]
                    let xlsxData = XLSXWriter.build(sheets: sheets)
                    let filename = ChartExporter.xlsxFilename(clusterName: clusterName, chartType: .isrHealth, dataPoints: exportData.map(\.timestamp))
                    ChartExporter.saveXLSX(data: xlsxData, defaultFilename: filename)
                }
            },
        ) {
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
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v, format: .number.notation(.compactName))
                        }
                    }
                    AxisGridLine()
                }
            }
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
                    .chartReveal(trigger: store.dataEpoch)
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
                    .chartReveal(trigger: store.dataEpoch)
            }
        }
    }
}
