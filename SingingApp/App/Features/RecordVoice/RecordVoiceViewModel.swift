import Foundation

@MainActor
final class RecordVoiceViewModel: ObservableObject {
    
    // 入力
    let userId: String
    
    // 状態
    @Published var isUploading: Bool = false
    @Published var errorMessage: String?
    
    // 遷移用（CompareViewに渡すsessionId）
    @Published var nextSessionId: String?
    
    private let api: AnalysisAPI
    
    init(userId: String, api: AnalysisAPI = .shared) {
        self.userId = userId
        self.api = api
    }
    
    // 成功/失敗を Bool で返す（VMでは削除しない）
    func uploadOnlyReturnBool(fileURL: URL?, songId: String) async -> Bool {
        guard let fileURL else {
            errorMessage = "録音ファイルがありません"
            return false
        }
        
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        
        do {
            let res = try await api.uploadUserVoice(userId: userId, songId: songId, wavFileURL: fileURL)
            nextSessionId = res.session_id
            return true
        } catch {
            errorMessage = "アップロードに失敗: \(error.localizedDescription)"
            return false
        }
    }
    
    func resetError() {
        errorMessage = nil
    }
    
    func resetNavigation() {
        nextSessionId = nil
    }
}
