import Foundation

// MARK: - Pitch

/// サーバの pitch track は t が null の可能性もゼロではないので Optional に寄せる（安全側）
struct PitchPoint: Decodable {
    let t: Double?
    let f0Hz: Double?
    
    enum CodingKeys: String, CodingKey {
        case t
        case f0Hz = "f0_hz"
    }
}

struct PitchTrack: Decodable {
    let algo: String?   // null 対応
    let sr: Int?        // null 対応
    let hop: Int?       // null 対応
    let track: [PitchPoint]?
}

struct PitchEvent: Decodable, Identifiable {
    /// JSONには無いので decode 対象外（CodingKeysに入れない）
    let id = UUID()
    
    let start: Double?
    let end: Double?
    let type: String?
    let avgCents: Double?
    let maxCents: Double?
    
    enum CodingKeys: String, CodingKey {
        case start, end, type
        case avgCents = "avg_cents"
        case maxCents = "max_cents"
    }
}

// MARK: - Summary / Meta

/// ✅ 今サーバが返している summary 形式に合わせる
/// - tips: [String]（あなたのログは配列）
/// - tol_cents などはそのまま
///
/// ※ 将来スコア系（percentWithinTol 等）を追加しても Optional なので壊れにくい
struct AnalysisSummary: Decodable {
    let tolCents: Double?
    let frames: Int?
    let seconds: Double?
    
    let meanCents: Double?
    let medianCents: Double?
    let stdCents: Double?
    
    let percentWithinTol: Double?
    let percentLow: Double?
    let percentHigh: Double?
    
    let p10Cents: Double?
    let p90Cents: Double?
    
    let unvoicedMissSeconds: Double?
    
    let verdict: String?
    let reason: String?
    
    /// ✅ ここが旧モデルと違う：配列
    let tips: [String]?
    
    enum CodingKeys: String, CodingKey {
        case tolCents = "tol_cents"
        case frames, seconds
        case meanCents = "mean_cents"
        case medianCents = "median_cents"
        case stdCents = "std_cents"
        case percentWithinTol = "percent_within_tol"
        case percentLow = "percent_low"
        case percentHigh = "percent_high"
        case p10Cents = "p10_cents"
        case p90Cents = "p90_cents"
        case unvoicedMissSeconds = "unvoiced_miss_seconds"
        case verdict, reason, tips
    }
}

/// meta.counts が辞書っぽい構造なので型を用意
struct AnalysisCounts: Decodable {
    let events: Int?
    let refTrack: Int?
    let usrTrack: Int?
    
    enum CodingKeys: String, CodingKey {
        case events
        case refTrack = "ref_track"
        case usrTrack = "usr_track"
    }
}

struct AnalysisMeta: Decodable {
    /// ✅ サーバは paths を「任意キーの辞書」で返している
    let paths: [String: String]?
    let counts: AnalysisCounts?
}

// MARK: - AnalysisResponse

/// ✅ /api/analysis の現行レスポンスに合わせる
/// あなたのログには ok / session_id / song_id / user_id / ref_pitch / usr_pitch / events / summary / meta がある
struct AnalysisResponse: Decodable {
    let ok: Bool
    let message: String?
    
    let sessionId: String?
    let songId: String?
    let userId: String?
    
    let events: [PitchEvent]?
    let summary: AnalysisSummary?
    
    let usrPitch: PitchTrack?
    let refPitch: PitchTrack?
    
    let meta: AnalysisMeta?
    
    enum CodingKeys: String, CodingKey {
        case ok
        case message
        
        case sessionId = "session_id"
        case songId = "song_id"
        case userId = "user_id"
        
        case events
        case summary
        
        case usrPitch = "usr_pitch"
        case refPitch = "ref_pitch"
        
        case meta
    }
}

// MARK: - AI Comment

struct AICommentResponse: Decodable {
    let ok: Bool
    let title: String?
    let body: String?
    let message: String?
}

struct AICommentRequest: Encodable {
    let stats: AICommentStats
}

struct AICommentStats: Encodable {
    let tolCents: Double
    let percentWithinTol: Double
    let meanAbsCents: Double
    let sampleCount: Int
    let scoreStrict: Double
    let scoreOctaveInvariant: Double
    let octaveInvariantNow: Bool
}
