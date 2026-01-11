import Foundation

extension AnalysisAPI {
    
    /// ユーザ歌声（WAV）をサーバにアップロードして session_id を受け取る
    /// 例: POST /api/voice/user01?song_id=orpheus
    func uploadUserVoice(userId: String, songId: String, wavFileURL: URL) async throws -> VoiceUploadResponse {
        
        // /api/voice/{userId} に song_id をクエリで付与
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/voice/\(userId)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "song_id", value: songId)
        ]
        guard let endpoint = components?.url else {
            throw URLError(.badURL)
        }
        
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // 重いファイル読み込みはバックグラウンドで
        let fileData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: wavFileURL)
        }.value
        
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(wavFileURL.lastPathComponent)\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        
        req.httpBody = body
        
        let (data, res) = try await URLSession.shared.data(for: req)
        
        // HTTPステータスチェック
        if let http = res as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw URLError(
                .badServerResponse,
                userInfo: ["status": http.statusCode, "body": text]
            )
        }
        
        // デバッグ用（今は必須）
        if let raw = String(data: data, encoding: .utf8) {
            print("UPLOAD RAW RESPONSE:", raw)
        }
        
        return try JSONDecoder().decode(VoiceUploadResponse.self, from: data)
    }
}
