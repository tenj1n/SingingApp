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
            VStack(spacing: 0) {
                
                // ★フィルタ行
                VStack(alignment: .leading, spacing: 10) {
                    
                    Toggle("AIのみ", isOn: $vm.onlyAI)
                    
                    // B-1 prompt
                    Picker("prompt", selection: $vm.promptFilter) {
                        ForEach(HistoryViewModel.PromptFilter.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // B-2 model（segmentedだと窮屈なのでmenu）
                    Picker("model", selection: $vm.modelFilter) {
                        ForEach(HistoryViewModel.ModelFilter.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 10)
                
                Divider()
                
                content
            }
            .navigationTitle("履歴")
            .toolbar { EditButton() }
            .onAppear { vm.load() }
            
            // どれか変わったら再取得
            .onChange(of: vm.onlyAI) { _, _ in
                vm.load()
            }
            .onChange(of: vm.promptFilter) { _, _ in
                vm.load()
            }
            .onChange(of: vm.modelFilter) { _, _ in
                vm.load()
            }
       }
    }
    
    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("読み込み中…")
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            
        } else if let err = vm.errorMessage, !err.isEmpty {
            VStack(spacing: 12) {
                Text("取得に失敗しました")
                    .font(.headline)
                
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("再読み込み") { vm.load() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            
        } else if vm.items.isEmpty {
            VStack(spacing: 10) {
                Text("履歴がありません")
                    .font(.headline)
                
                Text(vm.onlyAI
                     ? "AIの履歴がありません（トグルをOFFにすると全件表示に戻ります）"
                     : "サーバ側の /api/history に保存した記録がここに出ます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                            
                            Text(item.experimentShort)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            
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
                    
                    Text(item.experimentShort)
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

#Preview { HistoryListView() }
