import Foundation
import CryptoKit

final class AnalysisAPI {
    static let shared = AnalysisAPI()
    
    /// ★ extension から見える必要がある
    let baseURL: URL
    
    private init()
    {
        // 1) シミュレータ: 127.0.0.1 に固定（= Mac上のFlaskへ）
#if targetEnvironment(simulator)
        if
            let s = Bundle.main.object(forInfoDictionaryKey: "SIMULATOR_API_BASE_URL") as? String,
            let u = URL(string: s)
        {
            // 必要ならシミュレータだけ別URLにしたい時用（基本は不要）
            self.baseURL = u
        } else {
            self.baseURL = URL(string: "http://127.0.0.1:5000")!
        }
        print("✅ AnalysisAPI baseURL =", baseURL.absoluteString)
        // 2) 実機: Info.plist の API_BASE_URL を必須にする（= MacのIP）
#else
        if
            let s = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            let u = URL(string: s)
        {
            self.baseURL = u
        } else {
            // ここで 127.0.0.1 を使うと必ず失敗するので、分かりやすく落とす
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
    
    /// 例: sessionId = "orphans/user01"
    func fetchAnalysis(sessionId: String) async throws -> AnalysisResponse {
        let (songId, userId) = try splitSessionId(sessionId)
        
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("analysis")
            .appendingPathComponent(songId)
            .appendingPathComponent(userId)
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"]
            )
        }
        
        // ✅ デバッグ：今は必須（原因が一発で出る）
        if let raw = String(data: data, encoding: .utf8) {
            print("ANALYSIS RAW RESPONSE:", raw)
        } else {
            print("ANALYSIS RAW RESPONSE: <non-utf8 binary>")
        }
        
        return try JSONDecoder().decode(AnalysisResponse.self, from: data)
    }

    
    // ----------------------------
    // AIコメント
    // ----------------------------
    func fetchAIComment(sessionId: String, req: AICommentRequest) async throws -> AICommentResponse {
        try await fetchAIComment(sessionId: sessionId, reqBody: req)
    }
    
    func fetchAIComment(sessionId: String, reqBody: AICommentRequest) async throws -> AICommentResponse {
        let url = URL(string: "\(baseURL.absoluteString)/api/comment/\(sessionId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(reqBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
        
        return try JSONDecoder().decode(AICommentResponse.self, from: data)
    }
    
    // ----------------------------
    // 履歴：保存（append）
    // ----------------------------
    func appendHistory(sessionId: String, reqBody: HistorySaveRequest) async throws -> HistorySaveResponse {
        let (songId, userId) = try splitSessionId(sessionId)
        let url = URL(string: "\(baseURL.absoluteString)/api/history/\(songId)/\(userId)/append")!
        
        let bodyData = try JSONEncoder().encode(reqBody)
        let idempotencyKey = Self.sha256Hex(Data((sessionId + ":").utf8) + bodyData)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.setValue(
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            forHTTPHeaderField: "X-App-Version"
        )
        request.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
        
        return try JSONDecoder().decode(HistorySaveResponse.self, from: data)
    }
    
    // ----------------------------
    // 履歴：一覧（フィルタ対応）
    // ----------------------------
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
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
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
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
        
        return try JSONDecoder().decode(SimpleOkResponse.self, from: data)
    }
    
    // ----------------------------
    // util
    // ----------------------------
    private func splitSessionId(_ sessionId: String) throws -> (songId: String, userId: String) {
        let parts = sessionId.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            throw NSError(
                domain: "AnalysisAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "sessionIdの形式が不正です: \(sessionId)"]
            )
        }
        return (parts[0], parts[1])
    }
    
    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
