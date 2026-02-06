//
//  DashboardView.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 22/12/2025.
//

import SwiftUI

struct DashboardView: View {
    let totalPanels: Int
    let events: [CoverEvent]
    let absentNowCount: Int
    let absentAllTimeCount: Int

    var body: some View {
        List {
            Section("Aujourd’hui") {
                Text("Panneaux couverts aujourd’hui: \(coveredTodayCount)")
                Text("Couvreurs actifs: \(activePeopleCount)")
            }

            Section("Top couvreurs (aujourd’hui)") {
                ForEach(topPeopleToday, id: \.name) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text("\(row.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Couverture (approx.)") {
                // Approche: nb de panneaux ayant au moins un event (sur la période chargée)
                Text("Panneaux distincts couverts (historique chargé): \(distinctPanelsCovered)")

                HStack {
                    Text("Absents")
                    Spacer()
                    Text("\(absentAllTimeCount)")
                        .foregroundStyle(.secondary)
                }
                Text("Total panneaux (OpenData): \(totalPanels)")
            }
        }
        .navigationTitle("Tableau de bord")
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var coveredTodayCount: Int {
        events.filter { $0.covered_at >= startOfToday }.count
    }

    private var activePeopleCount: Int {
        Set(events.filter { $0.covered_at >= startOfToday }.map { $0.covered_by }).count
    }

    private var topPeopleToday: [(name: String, count: Int)] {
        let today = events.filter { $0.covered_at >= startOfToday }
        let grouped = Dictionary(grouping: today, by: { $0.covered_by })
        return grouped
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    private var distinctPanelsCovered: Int {
        Set(events.map { $0.panel_id }).count
    }
}
