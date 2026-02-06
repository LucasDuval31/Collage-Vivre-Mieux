//
//  ActivityView.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 22/12/2025.
//

import SwiftUI

struct ActivityView: View {
    let events: [CoverEvent]

    var body: some View {
        List(events) { e in
            VStack(alignment: .leading, spacing: 4) {
                Text(e.covered_by).font(.headline)
                Text("Panneau: \(e.panel_id)").font(.subheadline).foregroundStyle(.secondary)
                Text(dateText(e.covered_at)).font(.caption).foregroundStyle(.secondary)
                if let note = e.note, !note.isEmpty {
                    Text(note).font(.caption)
                }
            }
        }
        .navigationTitle("Activité récente")
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .init(identifier: "fr_FR")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }
}
