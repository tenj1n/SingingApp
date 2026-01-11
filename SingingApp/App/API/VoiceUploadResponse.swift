import Foundation

struct VoiceUploadResponse: Decodable {
    let ok: Bool
    let session_id: String?
    let message: String?
}
