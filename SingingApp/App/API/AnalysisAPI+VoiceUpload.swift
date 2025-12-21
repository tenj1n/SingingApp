import Foundation

extension AnalysisAPI {
    
    /// ユーザ歌声（WAV）をサーバにアップロードして、比較に使う session_id を受け取る
    func uploadUserVoice(userId: String, wavFileURL: URL) async throws -> VoiceUploadResponse {
        
        let endpoint = baseURL.appendingPathComponent("/api/voice/\(userId)")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let fileData = try Data(contentsOf: wavFileURL)
        
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(wavFileURL.lastPathComponent)\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        
        req.httpBody = body
        
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(VoiceUploadResponse.self, from: data)
    }
}
