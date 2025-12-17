import Foundation

// MARK: - API Models

struct PitchPoint: Codable {
    let t: Double
    let f0Hz: Double?
    
    enum CodingKeys: String, CodingKey {
        case t
        case f0Hz = "f0_hz"
    }
}

struct PitchTrack: Codable {
    let algo: String?
    let sr: Int?
    let hop: Int?
    let track: [PitchPoint]?
}

struct PitchEvent: Codable, Identifiable {
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

struct AnalysisSummary: Codable {
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
    let tips: String?
    
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

struct AnalysisMeta: Codable {
    struct Paths: Codable {
        let refPitch: String?
        let usrPitch: String?
        
        enum CodingKeys: String, CodingKey {
            case refPitch = "ref_pitch"
            case usrPitch = "usr_pitch"
        }
    }
    let paths: Paths?
}

struct AnalysisResponse: Codable {
    let sessionId: String?
    let userId: String?
    let events: [PitchEvent]?
    let summary: AnalysisSummary?
    let usrPitch: PitchTrack?
    let refPitch: PitchTrack?
    let meta: AnalysisMeta?
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case userId = "user_id"
        case events, summary, meta
        case usrPitch = "usr_pitch"
        case refPitch = "ref_pitch"
    }
}
