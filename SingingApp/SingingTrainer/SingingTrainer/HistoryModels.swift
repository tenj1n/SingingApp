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
        
        case songId    = "song_id"
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
    
    enum CodingKeys: String, CodingKey {
        case ok, message, items
    }
}

// ==================================================
// MARK: - HistoryItem (single source of truth)
// ==================================================

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
        
        // サーバは comment_* を返す
        case commentSource = "comment_source"
        case commentTitle  = "comment_title"
        case commentBody   = "comment_body"
        
        // 旧/別実装保険
        case source
        case title
        case body
        
        // song meta（snake_case）
        case songId = "song_id"
        case songTitle = "song_title"
        case sessionId = "session_id"
        
        // camelCase 保険
        case songIdCamel = "songId"
        case songTitleCamel = "songTitle"
        case sessionIdCamel = "sessionId"
        
        // score / metrics（snake_case）
        case score100 = "score100"
        case score100StrictSnake = "score100_strict"
        case score100OctaveInvariantSnake = "score100_octave_invariant"
        case meanAbsCentsSnake = "mean_abs_cents"
        case percentWithinTolSnake = "percent_within_tol"
        case sampleCountSnake = "sample_count"
        
        // score / metrics（camelCase 保険）
        case score100StrictCamel = "score100Strict"
        case score100OctaveInvariantCamel = "score100OctaveInvariant"
        case meanAbsCentsCamel = "meanAbsCents"
        case percentWithinTolCamel = "percentWithinTol"
        case sampleCountCamel = "sampleCount"
    }
    
    // ✅ throws しても nil 扱いにする（ここが超重要）
    private static func decodeIfPresentSafe<T: Decodable>(
        _ type: T.Type,
        _ c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> T? {
        return (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try c.decode(String.self, forKey: .id)
        createdAt = Self.decodeIfPresentSafe(String.self, c, forKey: .createdAt)
        
        let cs = Self.decodeIfPresentSafe(String.self, c, forKey: .commentSource)
        let ct = Self.decodeIfPresentSafe(String.self, c, forKey: .commentTitle)
        let cb = Self.decodeIfPresentSafe(String.self, c, forKey: .commentBody)
        
        source = cs ?? Self.decodeIfPresentSafe(String.self, c, forKey: .source)
        title  = ct ?? Self.decodeIfPresentSafe(String.self, c, forKey: .title)
        body   = cb ?? Self.decodeIfPresentSafe(String.self, c, forKey: .body)
        
        songId =
        Self.decodeIfPresentSafe(String.self, c, forKey: .songId)
        ?? Self.decodeIfPresentSafe(String.self, c, forKey: .songIdCamel)
        
        songTitle =
        Self.decodeIfPresentSafe(String.self, c, forKey: .songTitle)
        ?? Self.decodeIfPresentSafe(String.self, c, forKey: .songTitleCamel)
        
        sessionId =
        Self.decodeIfPresentSafe(String.self, c, forKey: .sessionId)
        ?? Self.decodeIfPresentSafe(String.self, c, forKey: .sessionIdCamel)
        
        score100 = Self.decodeIfPresentSafe(Double.self, c, forKey: .score100)
        
        score100Strict =
        Self.decodeIfPresentSafe(Double.self, c, forKey: .score100StrictSnake)
        ?? Self.decodeIfPresentSafe(Double.self, c, forKey: .score100StrictCamel)
        
        score100OctaveInvariant =
        Self.decodeIfPresentSafe(Double.self, c, forKey: .score100OctaveInvariantSnake)
        ?? Self.decodeIfPresentSafe(Double.self, c, forKey: .score100OctaveInvariantCamel)
        
        meanAbsCents =
        Self.decodeIfPresentSafe(Double.self, c, forKey: .meanAbsCentsSnake)
        ?? Self.decodeIfPresentSafe(Double.self, c, forKey: .meanAbsCentsCamel)
        
        percentWithinTol =
        Self.decodeIfPresentSafe(Double.self, c, forKey: .percentWithinTolSnake)
        ?? Self.decodeIfPresentSafe(Double.self, c, forKey: .percentWithinTolCamel)
        
        sampleCount =
        Self.decodeIfPresentSafe(Int.self, c, forKey: .sampleCountSnake)
        ?? Self.decodeIfPresentSafe(Int.self, c, forKey: .sampleCountCamel)
    }
}

// ==================================================
// MARK: - Simple Ok
// ==================================================

struct SimpleOkResponse: Decodable {
    let ok: Bool?
    let message: String?
}
