import Foundation

struct GrowthHistoryItem: Identifiable, Decodable {
    let id: String
    let songId: String
    let userId: String
    
    let createdAt: String
    
    // 指標
    let score100: Double?
    let score100Strict: Double?
    let score100OctaveInvariant: Double?
    
    let meanAbsCents: Double?
    let percentWithinTol: Double?
    let tolCents: Double?
    let sampleCount: Int?
    
    // あるなら（現状のJSONには無いっぽい）
    let sessionId: String?
}
