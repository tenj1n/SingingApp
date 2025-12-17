import Foundation

final class AnalysisAPI {
    static let shared = AnalysisAPI()
    private init() {}
    
    private let baseURL = URL(string: "http://127.0.0.1:5000")!
    
    /// 例: sessionId = "orphans/user01"
    func fetchAnalysis(sessionId: String) async throws -> AnalysisResponse {
        // sessionId に / が含まれてもOKな形で URL を作る
        let url = URL(string: "\(baseURL.absoluteString)/api/analysis/\(sessionId)")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "AnalysisAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(AnalysisResponse.self, from: data)
    }
}
