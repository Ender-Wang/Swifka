import SwiftUI

struct ConnectionStatusBadge: View {
    let status: ConnectionStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch status {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .gray
        case .error: .red
        }
    }
}
