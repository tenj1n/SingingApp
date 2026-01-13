import Foundation

struct CreateUserResponse: Decodable {
    let ok: Bool
    let message: String?
    let user_id: String?
    let token: String?
    let name: String?
}

final class UserAPI {
    static let shared = UserAPI()
    private init() {}
    
    func createUser(displayName: String?) async throws -> String {
        let base = AnalysisAPI.shared.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(string: "\(base)/api/users")!
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct Body: Encodable { let name: String }
        let name = (displayName?.isEmpty == false) ? displayName! : "guest"
        req.httpBody = try JSONEncoder().encode(Body(name: name))
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "UserAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(text)"])
        }
        
        let decoded = try JSONDecoder().decode(CreateUserResponse.self, from: data)
        guard decoded.ok, let uid = decoded.user_id, !uid.isEmpty else {
            throw NSError(domain: "UserAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: decoded.message ?? "user create failed"])
        }
        return uid
    }
}
