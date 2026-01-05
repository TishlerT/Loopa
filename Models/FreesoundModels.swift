import Foundation

struct SearchResponse: Decodable {
	let count: Int
	let next: String?
	let previous: String?
	let results: [Sound]
}

struct Sound: Decodable, Identifiable {
	let id: Int
	let name: String
	let duration: Double?
	let license: String?
	let user: UserSummary?
	let tags: [String]?
	let previews: [String: String]?
}

struct UserSummary: Decodable {
	let username: String
}

struct SoundDetail: Decodable {
	let id: Int
	let name: String
	let duration: Double?
	let license: String?
	let tags: [String]?
	let user: UserSummary?
	let previews: [String: String]?
}





