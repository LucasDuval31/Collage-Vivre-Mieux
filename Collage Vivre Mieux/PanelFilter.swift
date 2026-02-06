import Foundation

enum PanelFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case todo = "À faire"
    case upToDate = "À jour (<24h)"
    case old = "À refaire"
    case absent = "Absents"
    case pending = "À sync"

    var id: String { rawValue }
}
