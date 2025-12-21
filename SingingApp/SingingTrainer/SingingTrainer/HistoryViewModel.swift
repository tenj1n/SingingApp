import Foundation
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // ★追加：AIのみトグル状態
    @Published var onlyAI = false
    
    private let userId: String
    
    init(userId: String) {
        self.userId = userId
    }
    
    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // ★ここがA-2：トグル状態でsourceを切り替える
                let source = onlyAI ? "ai" : nil
                let res = try await AnalysisAPI.shared.fetchHistoryList(userId: userId, source: source)
                
                if res.ok {
                    items = res.items
                } else {
                    errorMessage = res.message ?? "履歴の取得に失敗しました"
                }
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    func delete(at offsets: IndexSet) {
        let targets = offsets.map { items[$0] }
        items.remove(atOffsets: offsets)
        
        Task {
            for t in targets {
                _ = try? await AnalysisAPI.shared.deleteHistory(userId: userId, historyId: t.id)
            }
            // ★削除後に、フィルタ状態を保ったまま再取得
            load()
        }
    }
}
