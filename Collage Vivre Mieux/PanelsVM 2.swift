import Foundation
import SwiftData
import Combine

@MainActor
final class PanelsVM: ObservableObject {
    @Published var panels: [OpenDataPanel] = []
    @Published var extraPanels: [ExtraPanel] = []
    @Published var votingSites: [VotingSite] = []

    @Published var isLoading = false
    @Published var error: String?

    @Published var recentEvents: [CoverEvent] = []
    @Published var dashboardEvents: [CoverEvent] = []

    private let openData = OpenDataClient()
    private let server = LightServerClient()
    private let votingOpenData = VotingOpenDataClient()

    // MARK: - Loading

    func loadPanels() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            panels = try await openData.fetchAllPanels()
        } catch {
            self.error = "OpenData: \(error.localizedDescription)"
        }
    }

    func loadExtraPanels() async {
        do {
            extraPanels = try await server.fetchExtraPanels(limit: 5000)
        } catch {
            self.error = "Extra panneaux: \(error.localizedDescription)"
        }
    }

    func loadVotingSites() async {
        do {
            votingSites = try await votingOpenData.fetchVotingSites(pageSize: 100)
        } catch {
            self.error = "Lieux de vote: \(error.localizedDescription)"
        }
    }

    func addExtraPanel(lat: Double, lon: Double, title: String, subtitle: String?, createdBy: String) async {
        do {
            try await server.postExtraPanel(
                lat: lat,
                lon: lon,
                title: title,
                subtitle: subtitle,
                createdBy: createdBy
            )
            await loadExtraPanels()
        } catch {
            self.error = "Ajout panneau: \(error.localizedDescription)"
        }
    }

    // MARK: - Actions (covered / absent / overposted / todo)

    func markCovered(
        panelId: String,
        coveredAt: Date,
        coveredBy: String,
        note: String?,
        photoFilename: String?,
        modelContext: ModelContext
    ) async {
        let status = upsertStatus(panelId: panelId, modelContext: modelContext)

        // reset absent
        status.isAbsent = false
        status.absentAt = nil
        status.absentBy = nil
        status.absentReason = nil

        // reset overposted
        status.isOverposted = false
        status.overpostedAt = nil
        status.overpostedBy = nil
        status.overpostedNote = nil

        // set covered
        status.lastCoveredAt = coveredAt
        status.lastCoveredBy = coveredBy
        status.note = note
        status.photoFilename = photoFilename

        status.needsSync = true

        let event = CoverEvent(
            id: UUID().uuidString,
            panelId: panelId,
            coveredAt: coveredAt,
            coveredBy: coveredBy,
            note: note,
            photoFilename: photoFilename,
            eventType: "covered",
            absentReason: nil
        )

        do {
            try await server.postCoverEvent(event)
            status.needsSync = false
            status.lastSyncedAt = .now
        } catch {
            self.error = "Sync: \(error.localizedDescription)"
        }
    }

    func reportAbsent(
        panelId: String,
        reportedAt: Date,
        reportedBy: String,
        reason: String?,
        modelContext: ModelContext
    ) async {
        let status = upsertStatus(panelId: panelId, modelContext: modelContext)

        // set absent
        status.isAbsent = true
        status.absentAt = reportedAt
        status.absentBy = reportedBy
        status.absentReason = reason

        // reset covered
        status.lastCoveredAt = nil
        status.lastCoveredBy = nil
        status.note = nil
        status.photoFilename = nil

        // reset overposted
        status.isOverposted = false
        status.overpostedAt = nil
        status.overpostedBy = nil
        status.overpostedNote = nil

        status.needsSync = true

        let event = CoverEvent(
            id: UUID().uuidString,
            panelId: panelId,
            coveredAt: reportedAt,
            coveredBy: reportedBy,
            note: nil,
            photoFilename: nil,
            eventType: "absent",
            absentReason: reason
        )

        do {
            try await server.postCoverEvent(event)
            status.needsSync = false
            status.lastSyncedAt = .now
        } catch {
            self.error = "Sync absent: \(error.localizedDescription)"
        }
    }

    // ✅ NEW: recouvert adversaires
    func markOverposted(
        panelId: String,
        at: Date,
        by: String,
        note: String?,
        modelContext: ModelContext
    ) async {
        let status = upsertStatus(panelId: panelId, modelContext: modelContext)

        // reset absent
        status.isAbsent = false
        status.absentAt = nil
        status.absentBy = nil
        status.absentReason = nil

        // reset covered (optionnel, mais logique: s’il est recouvert par adversaires => plus “à jour”)
        status.lastCoveredAt = nil
        status.lastCoveredBy = nil
        status.note = nil
        status.photoFilename = nil

        // set overposted
        status.isOverposted = true
        status.overpostedAt = at
        status.overpostedBy = by
        status.overpostedNote = note

        status.needsSync = true

        let event = CoverEvent(
            id: UUID().uuidString,
            panelId: panelId,
            coveredAt: at,
            coveredBy: by,
            note: note,
            photoFilename: nil,
            eventType: "overposted",
            absentReason: nil
        )

        do {
            try await server.postCoverEvent(event)
            status.needsSync = false
            status.lastSyncedAt = .now
        } catch {
            self.error = "Sync adversaires: \(error.localizedDescription)"
        }
    }

    // ✅ NEW: marquer à faire (reset)
    func markTodo(
        panelId: String,
        at: Date,
        by: String,
        modelContext: ModelContext
    ) async {
        let status = upsertStatus(panelId: panelId, modelContext: modelContext)

        // reset all
        status.isAbsent = false
        status.absentAt = nil
        status.absentBy = nil
        status.absentReason = nil

        status.isOverposted = false
        status.overpostedAt = nil
        status.overpostedBy = nil
        status.overpostedNote = nil

        status.lastCoveredAt = nil
        status.lastCoveredBy = nil
        status.note = nil
        status.photoFilename = nil

        status.needsSync = true

        let event = CoverEvent(
            id: UUID().uuidString,
            panelId: panelId,
            coveredAt: at,
            coveredBy: by,
            note: nil,
            photoFilename: nil,
            eventType: "todo",
            absentReason: nil
        )

        do {
            try await server.postCoverEvent(event)
            status.needsSync = false
            status.lastSyncedAt = .now
        } catch {
            self.error = "Sync à faire: \(error.localizedDescription)"
        }
    }

    // MARK: - Coordination (Responsabilité)

        /// Alterne la responsabilité de l'utilisateur sur un panneau et synchronise avec Supabase
        func toggleResponsibility(panelId: String, userName: String, modelContext: ModelContext) {
            // 1. Mise à jour locale dans SwiftData
            let status = upsertStatus(panelId: panelId, modelContext: modelContext)
            
            if status.assignedTo == userName {
                // Si c'est déjà l'utilisateur, on libère le panneau localement
                status.assignedTo = nil
                status.assignedAt = nil
                print("Responsabilité retirée localement pour le panneau: \(panelId)")
            } else {
                // Sinon, on assigne l'utilisateur comme responsable localement
                status.assignedTo = userName
                status.assignedAt = Date()
                print("Utilisateur \(userName) désormais responsable localement du panneau: \(panelId)")
            }
            
            // 2. PROTECTION : On met à jour la date de synchro locale à "maintenant"
            // Cela empêche la fonction 'syncFromServer' d'écraser ce panneau
            // avec d'anciennes données pendant que la requête réseau est en cours.
            status.lastSyncedAt = .now
            
            // 3. Synchronisation asynchrone avec le serveur Supabase
            Task {
                do {
                    // Appel de la méthode qui utilise NSNull() pour le retrait
                    try await server.updateAssignment(
                        panelId: panelId,
                        user: status.assignedTo,
                        date: status.assignedAt
                    )
                    print("✅ Synchronisation de la responsabilité réussie sur Supabase")
                    
                    // On confirme la synchro après le succès serveur
                    status.lastSyncedAt = .now
                } catch {
                    print("❌ Erreur de synchronisation coordination : \(error.localizedDescription)")
                    // En cas d'échec, on marque qu'il faudra resynchroniser
                    status.needsSync = true
                }
            }
        }
    // MARK: - Sync

        func syncFromServer(modelContext: ModelContext) async {
            do {
                let events = try await server.fetchLatestEvents(limit: 5000)
                let serverPanelIds = Set(events.map { $0.panel_id })

                for ev in events {
                    let s = upsertStatus(panelId: ev.panel_id, modelContext: modelContext)
                    if s.needsSync { continue }

                    let type = (ev.event_type ?? "covered").lowercased()

                    if type == "absent" {
                        s.isAbsent = true
                        s.absentAt = ev.covered_at
                        s.absentBy = ev.covered_by
                        s.absentReason = ev.absent_reason

                        s.isOverposted = false
                        s.overpostedAt = nil
                        s.overpostedBy = nil
                        s.overpostedNote = nil

                        s.lastCoveredAt = nil
                        s.lastCoveredBy = nil
                        s.note = nil
                        s.photoFilename = nil

                    } else if type == "overposted" {
                        s.isAbsent = false
                        s.absentAt = nil
                        s.absentBy = nil
                        s.absentReason = nil

                        s.isOverposted = true
                        s.overpostedAt = ev.covered_at
                        s.overpostedBy = ev.covered_by
                        s.overpostedNote = ev.note

                        s.lastCoveredAt = nil
                        s.lastCoveredBy = nil
                        s.note = nil
                        s.photoFilename = nil

                    } else if type == "todo" {
                        s.isAbsent = false
                        s.absentAt = nil
                        s.absentBy = nil
                        s.absentReason = nil

                        s.isOverposted = false
                        s.overpostedAt = nil
                        s.overpostedBy = nil
                        s.overpostedNote = nil

                        s.lastCoveredAt = nil
                        s.lastCoveredBy = nil
                        s.note = nil
                        s.photoFilename = nil

                    } else {
                        // covered
                        s.isAbsent = false
                        s.absentAt = nil
                        s.absentBy = nil
                        s.absentReason = nil

                        s.isOverposted = false
                        s.overpostedAt = nil
                        s.overpostedBy = nil
                        s.overpostedNote = nil

                        s.lastCoveredAt = ev.covered_at
                        s.lastCoveredBy = ev.covered_by
                        s.note = ev.note
                        s.photoFilename = ev.photo_filename
                    }
                    
                    // ✅ Mise à jour de la responsabilité depuis le serveur
                    s.assignedTo = ev.assigned_to
                    s.assignedAt = ev.assigned_at
                    
                    s.needsSync = false
                    s.lastSyncedAt = .now
                }

                // Reconcile deletions
                do {
                    let locals = try modelContext.fetch(FetchDescriptor<PanelLocalStatus>())
                    for s in locals {
                        if s.needsSync { continue }
                        if !serverPanelIds.contains(s.panelId) {
                            s.isAbsent = false
                            s.absentAt = nil
                            s.absentBy = nil
                            s.absentReason = nil

                            s.isOverposted = false
                            s.overpostedAt = nil
                            s.overpostedBy = nil
                            s.overpostedNote = nil

                            s.lastCoveredAt = nil
                            s.lastCoveredBy = nil
                            s.note = nil
                            s.photoFilename = nil

                            // ✅ On remet aussi à zéro le responsable si le panneau disparaît du serveur
                            s.assignedTo = nil
                            s.assignedAt = nil

                            s.lastSyncedAt = .now
                        }
                    }
                } catch {
                    self.error = "Reconcile local: \(error.localizedDescription)"
                }

            } catch {
                self.error = "Lecture serveur : \(error.localizedDescription)"
            }
        }
    // MARK: - Activity / Dashboard

    func loadRecentActivity() async {
        do { recentEvents = try await server.fetchRecentEvents(limit: 80) }
        catch { self.error = "Activité: \(error.localizedDescription)" }
    }

    func loadDashboardData() async {
        do { dashboardEvents = try await server.fetchRecentEvents(limit: 2000) }
        catch { self.error = "Dashboard: \(error.localizedDescription)" }
    }

    // MARK: - Local status helper

    private func upsertStatus(panelId: String, modelContext: ModelContext) -> PanelLocalStatus {
        let descriptor = FetchDescriptor<PanelLocalStatus>(
            predicate: #Predicate { $0.panelId == panelId }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let s = PanelLocalStatus(panelId: panelId)
        modelContext.insert(s)
        return s
    }
}
