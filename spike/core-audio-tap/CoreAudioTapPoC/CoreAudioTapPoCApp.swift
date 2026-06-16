import SwiftUI

@main
struct CoreAudioTapPoCApp: App {
    var body: some Scene {
        MenuBarExtra("Hazakura Boost", systemImage: "speaker.wave.2.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
