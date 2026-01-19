import Foundation
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [HistoryListResponse.HistoryItem] = []
    @Published var isLoading = false          // 初回/リセット読み込み用
    @Published var isLoadingMore = false      // 追加読み込み用
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
        
        var queryValue: String? { rawValue.isEmpty ? nil : rawValue }
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
        
        var queryValue: String? { rawValue.isEmpty ? nil : rawValue }
    }
    @Published var modelFilter: ModelFilter = .all
    
    // ★0件のときに「どの条件で0件か」を表示するためのラベル
    var currentFilterLabel: String {
        var parts: [String] = []
        if onlyAI { parts.append("AIのみ") }
        parts.append("prompt=\(promptFilter.queryValue ?? "全部")")
        parts.append("model=\(modelFilter.queryValue ?? "全部")")
        return parts.joined(separator: " / ")
    }
    
    private let userId: String
    
    // ----------------------------
    // paging state
    // ----------------------------
    private let pageSize = 5
    private var offset = 0
    private var hasMore = true
    
    var canLoadMore: Bool { hasMore && !isLoading && !isLoadingMore }
    
    init(userId: String) {
        self.userId = userId
    }
    
    // 画面表示/フィルタ変更時はこれ
    func resetAndLoad() {
        offset = 0
        hasMore = true
        items.removeAll()
        loadNextPage(isReset: true)
    }
    
    // 「次の5件」ボタンで呼ぶ
    func loadMore() {
        loadNextPage(isReset: false)
    }
    
    private func loadNextPage(isReset: Bool) {
        if isReset {
            guard !isLoading else { return }
            isLoading = true
        } else {
            guard canLoadMore else { return }
            isLoadingMore = true
        }
        
        errorMessage = nil
        
        Task {
            defer {
                isLoading = false
                isLoadingMore = false
            }
            
            do {
                let source = onlyAI ? "ai" : nil
                
                let res = try await APIClient.shared.fetchHistoryList(
                    userId: userId,
                    source: source,
                    prompt: promptFilter.queryValue,
                    model: modelFilter.queryValue,
                    limit: pageSize,
                    offset: offset
                )
                
                guard (res.ok ?? false) else {
                    errorMessage = res.message ?? "履歴の取得に失敗しました"
                    return
                }

                let newItems = res.items ?? []   // ✅ nilなら空配列
                
                // 追加
                items.append(contentsOf: newItems)
                
                // 次のoffsetへ
                offset += newItems.count
                
                // 返ってきた件数が pageSize 未満なら「もう次は無い」
                if newItems.count < pageSize {
                    hasMore = false
                }

                
                // 返ってきた件数が pageSize 未満なら「もう次は無い」
                if newItems.count < pageSize {
                    hasMore = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func delete(at offsets: IndexSet) {
        let targets = offsets.map { items[$0] }
        items.remove(atOffsets: offsets)
        
        Task {
            for t in targets {
                _ = try? await APIClient.shared.deleteHistory(userId: userId, historyId: t.id)
            }
            // 削除後はズレやすいので先頭から取り直す
            resetAndLoad()
        }
    }
}
