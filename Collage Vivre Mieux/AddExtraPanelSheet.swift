//
//  AddExtraPanelSheet.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 26/12/2025.
//


import SwiftUI
import CoreLocation

struct AddExtraPanelSheet: View {
    let location: CLLocation
    let userName: String
    let onAdd: (_ title: String, _ subtitle: String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Form {
            Section("Nom du panneau") {
                TextField("Rue / place", text: $title)
                TextField("Complément (optionnel)", text: $subtitle)
            }

            if isLoading {
                Section { ProgressView("Recherche de l’adresse…") }
            }
            if let error {
                Section { Text(error).foregroundStyle(.secondary) }
            }

            Section {
                Button("Ajouter") {
                    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let s = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAdd(t.isEmpty ? "Panneau (ajout équipe)" : t, s.isEmpty ? nil : s)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isLoading)

                Button("Annuler", role: .cancel) { dismiss() }
            }
        }
        .navigationTitle("Ajouter un panneau")
        .task { await fillFromReverseGeocode() }
    }

    private func fillFromReverseGeocode() async {
        isLoading = true
        error = nil

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let pm = placemarks.first {
                // On privilégie nom + rue/voie
                let name = pm.name ?? ""
                let thoroughfare = pm.thoroughfare ?? ""
                let locality = pm.locality ?? ""

                let best = [thoroughfare, name]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty } ?? "Panneau (ajout équipe)"

                title = best
                subtitle = locality
            } else {
                title = "Panneau (ajout équipe)"
                subtitle = ""
            }
        } catch {
            title = "Panneau (ajout équipe)"
            subtitle = ""
            self.error = "Impossible de récupérer l’adresse automatiquement."
        }

        isLoading = false
    }
}