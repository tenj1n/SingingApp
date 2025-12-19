import Foundation

struct SimpleOkResponse: Codable {
    let ok: Bool
    let message: String?
}

struct HistoryItem: Codable, Identifiable {
    let id: String
    let songId: String
    let userId: String
    let createdAt: String
    
    let commentTitle: String
    let commentBody: String
    
    let score100: Double?
    let score100Strict: Double?
    let score100OctaveInvariant: Double?
    let octaveInvariantNow: Bool?
    
    let tolCents: Double?
    let percentWithinTol: Double?
    let meanAbsCents: Double?
    let sampleCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case songId = "song_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case commentTitle = "comment_title"
        case commentBody  = "comment_body"
        case score100
        case score100Strict = "score100_strict"
        case score100OctaveInvariant = "score100_octave_invariant"
        case octaveInvariantNow = "octave_invariant_now"
        case tolCents = "tol_cents"
        case percentWithinTol = "percent_within_tol"
        case meanAbsCents = "mean_abs_cents"
        case sampleCount = "sample_count"
    }
    
    /// CompareView 用のセッションID（song/user）
    var sessionId: String { "\(songId)/\(userId)" }
    
    var createdAtShort: String {
        // "2025-12-19T10:00:00" -> "2025-12-19 10:00"
        let s = String(createdAt.prefix(16))
        return s.replacingOccurrences(of: "T", with: " ")
    }
}

struct HistoryListResponse: Codable {
    let ok: Bool
    let userId: String?
    let items: [HistoryItem]
    let message: String?
    
    enum CodingKeys: String, CodingKey {
        case ok
        case userId = "user_id"
        case items
        case message
    }
}

struct HistorySaveRequest: Codable {
    let commentTitle: String
    let commentBody: String
    
    let score100: Double
    let score100Strict: Double
    let score100OctaveInvariant: Double
    let octaveInvariantNow: Bool
    
    let tolCents: Double
    let percentWithinTol: Double
    let meanAbsCents: Double
    let sampleCount: Int
}

struct HistorySaveResponse: Codable {
    let ok: Bool
    let item: HistoryItem?
    let message: String?
}
// AnalysisAPI側が使ってる古い名前の互換（append = save と同じレスポンス扱い）
typealias HistoryAppendResponse = HistorySaveResponse
