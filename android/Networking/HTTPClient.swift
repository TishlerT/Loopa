import Foundation

struct HTTPClient {
	struct Response<T: Decodable>: Decodable { let value: T }

	let baseURL = URL(string: "https://freesound.org/apiv2")!

	func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], fields: [String]? = nil, token: String) async throws -> T {
		var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
		var items = query
		if let fields, !fields.isEmpty {
			items.append(URLQueryItem(name: "fields", value: fields.joined(separator: ",")))
		}
		components.queryItems = items.isEmpty ? nil : items
		var req = URLRequest(url: components.url!)
		req.httpMethod = "GET"
		req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
		let (data, resp) = try await URLSession.shared.data(for: req)
		guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
		guard 200..<300 ~= http.statusCode else {
			throw NSError(domain: "Freesound", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"])
		}
		return try JSONDecoder().decode(T.self, from: data)
	}
}





