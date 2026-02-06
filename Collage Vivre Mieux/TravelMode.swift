//
//  TravelMode.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 22/12/2025.
//

import Foundation
import MapKit

enum TravelMode: String, CaseIterable, Identifiable {
    case driving = "Voiture"
    case walking = "À pied"
    case transit = "Transports"
    case cycling = "Vélo"

    var id: String { rawValue }

    var mkType: MKDirectionsTransportType {
        switch self {
        case .driving: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        case .cycling:
            if #available(iOS 14.0, *) { return .any } // Apple Maps gère vélo selon zones; on laisse any
            return .any
        }
    }
}
