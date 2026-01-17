import Foundation

// MARK: - Pitch

/// サーバの pitch track は t が null の可能性もゼロではないので Optional に寄せる（安全側）
struct PitchPoint: Decodable {
    let t: Double?
    let f0Hz: Double?
    
    init(t: Double?, f0Hz: Double?) {
        self.t = t
        self.f0Hz = f0Hz
    }
    
    enum CodingKeys: String, CodingKey { case t; case f0Hz = "f0_hz" }
    
    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            self.t = try c.decodeIfPresent(Double.self, forKey: .t)
            self.f0Hz = try c.decodeIfPresent(Double.self, forKey: .f0Hz)
            return
        }
        var u = try decoder.unkeyedContainer()
        self.t = u.isAtEnd ? nil : try u.decode(Double?.self)
        self.f0Hz = u.isAtEnd ? nil : try u.decode(Double?.self)
    }
}

enum JSONAny: Decodable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONAny])
    case object([String: JSONAny])
    
    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if c.decodeNil() { self = .null; return }
            if let v = try? c.decode(Bool.self) { self = .bool(v); return }
            if let v = try? c.decode(Int.self) { self = .int(v); return }
            if let v = try? c.decode(Double.self) { self = .double(v); return }
            if let v = try? c.decode(String.self) { self = .string(v); return }
        }
        if var a = try? decoder.unkeyedContainer() {
            var arr: [JSONAny] = []
            while !a.isAtEnd { arr.append(try a.decode(JSONAny.self)) }
            self = .array(arr)
            return
        }
        let o = try decoder.container(keyedBy: AnyKey.self)
        var dict: [String: JSONAny] = [:]
        for k in o.allKeys { dict[k.stringValue] = try o.decode(JSONAny.self, forKey: k) }
        self = .object(dict)
    }
    
    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        case .string(let s): return Double(s)
        default: return nil
        }
    }
    
    private struct AnyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? = nil
        init?(intValue: Int) { return nil }
    }
}

struct PitchTrack: Decodable {
    let algo: String?
    let sr: Int?
    let hop: Int?
    let track: [PitchPoint]?
    
    enum CodingKeys: String, CodingKey { case algo, sr, hop, track }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.algo = try c.decodeIfPresent(String.self, forKey: .algo)
        self.sr   = try c.decodeIfPresent(Int.self, forKey: .sr)
        self.hop  = try c.decodeIfPresent(Int.self, forKey: .hop)
        
        // track は形がブレるので “生のJSON” として取る
        if let raw = try? c.decodeIfPresent(JSONAny.self, forKey: .track) {
            self.track = PitchTrack.parseTrack(raw)
        } else {
            self.track = nil
        }
    }
    
    // track の JSON を [PitchPoint] に正規化
    private static func parseTrack(_ raw: JSONAny) -> [PitchPoint]? {
        // 1) [ {t,f0_hz}, ... ] or [ [t,f0], ... ]
        if case .array(let arr) = raw {
            // 2次元の可能性： [[...],[...]] なら平坦化
            let flattened: [JSONAny]
            if arr.count > 0, case .array = arr[0] {
                flattened = arr.flatMap { item -> [JSONAny] in
                    if case .array(let inner) = item { return inner }
                    return [item]
                }
            } else {
                flattened = arr
            }
            
            let points: [PitchPoint] = flattened.compactMap { item in
                // dict形式
                if case .object(let obj) = item {
                    let t = obj["t"]?.doubleValue
                    let f0 = (obj["f0_hz"] ?? obj["f0Hz"])?.doubleValue
                    return PitchPoint(t: t, f0Hz: f0)
                }
                // [t,f0]形式
                if case .array(let pair) = item {
                    let t = pair.count > 0 ? pair[0].doubleValue : nil
                    let f0 = pair.count > 1 ? pair[1].doubleValue : nil
                    return PitchPoint(t: t, f0Hz: f0)
                }
                return nil
            }
            return points
        }
        return nil
    }
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
