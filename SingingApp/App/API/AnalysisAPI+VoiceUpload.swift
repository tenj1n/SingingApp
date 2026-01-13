import Foundation

extension AnalysisAPI {
    
    func uploadUserVoice(userId: String, songId: String, wavFileURL: URL) async throws -> VoiceUploadResponse {
        
        // /api/voice/{userId}?song_id=...
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/voice/\(userId)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "song_id", value: songId)]
        
        guard let endpoint = components?.url else {
            throw URLError(.badURL)
        }
        
        print("VOICE UPLOAD URL =", endpoint.absoluteString)
        print("VOICE UPLOAD file =", wavFileURL.lastPathComponent)
        
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // ファイル読み込み
        let fileData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: wavFileURL)
        }.value
        print("VOICE UPLOAD bytes =", fileData.count)
        
        // multipart body
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
        
        // ✅ ここが最重要：常に出す
        if let http = res as? HTTPURLResponse {
            print("VOICE UPLOAD status =", http.statusCode)
        } else {
            print("VOICE UPLOAD response = (non-http)")
        }
        
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("VOICE UPLOAD body =", text)
        
        // HTTPステータスチェック（body を含めて投げる）
        if let http = res as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "AnalysisAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"]
            )
        }
        
        return try JSONDecoder().decode(VoiceUploadResponse.self, from: data)
    }
}
