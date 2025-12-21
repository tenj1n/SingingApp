import Foundation

struct LyricsLine: Decodable, Identifiable, Hashable {
    let id = UUID()
    let start: Double
    let end: Double
    let text: String
    
    private enum CodingKeys: String, CodingKey { case start, end, text }
}

struct LyricsRoot: Decodable {
    let lines: [LyricsLine]
}
