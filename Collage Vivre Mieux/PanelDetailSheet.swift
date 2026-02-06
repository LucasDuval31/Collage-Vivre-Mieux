import SwiftUI
import MapKit
import CoreLocation
import SwiftData

struct PanelDetailSheet: View {

    let panel: PanelItem
    let status: PanelComputedStatus
    let userName: String

    let onCovered: (_ coveredAt: Date, _ note: String?, _ photoFilename: String?) -> Void
    let onOverposted: (_ at: Date, _ note: String?) -> Void
    let onMarkTodo: (_ at: Date) -> Void
    let onReportAbsent: (_ reason: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var vm: PanelsVM // Permet d'appeler toggleResponsibility

    @AppStorage("travel_mode") private var travelModeRaw: String = TravelMode.driving.rawValue
    private var travelMode: TravelMode { TravelMode(rawValue: travelModeRaw) ?? .driving }

    @State private var note: String = ""

    @State private var showCoveredConfirm = false
    @State private var showOverpostedConfirm = false
    @State private var showTodoConfirm = false

    @State private var showAbsentConfirm = false
    @State private var absentReason: String = "Introuvable"

    var body: some View {
        NavigationStack {
            Form {
                // --- SECTION COORDINATION (AJOUTÉE) ---
                Section("Coordination") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let responsible = status.local?.assignedTo {
                                Label {
                                    Text("Responsable : \(responsible)")
                                        .font(.headline)
                                } icon: {
                                    Image(systemName: "person.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                                
                                if let date = status.local?.assignedAt {
                                    Text("Depuis le \(date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Label {
                                    Text("Aucun responsable")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                } icon: {
                                    Image(systemName: "person.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button {
                            vm.toggleResponsibility(
                                panelId: panel.id,
                                userName: userName,
                                modelContext: modelContext
                            )
                        } label: {
                            Text(status.local?.assignedTo == userName ? "Se retirer" : "Prendre")
                        }
                        .buttonStyle(.bordered)
                        .tint(status.local?.assignedTo == userName ? .red : .blue)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(panel.title)
                            .font(.title3)
                            .fontWeight(.bold)

                        if !panel.subtitle.isEmpty {
                            Text(panel.subtitle)
                                .foregroundStyle(.secondary)
                        }

                        let c = panel.coordinate
                        Text("Coordonnées : \(String(format: "%.5f", c.latitude)), \(String(format: "%.5f", c.longitude))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Statut") {
                    switch status.bucket {
                    case .absent:
                        Text("⚫️ Absent")

                    case .todo:
                        Text("🔴 À faire")
                            .foregroundStyle(.secondary)

                    case .upToDate:
                        Text("🟢 À jour (<24h)")

                    case .old:
                        Text("🟠 À refaire")

                    case .pendingSync:
                        Text("🔵 En attente de synchronisation")
                            .foregroundStyle(.secondary)

                    case .overposted:
                        Text("🔷 Recouvert par les adversaires")
                    }
                }

                Section("Actions") {

                    Button { openDirections() } label: {
                        Label("Ouvrir l’itinéraire", systemImage: "map")
                    }

                    Divider()

                    // ✅ Panneau fait
                    Button {
                        showCoveredConfirm = true
                    } label: {
                        Label("Panneau fait", systemImage: "checkmark.circle")
                    }
                    .confirmationDialog("Confirmer : panneau fait ?", isPresented: $showCoveredConfirm) {
                        Button("Oui, panneau fait") {
                            onCovered(
                                Date(),
                                note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                nil
                            )
                            dismiss()
                        }
                        Button("Annuler", role: .cancel) {}
                    }

                    // ✅ Recouvert adversaires
                    Button {
                        showOverpostedConfirm = true
                    } label: {
                        Label("Panneau recouvert par les adversaires", systemImage: "exclamationmark.triangle")
                    }
                    .confirmationDialog("Confirmer : recouvert par les adversaires ?", isPresented: $showOverpostedConfirm) {
                        Button("Oui, recouvert par les adversaires") {
                            onOverposted(
                                Date(),
                                note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            )
                            dismiss()
                        }
                        Button("Annuler", role: .cancel) {}
                    }

                    // ✅ Marquer à faire
                    Button(role: .destructive) {
                        showTodoConfirm = true
                    } label: {
                        Label("Marquer à faire", systemImage: "arrow.uturn.left")
                    }
                    .confirmationDialog("Remettre ce panneau « à faire » ?", isPresented: $showTodoConfirm) {
                        Button("Oui, remettre à faire", role: .destructive) {
                            onMarkTodo(Date())
                            dismiss()
                        }
                        Button("Annuler", role: .cancel) {}
                    }

                    Divider()

                    // Absent
                    Picker("Raison (absent)", selection: $absentReason) {
                        Text("Introuvable").tag("Introuvable")
                        Text("Travaux").tag("Travaux")
                        Text("Retiré / remplacé").tag("Retiré / remplacé")
                        Text("Dégradé / inutilisable").tag("Dégradé / inutilisable")
                        Text("Autre").tag("Autre")
                    }
                    .pickerStyle(.menu)

                    Button(role: .destructive) {
                        showAbsentConfirm = true
                    } label: {
                        Label("Signaler panneau absent", systemImage: "xmark.circle")
                    }
                    .confirmationDialog("Signaler ce panneau comme absent ?", isPresented: $showAbsentConfirm) {
                        Button("Oui, signaler absent", role: .destructive) {
                            let r = (absentReason == "Autre") ? nil : absentReason
                            onReportAbsent(r)
                            dismiss()
                        }
                        Button("Annuler", role: .cancel) {}
                    }
                }

                Section("Note (optionnel)") {
                    TextField("Ex : recouvert côté nord…", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Détails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var directionsMode: DirectionsMode {
        switch travelMode {
        case .driving: return .driving
        case .walking: return .walking
        case .transit: return .transit
        @unknown default: return .driving
        }
    }

    private func openDirections() {
        Directions.openInAppleMaps(
            title: panel.title,
            coordinate: panel.coordinate,
            mode: directionsMode
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
