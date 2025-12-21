import Foundation

@MainActor
final class RecordVoiceViewModel: ObservableObject {
    
    // 入力
    let userId: String
    
    // 状態
    @Published var isUploading: Bool = false
    @Published var errorMessage: String?
    
    // 遷移用
    @Published var nextSessionId: String?
    
    private let api: AnalysisAPI
    
    init(userId: String, api: AnalysisAPI = .shared) {
        self.userId = userId
        self.api = api
    }
    
    func uploadIfPossible(fileURL: URL?) async {
        guard let fileURL else {
            errorMessage = "録音ファイルがありません"
            return
        }
        
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        
        do {
            let res = try await api.uploadUserVoice(userId: userId, wavFileURL: fileURL)
            nextSessionId = res.session_id
        } catch {
            errorMessage = "アップロードに失敗: \(error.localizedDescription)"
        }
    }
}
