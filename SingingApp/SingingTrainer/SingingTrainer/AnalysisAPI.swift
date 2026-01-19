/*import Foundation
import CryptoKit

final class AnalysisAPI {
    static let shared = AnalysisAPI()
    
    /// ★ extension から見える必要がある
    let baseURL: URL
    
    private init() {
#if targetEnvironment(simulator)
        if
            let s = Bundle.main.object(forInfoDictionaryKey: "SIMULATOR_API_BASE_URL") as? String,
            let u = URL(string: s)
        {
            self.baseURL = u
        } else {
            self.baseURL = URL(string: "https://singingtrainer.fly.dev")!
        }
#else
        if
            let s = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            let u = URL(string: s)
        {
            self.baseURL = u
        } else {
            fatalError("""
            API_BASE_URL が Info.plist にありません。
            実機で動かすには Target > Info に
            API_BASE_URL = "http://<あなたのMacのIP>:5000"
            を追加してください。
            """)
        }
#endif
        print("✅ AnalysisAPI baseURL =", baseURL.absoluteString)
    }
    
    // ==================================================
    // API: analysis
    // GET /api/analysis/<session_id>   ※ session_id は path
    // ==================================================
    func fetchAnalysis(sessionId: String) async throws -> AnalysisResponse {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // sessionId の "/" を含むので、サーバ側の <path:session_id> へそのまま渡す
        let url = URL(string: "\(base)/api/analysis/\(sessionId)")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"]
            )
        }
        
        if let raw = String(data: data, encoding: .utf8) {
            print("ANALYSIS RAW RESPONSE:", raw)
        } else {
            print("ANALYSIS RAW RESPONSE: <non-utf8 binary>")
        }
        
        return try JSONDecoder().decode(AnalysisResponse.self, from: data)
    }
    
    // ==================================================
    // API: AI comment
    // POST /api/comment/<session_id>
    // ==================================================
    func fetchAIComment(sessionId: String, reqBody: AICommentRequest) async throws -> AICommentResponse {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(base)/api/comment/\(sessionId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(reqBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse {
            print("AI COMMENT status =", http.statusCode)
        }
        if let text = String(data: data, encoding: .utf8) {
            print("AI COMMENT body =", text)
        }
        
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"]
            )
        }
        
        return try JSONDecoder().decode(AICommentResponse.self, from: data)
    }
    
    // ==================================================
    // API: history append
    // POST /api/history/<song_id>/<user_id>/append
    // ==================================================
    enum CommentSource: String {
        case ai
        case rule
    }
    
    func appendHistory(
        sessionId: String,
        reqBody: HistorySaveRequest,
        commentSource: CommentSource
    ) async throws -> HistorySaveResponse {
        
        // song/user/take でも song/user でもOK（song,user だけ必要）
        let (songId, userId, _) = try splitSessionId3(sessionId)
        
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(base)/api/history/\(songId)/\(userId)/append")!
        
        print("HISTORY APPEND URL:", url.absoluteString)
        
        let bodyData = try JSONEncoder().encode(reqBody)
        
        // idempotency: sessionId + body で安定
        let idempotencyKey = Self.sha256Hex(Data((sessionId + ":").utf8) + bodyData)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        
        request.setValue(commentSource.rawValue, forHTTPHeaderField: "X-Comment-Source")
        
        request.setValue(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            forHTTPHeaderField: "X-App-Version"
        )
        
        request.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse {
            print("HISTORY APPEND status =", http.statusCode)
        }
        if let text = String(data: data, encoding: .utf8) {
            print("HISTORY APPEND body =", text)
        }
        
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"]
            )
        }
        
        return try JSONDecoder().decode(HistorySaveResponse.self, from: data)
    }
    
    // ==================================================
    // API: history list (filters)
    // GET /api/history/<user_id>?source=...&prompt=...&model=...
    // ==================================================
    func fetchHistoryList(
        userId: String,
        source: String? = nil,
        prompt: String? = nil,
        model: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> HistoryListResponse {
        
        let urlBase = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("history")
            .appendingPathComponent(userId)
        
        var components = URLComponents(url: urlBase, resolvingAgainstBaseURL: false)
        var q: [URLQueryItem] = []
        
        if let source, !source.isEmpty { q.append(.init(name: "source", value: source)) }
        if let prompt, !prompt.isEmpty { q.append(.init(name: "prompt", value: prompt)) }
        if let model, !model.isEmpty { q.append(.init(name: "model", value: model)) }
        if let limit { q.append(.init(name: "limit", value: String(limit))) }
        if let offset { q.append(.init(name: "offset", value: String(offset))) }
        
        if !q.isEmpty { components?.queryItems = q }
        
        guard let url = components?.url else {
            throw NSError(
                domain: "AnalysisAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "URLの生成に失敗しました"]
            )
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"]
            )
        }
        
        return try JSONDecoder().decode(HistoryListResponse.self, from: data)
    }
    
    // ==================================================
    // API: history delete
    // DELETE /api/history/<user_id>/<history_id>
    // ==================================================
    func deleteHistory(userId: String, historyId: String) async throws -> SimpleOkResponse {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(base)/api/history/\(userId)/\(historyId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"]
            )
        }
        
        return try JSONDecoder().decode(SimpleOkResponse.self, from: data)
    }
    
    // ==================================================
    // util
    // ==================================================
    /// sessionId:
    /// - "song/user"
    /// - "song/user/take"
    private func splitSessionId3(_ sessionId: String) throws -> (songId: String, userId: String, takeId: String?) {
        let parts = sessionId.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            throw NSError(
                domain: "AnalysisAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "sessionIdの形式が不正です: \(sessionId)"]
            )
        }
        let takeId = (parts.count >= 3) ? parts[2] : nil
        return (parts[0], parts[1], takeId)
    }
    
    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
*/
