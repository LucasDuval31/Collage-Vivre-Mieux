import Foundation

final class OpenDataClient {
    private let base = URL(string:
        "https://data.toulouse-metropole.fr/api/explore/v2.1/catalog/datasets/panneaux-dexpression-libre-toulouse/records"
    )!

    private let session: URLSession = .shared
    private let decoder = JSONDecoder()

    func fetchAllPanels(pageSize: Int = 50) async throws -> [OpenDataPanel] {
        var all: [OpenDataPanel] = []
        var offset = 0

        while true {
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                .init(name: "limit", value: "\(pageSize)"),
                .init(name: "offset", value: "\(offset)")
            ]

            var req = URLRequest(url: comps.url!)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let page = try decoder.decode(OpenDataResponse.self, from: data)
            all.append(contentsOf: page.results)

            offset += page.results.count
            if page.results.isEmpty || all.count >= page.total_count { break }
        }

        return all
    }
}
