import SwiftUI

struct HistoryListView: View {
    private let userId: String
    @StateObject private var vm: HistoryViewModel
    
    init(userId: String = "user01") {
        self.userId = userId
        _vm = StateObject(wrappedValue: HistoryViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("履歴")
                .toolbar { EditButton() }
                .onAppear { vm.load() }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("読み込み中…").padding()
        } else if let err = vm.errorMessage, !err.isEmpty {
            VStack(spacing: 12) {
                Text("取得に失敗しました").font(.headline)
                Text(err).font(.caption).foregroundStyle(.secondary)
                Button("再読み込み") { vm.load() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if vm.items.isEmpty {
            VStack(spacing: 10) {
                Text("履歴がありません").font(.headline)
                Text("サーバ側の /api/history に保存した記録がここに出ます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else {
            List {
                ForEach(vm.items) { item in
                    NavigationLink {
                        HistoryDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.commentTitle.isEmpty ? "AIコメント" : item.commentTitle)
                                .font(.headline)
                                .lineLimit(1)
                            
                            Text(item.createdAtShort)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            let s  = item.score100 ?? 0
                            let ss = item.score100Strict ?? 0
                            let so = item.score100OctaveInvariant ?? 0
                            Text("スコア: \(String(format: "%.1f", s)) / 通常: \(String(format: "%.1f", ss)) / オクターブ無視: \(String(format: "%.1f", so))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: vm.delete)
            }
        }
    }
}

struct HistoryDetailView: View {
    let item: HistoryItem
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.commentTitle.isEmpty ? "AIコメント" : item.commentTitle)
                        .font(.title3.bold())
                    
                    Text(item.createdAtShort)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !item.commentBody.isEmpty {
                        Text(item.commentBody)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                NavigationLink("グラフを見る") {
                    CompareView(sessionId: item.sessionId)
                }
                .buttonStyle(.borderedProminent)
                
                Spacer(minLength: 12)
            }
            .padding()
        }
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#Preview {HistoryListView()}
