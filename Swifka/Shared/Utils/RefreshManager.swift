import Foundation

@Observable
final class RefreshManager {
    var mode: RefreshMode = .manual
    var tick: UInt = 0
    @ObservationIgnored var onRefresh: (@MainActor () async -> Void)?

    private var timer: Timer?

    var isAutoRefresh: Bool {
        if case .interval = mode { return true }
        return false
    }

    func start() {
        stop()
        guard case let .interval(seconds) = mode else { return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick &+= 1
                await self.onRefresh?()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        await onRefresh?()
    }

    func restart() {
        guard isAutoRefresh else { return }
        start()
    }

    func updateMode(_ newMode: RefreshMode) {
        mode = newMode
        if isAutoRefresh {
            start()
        } else {
            stop()
        }
    }
}
