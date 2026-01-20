import Foundation
import CryptoKit

enum APIError: Error, LocalizedError {
    case badURL
    case http(Int, String)
    case decode(String)
    case invalidResponse(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .badURL: return "URLが不正です"
        case .http(let code, let msg): return "HTTP \(code): \(msg)"
        case .decode(let msg): return "JSONデコード失敗: \(msg)"
        case .invalidResponse(let msg): return "不正なレスポンス: \(msg)"
        case .timeout: return "タイムアウトしました"
        }
    }
}

// ✅ convertFromSnakeCase 前提：モデルは camelCase に統一する
struct APIUploadResponse: Decodable {
    let ok: Bool
    let message: String?
    let sessionId: String?
    let songId: String?
    let userId: String?
    let takeId: String?
}

struct APIStatusResponse: Decodable {
    let ok: Bool
    let state: String?
    let message: String?
    let updatedAt: String?
    let sessionId: String?
    let songId: String?
    let userId: String?
    let takeId: String?
}

struct APIAnalyzeResponse: Decodable {
    let ok: Bool
    let message: String?
    let sessionId: String?
    let songId: String?
    let userId: String?
    let takeId: String?
}

struct APINotReadyResponse: Decodable {
    let ok: Bool
    let code: String?
    let message: String?
    let sessionId: String?
    let status: APIStatusResponse?
}

