//
//  VotingModels.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 26/12/2025.
//

import Foundation
import CoreLocation

struct VotingOpenDataResponse: Codable {
    let total_count: Int
    let results: [VotingOpenDataRow]
}

struct VotingOpenDataRow: Codable, Identifiable {
    let gml_id: String
    let nom: String?
    let bureau: String?

    // ⚠️ Dans ton JSON tu as "adresse".
    // Tu m’as dit qu’il y a aussi une colonne "adresse du lieu de vote".
    // Sur l’API, elle peut être exposée sous un nom type "adresse_du_lieu_de_vote".
    let adresse: String?
    let adresse_du_lieu_de_vote: String?

    var id: String { gml_id }

    /// Adresse à utiliser pour géocoder le LIEU (et non le bureau)
    var lieuAddress: String? {
        let a = (adresse_du_lieu_de_vote ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        let b = (adresse ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? nil : b
    }
}

struct VotingSite: Identifiable, Hashable {
    let id: String              // "vote:<normalizedAddress>"
    let title: String           // nom du lieu
    let subtitle: String        // adresse + bureaux
    let coordinate: CLLocationCoordinate2D
    let bureauList: [String]

    static func == (lhs: VotingSite, rhs: VotingSite) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
