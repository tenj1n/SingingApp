import Foundation

@MainActor
final class UploadProgress: NSObject, ObservableObject, URLSessionTaskDelegate {
    
    @Published var fraction: Double = 0          // 0.0〜1.0
    @Published var sentBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var isUploading: Bool = false
    
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()
    
    func upload(request: URLRequest, body: Data) async throws -> (Data, URLResponse) {
        isUploading = true
        fraction = 0
        sentBytes = 0
        totalBytes = Int64(body.count)
        
        return try await withCheckedThrowingContinuation { cont in
            var req = request
            req.httpBody = nil
            
            let task = session.uploadTask(with: req, from: body) { data, resp, err in
                Task { @MainActor in
                    self.isUploading = false
                }
                
                if let err {
                    cont.resume(throwing: err)
                    return
                }
                guard let data, let resp else {
                    cont.resume(throwing: URLError(.badServerResponse))
                    return
                }
                cont.resume(returning: (data, resp))
            }
            task.resume()
        }
    }
    
    // 進捗通知
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        Task { @MainActor in
            self.sentBytes = totalBytesSent
            self.totalBytes = (totalBytesExpectedToSend > 0) ? totalBytesExpectedToSend : self.totalBytes
            if self.totalBytes > 0 {
                self.fraction = Double(totalBytesSent) / Double(self.totalBytes)
            }
        }
    }
}