final class APIClient {
    static let shared = APIClient()
    
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
            Target > Info に
            API_BASE_URL = "http://<あなたのMacのIP>:5000"
            を追加してください。
            """)
        }
#endif
        print("✅ APIClient baseURL =", baseURL.absoluteString)
    }
    
    // ✅ snake_case -> camelCase 自動変換
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    
    // ==================================================
    // MARK: - Upload
    // POST /api/voice/<user_id>?song_id=...
    // ==================================================
    func uploadVoice(userId: String, songId: String, wavFileURL: URL) async throws -> APIUploadResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/api/voice/\(userId)?song_id=\(songId)") else {
            throw APIError.badURL
        }
        
        print("VOICE UPLOAD URL =", url.absoluteString)
        print("VOICE UPLOAD file =", wavFileURL.lastPathComponent)
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = try makeMultipartBody(boundary: boundary, fileURL: wavFileURL, fieldName: "file")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp: resp, data: data)
        
        if let http = resp as? HTTPURLResponse {
            print("VOICE UPLOAD status =", http.statusCode)
        }
        print("VOICE UPLOAD body =", String(data: data, encoding: .utf8) ?? "")
        
        return try decode(APIUploadResponse.self, from: data)
    }
    
    // ==================================================
    // MARK: - Status
    // GET /api/status/<session_id>
    // ==================================================
    func getStatus(sessionId: String) async throws -> APIStatusResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/api/status/\(sessionId)") else {
            throw APIError.badURL
        }
        
        print("STATUS URL =", url.absoluteString)
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("STATUS code =", code)
        
        try checkHTTP(resp: resp, data: data)
        return try decode(APIStatusResponse.self, from: data)
    }
    
    // ==================================================
    // MARK: - Analyze
    // POST /api/analyze/<session_id>
    // ==================================================
    func analyze(sessionId: String) async throws -> APIAnalyzeResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/api/analyze/\(sessionId)") else {
            throw APIError.badURL
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 900
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp: resp, data: data)
        return try decode(APIAnalyzeResponse.self, from: data)
    }
    
    // ==================================================
    // MARK: - Analysis
    // GET /api/analysis/<session_id>
    // ==================================================
    func getAnalysis(sessionId: String) async throws -> AnalysisResponse {
        
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = comps?.path ?? ""
        comps?.path = basePath + "/api/analysis/" + sessionId
        
        guard let url = comps?.url else {
            throw APIError.badURL
        }
        
        print("ANALYSIS URL =", url.absoluteString)
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        
        for _ in 0..<20 {
            let (data, statusCode) = try await dataWithStatus(for: req)
            print("ANALYSIS code =", statusCode)
            
            if statusCode == 202 {
                print("ANALYSIS 202 body =", String(data: data, encoding: .utf8) ?? "")
                _ = try? decode(APINotReadyResponse.self, from: data)
                try await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            
            if !(200...299).contains(statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? ""
                print("ANALYSIS error body =", msg)
                throw APIError.http(statusCode, msg)
            }
            
            let res = try decode(AnalysisResponse.self, from: data)
            return res
        }
        
        throw APIError.timeout
    }
    
    // ==================================================
    // MARK: - AI Comment
    // ==================================================
    func fetchAIComment(sessionId: String, reqBody: AICommentRequest) async throws -> AICommentResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/api/comment/\(sessionId)") else {
            throw APIError.badURL
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(reqBody)
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp: resp, data: data)
        
        if let http = resp as? HTTPURLResponse { print("AI COMMENT status =", http.statusCode) }
        print("AI COMMENT body =", String(data: data, encoding: .utf8) ?? "")
        
        return try decode(AICommentResponse.self, from: data)
    }
    
    func generateAIComment(sessionId: String) async throws -> AICommentResponse {
        try await fetchAIComment(sessionId: sessionId, reqBody: AICommentRequest())
    }
    
    // ==================================================
    // MARK: - History append / list / delete（ここは元コードのまま）
    // ==================================================
    enum CommentSource: String { case ai, rule }
    
    func appendHistory(sessionId: String, reqBody: HistorySaveRequest, commentSource: CommentSource) async throws -> HistorySaveResponse {
        let (songId, userId, _) = try splitSessionId3(sessionId)
        
        guard let url = URL(string: "\(baseURL.absoluteString)/api/history/\(songId)/\(userId)/append") else {
            throw APIError.badURL
        }
        
        let baseData = try JSONEncoder().encode(reqBody)
        let baseObjAny = try JSONSerialization.jsonObject(with: baseData, options: [])
        
        guard var baseObj = baseObjAny as? [String: Any] else {
            throw APIError.decode("HistorySaveRequest is not a JSON object")
        }
        
        baseObj["commentSource"] = commentSource.rawValue
        baseObj["comment_source"] = commentSource.rawValue
        
        let bodyData = try JSONSerialization.data(withJSONObject: baseObj, options: [])
        let idempotencyKey = Self.sha256Hex(Data((sessionId + ":").utf8) + bodyData)
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        req.setValue(commentSource.rawValue, forHTTPHeaderField: "X-Comment-Source")
        req.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                     forHTTPHeaderField: "X-App-Version")
        req.httpBody = bodyData
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp: resp, data: data)
        return try decode(HistorySaveResponse.self, from: data)
    }
    
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
        
        var comp = URLComponents(url: urlBase, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = []
        
        if let source, !source.isEmpty { items.append(.init(name: "source", value: source)) }
        if let prompt, !prompt.isEmpty { items.append(.init(name: "prompt", value: prompt)) }
        if let model,  !model.isEmpty  { items.append(.init(name: "model",  value: model)) }
        if let limit { items.append(.init(name: "limit", value: String(limit))) }
        if let offset { items.append(.init(name: "offset", value: String(offset))) }
        
        if !items.isEmpty { comp?.queryItems = items }
        
        guard let url = comp?.url else { throw APIError.badURL }
        
        print("HISTORY LIST URL =", url.absoluteString)
        
        let (data, resp) = try await URLSession.shared.data(from: url)
        try checkHTTP(resp: resp, data: data)
        
        // RAWログ（あなたが貼ってくれてるやつ）
        print("HISTORY LIST RAW =", String(data: data, encoding: .utf8) ?? "(binary)")
        
        // ✅ decodeして中身もログ
        let res = try decode(HistoryListResponse.self, from: data)
        
        if let first = res.items?.first {
            print("DECODED first.id =", first.id)
            print("DECODED first.songId =", first.songId ?? "nil")
            print("DECODED first.songTitle =", first.songTitle ?? "nil")
            print("DECODED first.title =", first.title ?? "nil")
            print("DECODED first.body =", (first.body ?? "nil").prefix(30))
            print("DECODED first.score100 =", first.score100 ?? -1)
            print("DECODED first.sessionId =", first.sessionId ?? "nil")
        } else {
            print("DECODED items is empty")
        }
        
        return res
    }

    func deleteHistory(userId: String, historyId: String) async throws -> SimpleOkResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/api/history/\(userId)/\(historyId)") else {
            throw APIError.badURL
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 60
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp: resp, data: data)
        return try decode(SimpleOkResponse.self, from: data)
    }
    
    // ==================================================
    // MARK: - Helpers
    // ==================================================
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T  {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let msg = String(data: data, encoding: .utf8) ?? "(binary)"
            throw APIError.decode("\(error)\n\(msg)")
        }
    }
    
    func checkHTTP(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.invalidResponse("no http response")
        }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, msg)
        }
    }
    
    private func dataWithStatus(for req: URLRequest) async throws -> (Data, Int) {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.invalidResponse("no http response")
        }
        return (data, http.statusCode)
    }
    
    private func makeMultipartBody(boundary: String, fileURL: URL, fieldName: String) throws -> Data {
        var body = Data()
        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
    
    private func splitSessionId3(_ sessionId: String) throws -> (songId: String, userId: String, takeId: String?) {
        let parts = sessionId.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw APIError.invalidResponse("sessionIdの形式が不正: \(sessionId)") }
        let takeId = (parts.count >= 3) ? parts[2] : nil
        return (parts[0], parts[1], takeId)
    }
    
    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
