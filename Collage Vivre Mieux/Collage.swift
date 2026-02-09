import SwiftUI
import SwiftData

@main
struct Collage_Vivre_MieuxApp: App {
    
    // Initialisation du container SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PanelLocalStatus.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Erreur lors de la création du ModelContainer : \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            // ✅ On passe le container ici au ContentView
            ContentView(modelContainer: sharedModelContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}