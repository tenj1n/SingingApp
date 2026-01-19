import Foundation

// ==================================================
// MARK: - AI Comment Models
// ==================================================

struct AICommentRequest: Encodable {
    var promptVersion: String? = nil
    var model: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case promptVersion = "prompt_version"
        case model
    }
}

struct AICommentResponse: Decodable {
    let ok: Bool?
    let title: String?
    let body: String?
    let model: String?
    let promptVersion: String?
    
    enum CodingKeys: String, CodingKey {
        case ok, title, body, model
        case promptVersion = "prompt_version"
    }
}

// ==================================================
// MARK: - History Save / List / Delete Models
// ==================================================

import Foundation

struct HistorySaveRequest: Encodable {
    var title: String
    var body: String
    
    var score100: Double? = nil
    var score100Strict: Double? = nil
    var score100OctaveInvariant: Double? = nil
    var meanAbsCents: Double? = nil
    var percentWithinTol: Double? = nil
    var sampleCount: Int? = nil
    
    enum CodingKeys: String, CodingKey {
        // ✅ サーバが欲しいキーに合わせる
        case title = "commentTitle"
        case body  = "commentBody"
        
        // ✅ snake_case はそのまま維持（サーバ側が snake_case っぽいので）
        case score100 = "score100"
        case score100Strict = "score100_strict"
        case score100OctaveInvariant = "score100_octave_invariant"
        case meanAbsCents = "mean_abs_cents"
        case percentWithinTol = "percent_within_tol"
        case sampleCount = "sample_count"
    }
}

struct HistorySaveResponse: Decodable {
    let ok: Bool?
    let message: String?
    let historyId: String?
    
    enum CodingKeys: String, CodingKey {
        case ok, message
        case historyId = "history_id"
    }
}

struct HistoryListResponse: Decodable {
    let ok: Bool?
    let message: String?
    let items: [HistoryItem]?   // ✅ 配列
    
    struct HistoryItem: Decodable, Identifiable {
        let id: String
        let songId: String?
        let createdAt: String?
        let source: String?
        let title: String?
        let body: String?
        
        let score100: Double?
        let score100Strict: Double?
        let score100OctaveInvariant: Double?
        let meanAbsCents: Double?
        let percentWithinTol: Double?
        let sampleCount: Int?
        
        let sessionId: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case songId = "song_id"
            case createdAt = "created_at"
            case source, title, body
            
            case score100 = "score100"
            case score100Strict = "score100_strict"
            case score100OctaveInvariant = "score100_octave_invariant"
            case meanAbsCents = "mean_abs_cents"
            case percentWithinTol = "percent_within_tol"
            case sampleCount = "sample_count"
            
            case sessionId = "session_id"
        }
    }
}

struct SimpleOkResponse: Decodable {
    let ok: Bool?
    let message: String?
}
