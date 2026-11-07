import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup("MacVPN Tunnel") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
