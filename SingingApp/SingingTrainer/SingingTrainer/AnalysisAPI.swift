import Foundation
import CryptoKit

final class AnalysisAPI {
    static let shared = AnalysisAPI()
    private init() {}
    
    private let baseURL = URL(string: "http://127.0.0.1:5000")!
    
    /// 例: sessionId = "orphans/user01"
    func fetchAnalysis(sessionId: String) async throws -> AnalysisResponse {
        let url = URL(string: "\(baseURL.absoluteString)/api/analysis/\(sessionId)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "AnalysisAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        
        return try JSONDecoder().decode(AnalysisResponse.self, from: data)
    }
    
    // ----------------------------
    // AIコメント
    // ----------------------------
    
    // 呼び出し側が req: を使ってても通るように
    func fetchAIComment(sessionId: String, req: AICommentRequest) async throws -> AICommentResponse {
        try await fetchAIComment(sessionId: sessionId, reqBody: req)
    }
    
    // こちらが本体（reqBody:）
    func fetchAIComment(sessionId: String, reqBody: AICommentRequest) async throws -> AICommentResponse {
        let url = URL(string: "\(baseURL.absoluteString)/api/comment/\(sessionId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(reqBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "AnalysisAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        
        return try JSONDecoder().decode(AICommentResponse.self, from: data)
    }
    
    // ----------------------------
    // 履歴：保存（append）
    // ----------------------------
    
    /// 例: sessionId = "orphans/user01" を /api/history/<song>/<user>/append に保存
    /// Idempotency-Key を付与して二重保存を防ぐ
    func appendHistory(sessionId: String, reqBody: HistorySaveRequest) async throws -> HistorySaveResponse {
        let (songId, userId) = try splitSessionId(sessionId)
        
        let url = URL(string: "\(baseURL.absoluteString)/api/history/\(songId)/\(userId)/append")!
        
        // 送信JSONを安定的にハッシュ化（同じ内容なら同じキーになる）
        let bodyData = try JSONEncoder().encode(reqBody)
        let idempotencyKey = Self.sha256Hex(Data((sessionId + ":").utf8) + bodyData)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",forHTTPHeaderField:"X-App-Version")
        request.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "AnalysisAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        
        return try JSONDecoder().decode(HistorySaveResponse.self, from: data)
    }
    
    // ----------------------------
    // 履歴：一覧
    // ----------------------------
    func fetchHistoryList(userId: String) async throws -> HistoryListResponse {
        let url = URL(string: "\(baseURL.absoluteString)/api/history/\(userId)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "AnalysisAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        
        return try JSONDecoder().decode(HistoryListResponse.self, from: data)
    }
    
    // ----------------------------
    // 履歴：削除
    // ----------------------------
    func deleteHistory(userId: String, historyId: String) async throws -> SimpleOkResponse {
        let url = URL(string: "\(baseURL.absoluteString)/api/history/\(userId)/\(historyId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "AnalysisAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        
        return try JSONDecoder().decode(SimpleOkResponse.self, from: data)
    }
    
    // ----------------------------
    // util
    // ----------------------------
    
    private func splitSessionId(_ sessionId: String) throws -> (songId: String, userId: String) {
        let parts = sessionId.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            throw NSError(domain: "AnalysisAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "sessionIdの形式が不正です: \(sessionId)"])
        }
        return (parts[0], parts[1])
    }
    
    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
