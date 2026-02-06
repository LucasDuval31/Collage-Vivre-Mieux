//
//  PanelItem.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 26/12/2025.
//

import Foundation
import CoreLocation

struct PanelItem: Identifiable, Hashable {
    let id: String                 // gml_id ou "extra:UUID"
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let isExtra: Bool

    static func == (lhs: PanelItem, rhs: PanelItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
