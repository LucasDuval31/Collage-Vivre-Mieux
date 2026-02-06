import SwiftUI
import SwiftData

@main
struct Collage_Vivre_MieuxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [PanelLocalStatus.self])
    }
}
