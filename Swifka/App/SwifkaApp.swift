import SwiftUI

@main
struct SwifkaApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(
                    minWidth: Constants.minWindowWidth,
                    minHeight: Constants.minWindowHeight,
                )
        }
        .defaultSize(
            width: Constants.defaultWindowWidth,
            height: Constants.defaultWindowHeight,
        )
        .windowToolbarStyle(.unified)
    }
}
