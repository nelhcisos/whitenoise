import SwiftUI

@main
struct LocketApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    init() {
        // Photos are immutable on the server, so cache them generously.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024, directory: nil)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, .ru)
                .preferredColorScheme(.dark)
                .tint(.locketYellow)
                .onOpenURL { model.open(url: $0) }
        }
    }
}
