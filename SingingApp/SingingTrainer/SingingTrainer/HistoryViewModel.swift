import Foundation
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 既に作った：AIのみ
    @Published var onlyAI = false
    
    // ★追加：promptフィルタ（B-1）
    enum PromptFilter: String, CaseIterable, Identifiable {
        case all = ""   // 指定なし
        case v1 = "v1"
        case v2 = "v2"
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .all: return "全部"
            case .v1:  return "v1"
            case .v2:  return "v2"
            }
        }
    }
    @Published var promptFilter: PromptFilter = .all
    
    // ★追加：modelフィルタ（B-2）
    enum ModelFilter: String, CaseIterable, Identifiable {
        case all = ""        // 指定なし
        case gpt52 = "gpt-5.2"
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .all:   return "全部"
            case .gpt52: return "gpt-5.2"
            }
        }
    }
    @Published var modelFilter: ModelFilter = .all
    
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
                let source = onlyAI ? "ai" : nil
                let prompt = promptFilter.rawValue.isEmpty ? nil : promptFilter.rawValue
                let model  = modelFilter.rawValue.isEmpty ? nil : modelFilter.rawValue
                
                let res = try await AnalysisAPI.shared.fetchHistoryList(
                    userId: userId,
                    source: source,
                    prompt: prompt,
                    model: model
                )
                
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
            // フィルタ状態を保ったまま再取得
            load()
        }
    }
}
