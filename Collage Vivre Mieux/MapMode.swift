//
//  MapMode.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 26/12/2025.
//

import Foundation

enum MapMode: String, CaseIterable, Identifiable {
    case free = "Expression libre"
    case vote = "Panneaux électoraux"

    var id: String { rawValue }
}
