//
//  TourView.swift
//  Collage Vivre Mieux
//
//  Created by Lucas Duval on 22/12/2025.
//

import SwiftUI
import CoreLocation

struct TourView: View {
    let panels: [OpenDataPanel]
    let statusFor: (OpenDataPanel) -> PanelComputedStatus
    let currentLocation: CLLocation?

    // "Continuer tournée"
    @AppStorage("last_route_panel_id") private var lastRoutePanelId: String = ""
    @AppStorage("last_route_title") private var lastRouteTitle: String = ""
    @AppStorage("last_route_lat") private var lastRouteLat: Double = 0
    @AppStorage("last_route_lon") private var lastRouteLon: Double = 0
    @AppStorage("last_route_ts") private var lastRouteTS: Double = 0 // Date().timeIntervalSince1970

    // Règles tournée
    private let refreshHours: Double = 24
    private let minDistanceMetersToRoute: CLLocationDistance = 30

    var body: some View {
        List {
            Section {
                Button {
                    startTour()
                } label: {
                    Label("Démarrer tournée (prochain panneau)", systemImage: "play.circle")
                }
                .disabled(currentLocation == nil || nextCandidatePanel(from: currentLocation) == nil)

                Button {
                    continueTour()
                } label: {
                    Label(continueLabel, systemImage: "arrow.triangle.turn.up.right.circle")
                }
                .disabled(!hasLastRoute)

                if !hasLastRoute {
                    Text("Astuce : ouvre un itinéraire depuis un panneau pour activer “Continuer tournée”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let d = lastRouteDate {
                    Text("Dernier itinéraire : \(relative(d))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Tournée")
            }

            Section("Panneaux proches") {
                Text("10 panneaux les plus proches à faire.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let loc = currentLocation {
                    ForEach(closestCandidates(from: loc).prefix(10), id: \.panel.id) { item in
                        Button {
                            openDirections(to: item.panel)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.panel.title).font(.headline)
                                if !item.panel.subtitle.isEmpty {
                                    Text(item.panel.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text(distanceText(item.distance))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Active la localisation pour calculer les panneaux proches.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Panneaux proches")
    }

    // MARK: - Actions

    private func startTour() {
        guard let loc = currentLocation,
              let next = nextCandidatePanel(from: loc)
        else { return }

        openDirections(to: next)
    }

    private func continueTour() {
        guard hasLastRoute else { return }
        let coord = CLLocationCoordinate2D(latitude: lastRouteLat, longitude: lastRouteLon)

        Directions.openInAppleMaps(
            title: lastRouteTitle.isEmpty ? "Itinéraire" : lastRouteTitle,
            coordinate: coord,
            mode: .driving
        )
    }

    private func openDirections(to panel: OpenDataPanel) {
        guard let c = panel.coordinate else { return }

        // mémoriser pour "Continuer tournée"
        lastRoutePanelId = panel.id
        lastRouteTitle = panel.title
        lastRouteLat = c.latitude
        lastRouteLon = c.longitude
        lastRouteTS = Date().timeIntervalSince1970

        Directions.openInAppleMaps(title: panel.title, coordinate: c, mode: .driving)
    }

    // MARK: - Candidate selection

    private func nextCandidatePanel(from loc: CLLocation?) -> OpenDataPanel? {
        guard let loc else { return nil }
        return closestCandidates(from: loc).first?.panel
    }

    /// "À faire" = pas absent ET (jamais fait OU fait il y a plus de 24h)
    /// + ignore les panneaux trop proches (<30m) pour éviter "tu es déjà arrivé"
    private func closestCandidates(from loc: CLLocation) -> [(panel: OpenDataPanel, distance: CLLocationDistance)] {
        let cutoff = Date().addingTimeInterval(-refreshHours * 60 * 60)

        return panels
            .filter { panel in
                let st = statusFor(panel)
                if st.isAbsent { return false }

                // jamais fait => OK
                guard let last = st.local?.lastCoveredAt else { return true }

                // fait récemment => exclu (<24h)
                return last <= cutoff
            }
            .compactMap { p -> (OpenDataPanel, CLLocationDistance)? in
                guard let c = p.coordinate else { return nil }
                let d = loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                if d < minDistanceMetersToRoute { return nil } // ignore si déjà dessus
                return (p, d)
            }
            .sorted { $0.1 < $1.1 }
    }

    // MARK: - Formatting

    private func distanceText(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int(meters)) m" }
        return String(format: "%.1f km", meters / 1000.0)
    }

    // MARK: - Continue helpers

    private var hasLastRoute: Bool {
        !(lastRouteLat == 0 && lastRouteLon == 0)
    }

    private var lastRouteDate: Date? {
        guard lastRouteTS > 0 else { return nil }
        return Date(timeIntervalSince1970: lastRouteTS)
    }

    private var continueLabel: String {
        if lastRouteTitle.isEmpty { return "Continuer tournée" }
        return "Continuer tournée • \(lastRouteTitle)"
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
