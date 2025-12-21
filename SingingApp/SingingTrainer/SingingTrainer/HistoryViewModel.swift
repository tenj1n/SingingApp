import Foundation
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 既に作った：AIのみ
    @Published var onlyAI = false
    
    // ★promptフィルタ（B-1）
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
        
        var queryValue: String? {
            rawValue.isEmpty ? nil : rawValue
        }
    }
    @Published var promptFilter: PromptFilter = .all
    
    // ★modelフィルタ（B-2）
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
        
        var queryValue: String? {
            rawValue.isEmpty ? nil : rawValue
        }
    }
    @Published var modelFilter: ModelFilter = .all
    
    // ★追加：0件のときに「どの条件で0件か」を表示するためのラベル
    var currentFilterLabel: String {
        var parts: [String] = []
        
        if onlyAI { parts.append("AIのみ") }
        
        if let p = promptFilter.queryValue {
            parts.append("prompt=\(p)")
        } else {
            parts.append("prompt=全部")
        }
        
        if let m = modelFilter.queryValue {
            parts.append("model=\(m)")
        } else {
            parts.append("model=全部")
        }
        
        return parts.joined(separator: " / ")
    }
    
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
                
                let res = try await AnalysisAPI.shared.fetchHistoryList(
                    userId: userId,
                    source: source,
                    prompt: promptFilter.queryValue,
                    model: modelFilter.queryValue
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
