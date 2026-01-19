import Foundation

// ==================================================
// MARK: - AI Comment Models
// ==================================================

struct AICommentRequest: Encodable {
    var promptVersion: String? = nil
    var model: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case promptVersion = "prompt_version"
        case model
    }
}

struct AICommentResponse: Decodable {
    let ok: Bool?
    let title: String?
    let body: String?
    let model: String?
    let promptVersion: String?
    
    enum CodingKeys: String, CodingKey {
        case ok, title, body, model
        case promptVersion = "prompt_version"
    }
}
