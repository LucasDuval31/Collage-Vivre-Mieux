import Foundation

final class LightServerClient {
    private let supabaseURL = URL(string: "https://jrndehihfbanbnplpcty.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpybmRlaGloZmJhbmJucGxwY3R5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjYzNTM2ODIsImV4cCI6MjA4MTkyOTY4Mn0.UQcNw-3Ql1ouIREdhz0eE8SwG-yqkZiJ-ILfuCZyhVU"
    private let session: URLSession = .shared

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func validate(_ data: Data?, _ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            if let data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
                throw NSError(domain: "Supabase", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: s])
            }
            throw NSError(domain: "Supabase", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
    }

    // MARK: - Coordination (Responsabilité)

        /// Met à jour la responsabilité d'un panneau sur la table dédiée
        func updateAssignment(panelId: String, user: String?, date: Date?) async throws {
            // On cible la ligne précise du panneau via son ID
            let url = supabaseURL.appendingPathComponent("rest/v1/panel_assignments")
            
            // On utilise POST avec l'en-tête UPSERT (plus robuste pour la création/mise à jour)
            var req = makeRequest(url: url, method: "POST")
            
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // "resolution=merge-duplicates" permet de mettre à jour si le panel_id existe déjà
            req.setValue("return=minimal, resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

            // Structure locale
            struct AssignmentBody: Codable {
                let panel_id: String
                let assigned_to: String?
                let assigned_at: Date?
            }

            let body = AssignmentBody(
                panel_id: panelId,
                assigned_to: user, // Si c'est nil, on veut que Supabase reçoive "null"
                assigned_at: date
            )

            // Force l'encodage des valeurs optionnelles à null
            // Note: L'encodeur JSON de base omet parfois les clés nil.
            // Si le problème persiste, on passe par un dictionnaire.
            let jsonData: Data
            if user == nil {
                // Pour le retrait, on envoie un dictionnaire explicite pour forcer le null
                let dict: [String: Any?] = [
                    "panel_id": panelId,
                    "assigned_to": NSNull(),
                    "assigned_at": NSNull()
                ]
                // On utilise JSONSerialization car JSONEncoder peut sauter les clés nil
                jsonData = try JSONSerialization.data(withJSONObject: dict)
            } else {
                jsonData = try encoder.encode(body)
            }

            req.httpBody = jsonData
            
            let (data, resp) = try await session.data(for: req)
            try validate(data, resp)
            
            print("📡 Supabase : Mise à jour responsable \(user ?? "Retrait") pour \(panelId)")
        }

    // MARK: - Cover events

    func postCoverEvent(_ event: CoverEvent) async throws {
        let url = supabaseURL.appendingPathComponent("rest/v1/cover_events")
        var req = makeRequest(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try encoder.encode(event)

        let (data, resp) = try await session.data(for: req)
        try validate(data, resp)
    }

    /// Récupère l'état combiné (Collage + Responsable) via la vue SQL
    func fetchLatestEvents(limit: Int = 5000) async throws -> [CoverEvent] {
        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("rest/v1/latest_combined_status"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            .init(name: "order", value: "covered_at.desc.nullslast"),
            .init(name: "limit", value: "\(limit)")
        ]

        let req = makeRequest(url: components.url!, method: "GET")
        let (data, resp) = try await session.data(for: req)
        try validate(data, resp)
        return try decoder.decode([CoverEvent].self, from: data)
    }

    func fetchRecentEvents(limit: Int = 80) async throws -> [CoverEvent] {
        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("rest/v1/cover_events"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            .init(name: "order", value: "covered_at.desc"),
            .init(name: "limit", value: "\(limit)")
        ]

        let req = makeRequest(url: components.url!, method: "GET")
        let (data, resp) = try await session.data(for: req)
        try validate(data, resp)
        return try decoder.decode([CoverEvent].self, from: data)
    }

    // MARK: - Extra panels

    func fetchExtraPanels(limit: Int = 5000) async throws -> [ExtraPanel] {
        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("rest/v1/extra_panels"),
            resolvingAgainstBaseURL: false
        )!

        components.queryItems = [
            .init(name: "select", value: "*"),
            .init(name: "order", value: "created_at.desc"),
            .init(name: "limit", value: "\(limit)")
        ]

        let req = makeRequest(url: components.url!, method: "GET")
        let (data, resp) = try await session.data(for: req)
        try validate(data, resp)
        return try decoder.decode([ExtraPanel].self, from: data)
    }

    @discardableResult
    func postExtraPanel(lat: Double, lon: Double, title: String?, subtitle: String?, createdBy: String?) async throws -> ExtraPanel? {
        let url = supabaseURL.appendingPathComponent("rest/v1/extra_panels")
        var req = makeRequest(url: url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")

        struct Body: Codable {
            let lat: Double
            let lon: Double
            let title: String?
            let subtitle: String?
            let created_by: String?
        }

        req.httpBody = try encoder.encode(
            Body(lat: lat, lon: lon, title: title, subtitle: subtitle, created_by: createdBy)
        )

        let (data, resp) = try await session.data(for: req)
        try validate(data, resp)

        if data.isEmpty { return nil }
        if let arr = try? decoder.decode([ExtraPanel].self, from: data) {
            return arr.first
        }
        return nil
    }
}
