import Foundation
import SwiftData
import Combine

@MainActor
final class PanelsVM: ObservableObject {
    @Published var panels: [OpenDataPanel] = []
    @Published var extraPanels: [ExtraPanel] = []

    // ✅ V2: lieux de vote agrégés (1 pin par lieu)
    @Published var votingSites: [VotingSite] = []

    @Published var isLoading = false
    @Published var error: String?

    @Published var recentEvents: [CoverEvent] = []
    @Published var dashboardEvents: [CoverEvent] = []

    private let openData = OpenDataClient()
    private let server = LightServerClient()

    // ✅ V2 client
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

    // ✅ V2: charge + agrège en sites (1 pin par lieu)
    func loadVotingSites() async {
        do {
            let rows = try await votingOpenData.fetchAllRows(limit: 5000)
            votingSites = votingOpenData.buildSites(from: rows)
        } catch {
            self.error = "Lieux de vote: \(error.localizedDescription)"
        }
    }

    // ✅ Option B : titre/subtitle modifiables
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

    // MARK: - Actions (cover / absent)

    func markCovered(
        panelId: String,
        coveredAt: Date,
        coveredBy: String,
        note: String?,
        photoFilename: String?,
        modelContext: ModelContext
    ) async {
        let status = upsertStatus(panelId: panelId, modelContext: modelContext)

        status.isAbsent = false
        status.absentAt = nil
        status.absentBy = nil
        status.absentReason = nil

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

        status.isAbsent = true
        status.absentAt = reportedAt
        status.absentBy = reportedBy
        status.absentReason = reason

        status.lastCoveredAt = nil
        status.lastCoveredBy = nil
        status.note = nil
        status.photoFilename = nil

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

                    s.lastCoveredAt = nil
                    s.lastCoveredBy = nil
                    s.note = nil
                    s.photoFilename = nil
                } else {
                    s.isAbsent = false
                    s.absentAt = nil
                    s.absentBy = nil
                    s.absentReason = nil

                    s.lastCoveredAt = ev.covered_at
                    s.lastCoveredBy = ev.covered_by
                    s.note = ev.note
                    s.photoFilename = ev.photo_filename
                }

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

                        s.lastCoveredAt = nil
                        s.lastCoveredBy = nil
                        s.note = nil
                        s.photoFilename = nil

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