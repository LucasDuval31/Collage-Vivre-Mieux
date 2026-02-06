import Foundation
import SwiftData
import CoreLocation

struct OpenDataResponse: Codable {
    let total_count: Int
    let results: [OpenDataPanel]
}

struct OpenDataPanel: Codable, Identifiable, Hashable {
    let gml_id: String
    let adresse_localisation: String?
    let complement_adresse: String?
    let ville: String?
    let geo_point_2d: GeoPoint?

    struct GeoPoint: Codable, Hashable {
        let lon: Double
        let lat: Double
    }

    var id: String { gml_id }

    var coordinate: CLLocationCoordinate2D? {
        guard let p = geo_point_2d else { return nil }
        return .init(latitude: p.lat, longitude: p.lon)
    }

    var title: String {
        let a = (adresse_localisation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return a.isEmpty ? "Panneau" : a
    }

    var subtitle: String {
        [complement_adresse, ville]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
    
    var asPanelItem: PanelItem? {
        guard let c = coordinate else { return nil }
        return PanelItem(
            id: id,                      // gml_id
            title: title,
            subtitle: subtitle,
            coordinate: c,
            isExtra: false
        )
    }
}

struct ExtraPanel: Codable, Identifiable, Hashable {
    let id: UUID
    let lat: Double
    let lon: Double
    let title: String?
    let subtitle: String?
    let created_by: String?
    let created_at: Date?

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: lat, longitude: lon)
    }

    var displayTitle: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Panneau (ajout équipe)" : t
    }

    var displaySubtitle: String {
        (subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var panelId: String { "extra:\(id.uuidString)" }
    
    var asPanelItem: PanelItem {
        PanelItem(
            id: panelId,
            title: displayTitle,
            subtitle: displaySubtitle,
            coordinate: coordinate,
            isExtra: true
        )
    }
}

@Model
final class PanelLocalStatus {
    @Attribute(.unique) var panelId: String

    // Covered
    var lastCoveredAt: Date?
    var lastCoveredBy: String?
    var note: String?
    var photoFilename: String?

    // Absent
    var isAbsent: Bool = false
    var absentAt: Date?
    var absentBy: String?
    var absentReason: String?

    // Sync
    var needsSync: Bool = false
    var lastSyncedAt: Date?
    
    // ✅ Coordination / Responsabilité
    var assignedTo: String? // Nom de l'utilisateur responsable
    var assignedAt: Date?   // Date d'assignation
    
    // ✅ Recouvert par les adversaires
    var isOverposted: Bool = false
    var overpostedAt: Date?
    var overpostedBy: String?
    var overpostedNote: String?

    init(panelId: String) {
        self.panelId = panelId
        self.isAbsent = false
        self.needsSync = false
        self.isOverposted = false
    }
}

struct CoverEvent: Codable, Identifiable {
    let id: UUID
    let panel_id: String
    let covered_at: Date
    let covered_by: String
    let note: String?
    let photo_filename: String?

    let event_type: String?
    let absent_reason: String?
    
    var assigned_to: String?
    var assigned_at: Date?

    init(
        id: String,
        panelId: String,
        coveredAt: Date,
        coveredBy: String,
        note: String?,
        photoFilename: String?,
        eventType: String? = "covered",
        absentReason: String? = nil
    ) {
        self.id = UUID(uuidString: id) ?? UUID()
        self.panel_id = panelId
        self.covered_at = coveredAt
        self.covered_by = coveredBy
        self.note = note
        self.photo_filename = photoFilename
        self.event_type = eventType
        self.absent_reason = absentReason
    }
}
