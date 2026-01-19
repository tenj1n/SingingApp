import Foundation

// ==================================================
// MARK: - AnalysisResponse
// ==================================================

struct AnalysisResponse: Decodable {
    let ok: Bool?
    let sessionId: String?
    let songId: String?
    let userId: String?
    
    let refPitch: PitchTrack?
    let usrPitch: PitchTrack?
    let events: [PitchEvent]?
    let summary: AnalysisSummary?
    let meta: Meta?
    
    struct Meta: Decodable {
        let paths: [String: String]?
    }
    
    enum CodingKeys: String, CodingKey {
        case ok
        case sessionId = "session_id"
        case songId = "song_id"
        case userId = "user_id"
        case refPitch = "ref_pitch"
        case usrPitch = "usr_pitch"
        case events
        case summary
        case meta
    }
}
extension AnalysisResponse {
    
    /// usrPitch.track の総数（nil含む。配列の長さ）
    var totalSampleCount: Int {
        usrPitch?.track.count ?? 0
    }
    
    /// usrPitch.track のうち f0Hz が入ってる数（=有効サンプル）
    var effectiveSampleCount: Int {
        guard let t = usrPitch?.track else { return 0 }
        return t.reduce(into: 0) { acc, p in
            if p.f0Hz != nil { acc += 1 }
        }
    }
    
    /// ref のほうも見たいなら
    var refTotalSampleCount: Int {
        refPitch?.track.count ?? 0
    }
    
    var refEffectiveSampleCount: Int {
        guard let t = refPitch?.track else { return 0 }
        return t.reduce(into: 0) { acc, p in
            if p.f0Hz != nil { acc += 1 }
        }
    }
}

struct AnalysisSummary: Decodable {
    let verdict: String?
    let reason: String?
    let tips: [String]?
    let tolCents: Double?
    
    enum CodingKeys: String, CodingKey {
        case verdict, reason, tips
        case tolCents = "tol_cents"
    }
}

// ==================================================
// MARK: - Pitch Track
// ==================================================

struct PitchTrack: Decodable {
    let algo: String?
    let sr: Int?
    let hop: Int?
    let frameLen: Int?
    
    /// ✅ ここが重要：どんな形で来ても最終的に 1次元 [PitchPoint] にして持つ
    let track: [PitchPoint]
    
    /// サーバが debug を返しても壊れないように受け口だけ用意
    let debug: JSONValue?
    
    enum CodingKeys: String, CodingKey {
        case algo, sr, hop, track, debug
        case frameLen = "frame_len"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        algo = try? c.decode(String.self, forKey: .algo)
        sr = try? c.decode(Int.self, forKey: .sr)
        hop = try? c.decode(Int.self, forKey: .hop)
        frameLen = try? c.decode(Int.self, forKey: .frameLen)
        debug = try? c.decode(JSONValue.self, forKey: .debug)
        
        // 1) 通常：[{...},{...}]
        if let points = try? c.decode([PitchPoint].self, forKey: .track) {
            track = points
            return
        }
        
        // 2) たまに：[[{...},{...}]] みたいに二重で包まれる
        if let nested = try? c.decode([[PitchPoint]].self, forKey: .track) {
            track = nested.flatMap { $0 }
            return
        }
        
        // 3) さらに変形：[[t,f0]...] or [[[...]]] 等が来ても落ちないように最後は空配列
        //    (PitchPoint は配列形式も decode できるようにしてる)
        if let nested2 = try? c.decode([[[PitchPoint]]].self, forKey: .track) {
            track = nested2.flatMap { $0 }.flatMap { $0 }
            return
        }
        
        track = []
    }
}

struct PitchPoint: Decodable {
    let t: Double?
    let f0Hz: Double?
    
    enum CodingKeys: String, CodingKey {
        case t
        case f0Hz = "f0_hz"
    }
    
    init(t: Double?, f0Hz: Double?) {
        self.t = t
        self.f0Hz = f0Hz
    }
    
    init(from decoder: Decoder) throws {
        // A) 通常：{"t":..., "f0_hz":...}
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            let t = try? c.decodeIfPresent(Double.self, forKey: .t)
            let f0 = try? c.decodeIfPresent(Double.self, forKey: .f0Hz)
            self.init(t: t, f0Hz: f0)
            return
        }
        
        // B) 変形： [t, f0] または [f0, t] みたいな配列で来るケースを救う
        var u = try decoder.unkeyedContainer()
        let a = try? u.decodeIfPresent(Double.self) // 1つ目
        let b = try? u.decodeIfPresent(Double.self) // 2つ目
        
        // 推定：t は通常 0〜数百秒、f0 は 0〜1000Hz くらい
        // a が 50 より大きければ f0 っぽい、そうでなければ t っぽい…という雑な推定
        if let a, a > 50 {
            // [f0, t]
            self.init(t: b, f0Hz: a)
        } else {
            // [t, f0]
            self.init(t: a, f0Hz: b)
        }
    }
}

struct PitchEvent: Decodable, Identifiable {
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

// ==================================================
// MARK: - JSONValue (debug用：Any対応)
// ==================================================

enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        
        self = .null
    }
}
