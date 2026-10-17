import SwiftUI

@main
struct PiliPlusApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environment(model)
                .preferredColorScheme(model.colorScheme)
                .tint(Palette.bili)
        }
    }
}
