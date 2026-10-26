import SwiftUI

@main
struct LumaApp: App {
    @StateObject private var lights = BLEController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lights)
                .preferredColorScheme(.dark)
        }
    }
}
