import Foundation

// ==================================================
// MARK: - History Save / List / Delete Models
// ==================================================

struct HistorySaveRequest: Encodable {
    
    // 保存するコメント
    var commentTitle: String
    var commentBody: String
    
    // 履歴で必要なメタ
    var songId: String
    var songTitle: String
    var sessionId: String
    
    // スコア系（任意）
    var score100: Double? = nil
    var score100Strict: Double? = nil
    var score100OctaveInvariant: Double? = nil
    var meanAbsCents: Double? = nil
    var percentWithinTol: Double? = nil
    var sampleCount: Int? = nil
    
    enum CodingKeys: String, CodingKey {
        case commentTitle = "commentTitle"
        case commentBody  = "commentBody"
        
        case songId = "song_id"
        case songTitle = "song_title"
        case sessionId = "session_id"
        
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
    let items: [HistoryItem]?
    
    // ✅ ここが重要：他ファイルが HistoryListResponse.HistoryItem を参照してても壊れない
    struct HistoryItem: Decodable, Identifiable {
        let id: String
        let createdAt: String?
        
        let source: String?
        let title: String?
        let body: String?
        
        let songId: String?
        let songTitle: String?
        let sessionId: String?
        
        let score100: Double?
        let score100Strict: Double?
        let score100OctaveInvariant: Double?
        let meanAbsCents: Double?
        let percentWithinTol: Double?
        let sampleCount: Int?
        
        enum CodingKeys: String, CodingKey {
            case id
            case createdAt = "created_at"
            
            case source
            case title
            case body
            
            case songId = "song_id"
            case songTitle = "song_title"
            case sessionId = "session_id"
            
            case score100 = "score100"
            case score100Strict = "score100_strict"
            case score100OctaveInvariant = "score100_octave_invariant"
            case meanAbsCents = "mean_abs_cents"
            case percentWithinTol = "percent_within_tol"
            case sampleCount = "sample_count"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case ok
        case message
        case items
    }
    
    // ✅ items は配列なので [HistoryItem].self で decodeIfPresent
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
        self.message = try c.decodeIfPresent(String.self, forKey: .message)
        self.items = try c.decodeIfPresent([HistoryItem].self, forKey: .items)
    }
}

// 他のファイルで「HistoryItem」単体で使いたい場合のショートカット（任意）
typealias HistoryItem = HistoryListResponse.HistoryItem

struct SimpleOkResponse: Decodable {
    let ok: Bool?
    let message: String?
}
