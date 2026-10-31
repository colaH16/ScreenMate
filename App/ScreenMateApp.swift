import SwiftUI

@main
struct ScreenMateApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ConnectionListView()
                .environment(model)
        }
    }
}
