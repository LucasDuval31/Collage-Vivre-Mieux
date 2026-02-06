//
//  AlertsView.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 22/12/2025.
//

import SwiftUI

struct AlertsView: View {
    let panels: [OpenDataPanel]
    let statusFor: (OpenDataPanel) -> PanelComputedStatus

    var body: some View {
        List {
            Section("À faire") {
                Text("Jamais recouverts: \(todoCount)")
                Text("À refaire (24h+): \(staleCount)")
            }

            Section("Recommandations") {
                if staleCount > 20 {
                    Text("⚠️ Beaucoup de panneaux à refaire : organise une tournée prioritaire.")
                } else {
                    Text("✅ Situation maîtrisée : continue la tournée régulière.")
                }
            }
        }
        .navigationTitle("Alertes")
    }

    private var todoCount: Int {
        panels.filter { statusFor($0).bucket == .todo }.count
    }

    private var staleCount: Int {
        panels.filter { statusFor($0).bucket == .old }.count
    }
}
