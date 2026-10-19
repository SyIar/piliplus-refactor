import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == "com.syiar.piliplus.downloads" else { return }
        DownloadBridge.shared.backgroundCompletion = completionHandler
        _ = DownloadBridge.shared.ensureSession()
    }
}

@main
struct PiliPlusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        setbuf(stdout, nil)
        LaunchClock.markMain()
        if LaunchMode.screen != nil, LaunchMode.screen != "favsheet" {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environment(model)
                .preferredColorScheme(model.colorScheme)
                .tint(model.accentColor)
                .background(FirstFrameProbe().frame(width: 0, height: 0).allowsHitTesting(false))
        }
    }
}
