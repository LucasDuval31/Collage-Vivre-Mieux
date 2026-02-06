import Foundation
import CoreLocation

final class VotingOpenDataClient {

    private let baseURL = URL(
        string: "https://data.toulouse-metropole.fr/api/explore/v2.1/catalog/datasets/election-2026-lieux-de-vote/records"
    )!

    private let session: URLSession = .shared

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    // MARK: - Public

    func fetchVotingSites(pageSize: Int = 100, maxPages: Int = 200) async throws -> [VotingSite] {
        // 1) Fetch en pagination (évite le -1011 quand on met un limit trop grand)
        let rows = try await fetchAllRows(pageSize: pageSize, maxPages: maxPages)

        // 2) Agrège en 1 lieu = 1 pin, basé sur l’adresse DU LIEU
        let grouped = Self.aggregateRowsByLieuAddress(rows: rows)

        // 3) Géocode les adresses -> coordonnées
        let sites = try await geocodeGroupsToSites(grouped)

        return sites.sorted { $0.title < $1.title }
    }

    // MARK: - Fetch pages

    private func fetchAllRows(pageSize: Int, maxPages: Int) async throws -> [VotingOpenDataRow] {
        var all: [VotingOpenDataRow] = []
        var offset = 0
        var total: Int? = nil

        for _ in 0..<maxPages {
            let (pageRows, totalCount) = try await fetchPage(limit: pageSize, offset: offset)
            if total == nil { total = totalCount }

            all.append(contentsOf: pageRows)

            if pageRows.isEmpty { break }
            offset += pageRows.count

            if let total, all.count >= total { break }
        }

        return all
    }

    private func fetchPage(limit: Int, offset: Int) async throws -> ([VotingOpenDataRow], Int) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "limit", value: "\(limit)"),
            .init(name: "offset", value: "\(offset)")
        ]

        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("CollageVivreMieux/2.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            print("❌ Voting OpenData HTTP \(http.statusCode)\n\(body)")
            throw URLError(.badServerResponse)
        }

        let decoded = try decoder.decode(VotingOpenDataResponse.self, from: data)
        return (decoded.results, decoded.total_count)
    }

    // MARK: - Aggregation (1 pin par lieu)

    private static func normalizeAddressKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Retourne un dictionnaire: key = adresse lieu normalisée, value = rows associées
    private static func aggregateRowsByLieuAddress(rows: [VotingOpenDataRow]) -> [String: [VotingOpenDataRow]] {
        var dict: [String: [VotingOpenDataRow]] = [:]

        for r in rows {
            guard let addr = r.lieuAddress, !addr.isEmpty else { continue }
            let key = normalizeAddressKey(addr)
            dict[key, default: []].append(r)
        }

        return dict
    }

    // MARK: - Geocoding

    private func geocodeGroupsToSites(_ groups: [String: [VotingOpenDataRow]]) async throws -> [VotingSite] {
        let geocoder = CLGeocoder()
        var sites: [VotingSite] = []

        // Géocodage séquentiel (plus stable, évite de se faire throttler)
        for (key, rows) in groups {
            guard let first = rows.first else { continue }

            let title = (first.nom?.trimmingCharacters(in: .whitespacesAndNewlines)).nilIfEmpty ?? "Lieu de vote"
            let addr = (first.lieuAddress?.trimmingCharacters(in: .whitespacesAndNewlines)).nilIfEmpty ?? ""

            let bureaux = rows.compactMap { $0.bureau?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted()

            // 🔎 On force Toulouse/France pour lever l’ambiguïté
            let query = "\(addr), 31000 Toulouse, France"

            // Si l’adresse est vide, on skip
            if addr.isEmpty { continue }

            do {
                let placemarks = try await geocoder.geocodeAddressString(query)
                guard let coord = placemarks.first?.location?.coordinate else { continue }

                let subtitle = addr + (bureaux.isEmpty ? "" : " • Bureaux \(bureaux.joined(separator: ", "))")

                sites.append(
                    VotingSite(
                        id: "vote:\(key)",      // ✅ 1 id = 1 adresse lieu => 1 pin
                        title: title,
                        subtitle: subtitle,
                        coordinate: coord,
                        bureauList: bureaux
                    )
                )
            } catch {
                // On n’échoue pas tout : on saute juste ce lieu
                print("⚠️ Geocode failed for \(query): \(error.localizedDescription)")
                continue
            }
        }

        return sites
    }
}

// MARK: - Helpers

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
