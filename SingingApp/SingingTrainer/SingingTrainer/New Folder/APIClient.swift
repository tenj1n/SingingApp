import Foundation

// ✅ 既存型と衝突しないように API*** に統一する

struct APIUploadResponse: Decodable {
    let ok: Bool
    let message: String?
    let session_id: String?
    let song_id: String?
    let user_id: String?
    let take_id: String?
}

struct APIStatusResponse: Decodable {
    let ok: Bool
    let state: String?       // queued / running / done / error / unknown
    let message: String?
    let updated_at: String?
    let session_id: String?
    let song_id: String?
    let user_id: String?
    let take_id: String?
}

struct APIAnalyzeResponse: Decodable {
    let ok: Bool
    let message: String?
    let session_id: String?
    let song_id: String?
    let user_id: String?
    let take_id: String?
}

// ✅ AnalysisResponse も既存と衝突しているので別名にする
// 注意：PitchPoint/PitchTrack/PitchEvent を既にプロジェクト内で持ってるなら、
// ここで定義しない方が良い。
// ただし、取得だけは必要なので最小限で “API***” として定義しておく。
struct APIAnalysisResponse: Decodable {
    let ok: Bool
    let session_id: String
    let song_id: String
    let user_id: String
    let events: [APIPitchEvent]?
    let ref_pitch: APIPitchTrack?
    let usr_pitch: APIPitchTrack?
    let summary: APISummary?
    
    struct APISummary: Decodable {
        let verdict: String?
        let reason: String?
        let tips: [String]?
        let tol_cents: Double?
    }
}

struct APIPitchPoint: Decodable {
    let t: Double?
    let f0_hz: Double?
}

struct APIPitchTrack: Decodable {
    let algo: String?
    let sr: Int?
    let hop: Int?
    let frame_len: Int?
    let track: [APIPitchPoint]?
}

struct APIPitchEvent: Decodable, Identifiable {
    let id = UUID()
    let start: Double?
    let end: Double?
    let type: String?
    let avg_cents: Double?
    let max_cents: Double?
    private enum CodingKeys: String, CodingKey { case start, end, type, avg_cents, max_cents }
}

struct APINotReadyResponse: Decodable {
    let ok: Bool
    let code: String?
    let message: String?
    let session_id: String?
    let status: APIStatusResponse?
}

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

final class APIClient {
    static let shared = APIClient()
    private init() {}
    
    // 例: https://singingtrainer.fly.dev
    private let baseURL = URL(string: "https://singingtrainer.fly.dev")!
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        //d.keyDecodingStrategy = .convertFromSnakeCase
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()
    
    // MARK: - Upload
    func uploadVoice(userId: String, songId: String, wavFileURL: URL) async throws -> APIUploadResponse {
        // ✅ baseURL は URL 型なので absoluteString を使うのが安全
        guard let url = URL(string: "\(baseURL.absoluteString)/api/voice/\(userId)?song_id=\(songId)") else {
            throw APIError.badURL
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = try makeMultipartBody(boundary: boundary, fileURL: wavFileURL, fieldName: "file")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp: resp, data: data)
        return try decode(APIUploadResponse.self, from: data)
    }
    
    // MARK: - Status
    func getStatus(sessionId: String) async throws -> APIStatusResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/api/status/\(sessionId)") else {
            throw APIError.badURL
        }
        
        print("STATUS URL =", url.absoluteString)   // ✅ 追加
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("STATUS code =", code)                // ✅ 追加
        
        try checkHTTP(resp: resp, data: data)
        return try decode(APIStatusResponse.self, from: data)
    }
    
    // MARK: - Analyze
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
    
    // MARK: - Analysis
    func getAnalysis(sessionId: String) async throws -> AnalysisResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/api/analysis/\(sessionId)") else {
            throw APIError.badURL
        }
        
        print("ANALYSIS URL =", url.absoluteString) // ✅ 追加
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 60
        
        // ✅ done直後に一瞬 NOT_READY(202) が混ざっても耐える
        for _ in 0..<20 { // 最大 ~10秒（0.5s * 20）
            let (data, statusCode) = try await dataWithStatus(for: req)
            print("ANALYSIS code =", statusCode)    // ✅ 追加
            
            if statusCode == 202 {
                // ここで body を出すと原因が見える
                print("ANALYSIS 202 body =", String(data: data, encoding: .utf8) ?? "")
                // NOT_READY を読む（ログ用。無くてもOK）
                _ = try? decode(APINotReadyResponse.self, from: data)
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                continue
            }
            
            if !(200...299).contains(statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? ""
                print("ANALYSIS error body =", msg) // ✅ 追加
                throw APIError.http(statusCode, msg)
            }
            // --- DEBUG: raw JSON shape check ---
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("ANALYSIS top keys =", obj.keys.sorted())
                print("ANALYSIS has ref_pitch =", obj["ref_pitch"] != nil)
                print("ANALYSIS has usr_pitch =", obj["usr_pitch"] != nil)
                
                if let rp = obj["ref_pitch"] {
                    print("ref_pitch type =", type(of: rp))
                    if let d = rp as? [String: Any] {
                        print("ref_pitch keys =", d.keys.sorted())
                        if let tr = d["track"] as? [Any] { print("ref_pitch.track count =", tr.count) }
                    }
                } else {
                    print("ref_pitch is MISSING")
                }
                
                if let up = obj["usr_pitch"] {
                    print("usr_pitch type =", type(of: up))
                    if let d = up as? [String: Any] {
                        print("usr_pitch keys =", d.keys.sorted())
                        if let tr = d["track"] as? [Any] { print("usr_pitch.track count =", tr.count) }
                    }
                } else {
                    print("usr_pitch is MISSING")
                }
            } else {
                let s = String(data: data, encoding: .utf8) ?? "(binary)"
                print("ANALYSIS raw prefix =", String(s.prefix(600)))
            }
            // --- /DEBUG ---
            // ✅ ここだけ既存型に変更
            return try decode(AnalysisResponse.self, from: data)
        }
        
        throw APIError.timeout
    }
    
    // MARK: - Poll helper
    func pollStatusUntilDone(
        sessionId: String,
        intervalSec: Double = 1.5,
        timeoutSec: Double = 900
    ) async throws -> APIStatusResponse {
        
        let start = Date()
        while true {
            let s = try await getStatus(sessionId: sessionId)
            let state = (s.state ?? "unknown").lowercased()
            
            if state == "done" { return s }
            if state == "error" {
                throw APIError.invalidResponse("status=error: \(s.message ?? "")")
            }
            
            if Date().timeIntervalSince(start) > timeoutSec {
                throw APIError.timeout
            }
            try await Task.sleep(nanoseconds: UInt64(intervalSec * 1_000_000_000))
        }
    }
    
    // MARK: - helpers
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let msg = String(data: data, encoding: .utf8) ?? "(binary)"
            throw APIError.decode("\(error)\n\(msg)")
        }
    }
    
    private func checkHTTP(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.invalidResponse("no http response")
        }
        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, msg)
        }
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
    
    private func dataWithStatus(for req: URLRequest) async throws -> (Data, Int) {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.invalidResponse("no http response")
        }
        return (data, http.statusCode)
    }
}
