import Foundation
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
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
                let res = try await AnalysisAPI.shared.fetchHistoryList(userId: userId)
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
        }
    }
}
