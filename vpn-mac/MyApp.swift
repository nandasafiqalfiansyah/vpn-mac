import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup("MacVPN Tunnel") {
            ContentView()
        }
        .windowResizability(.contentSize)
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
