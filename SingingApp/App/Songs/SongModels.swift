import Foundation

struct Song: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let instrumental: String
    let singer: String?
    let lyrics: String
}

struct SongManifest: Decodable {
    let songs: [Song]
}
