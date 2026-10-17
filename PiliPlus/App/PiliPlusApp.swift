import SwiftUI

@main
struct PiliPlusApp: App {
    @State private var model = AppModel()

    init() {
        setbuf(stdout, nil)
        LaunchClock.markMain()
        if LaunchMode.screen != nil {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environment(model)
                .preferredColorScheme(model.colorScheme)
                .tint(Palette.bili)
                .background(FirstFrameProbe().frame(width: 0, height: 0).allowsHitTesting(false))
        }
    }
}
