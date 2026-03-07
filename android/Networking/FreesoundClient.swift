import Foundation

struct FreesoundClient {
	let http = HTTPClient()
	let tokenProvider: () -> String?

	func token() throws -> String {
		guard let t = tokenProvider(), !t.isEmpty else {
			throw NSError(domain: "Freesound", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing FREESOUND_API_TOKEN"])
		}
		return t
	}

	func search(query: String, page: Int = 1, pageSize: Int = 30) async throws -> SearchResponse {
		let t = try token()
		let params = [
			URLQueryItem(name: "query", value: query),
			URLQueryItem(name: "page", value: String(page)),
			URLQueryItem(name: "page_size", value: String(pageSize))
		]
		let fields = ["id","name","previews","duration","license","user","created","tags"]
		return try await http.get("search/text/", query: params, fields: fields, token: t)
	}

	func sound(id: Int) async throws -> SoundDetail {
		let t = try token()
		let fields = ["id","name","previews","duration","license","user","tags"]
		return try await http.get("sounds/\(id)/", query: [], fields: fields, token: t)
	}
}





