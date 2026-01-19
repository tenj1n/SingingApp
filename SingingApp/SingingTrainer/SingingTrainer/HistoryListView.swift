import SwiftUI

// MARK: - HistoryListView (Game UI)

struct HistoryListView: View {
    private let userId: String
    @StateObject private var vm: HistoryViewModel
    
    init(userId: String = "user01") {
        self.userId = userId
        _vm = StateObject(wrappedValue: HistoryViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GameBackground()
                
                VStack(spacing: 12) {
                    filterPanel
                    content
                        .padding(.horizontal, 14)
                }
                .padding(.top, 12)
            }
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.resetAndLoad() }
            
            // フィルタが変わったら「先頭から」取り直す
            .onChange(of: vm.onlyAI) { _, _ in vm.resetAndLoad() }
            .onChange(of: vm.promptFilter) { _, _ in vm.resetAndLoad() }
            .onChange(of: vm.modelFilter) { _, _ in vm.resetAndLoad() }
        }
    }
    
    // MARK: - Filter Panel
    
    private var filterPanel: some View {
        SectionCard(accent: .purple) {
            VStack(alignment: .leading, spacing: 10) {
                
                HStack {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    MeterPills(text: vm.currentFilterLabel, accent: .purple)
                }
                
                Toggle(isOn: $vm.onlyAI) {
                    Text("AIのみ")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .tint(.purple)
                
                HStack {
                    Text("Prompt")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                }
                
                Picker("prompt", selection: $vm.promptFilter) {
                    ForEach(HistoryViewModel.PromptFilter.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.purple)
                
                HStack {
                    Text("Model")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                }
                
                Picker("model", selection: $vm.modelFilter) {
                    ForEach(HistoryViewModel.ModelFilter.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
        }
        .padding(.horizontal, 14)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            loadingPanel
            
        } else if let err = vm.errorMessage, !err.isEmpty {
            errorPanel(err)
            
        } else if vm.items.isEmpty {
            emptyPanel
            
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    
                    // ✅ ここを変更：id を明示して Binding版 ForEach を回避
                    ForEach(vm.items, id: \.id) { item in
                        
                        // ✅ sessionId があれば CompareView 直行
                        if let sid = item.sessionId, !sid.isEmpty {
                            NavigationLink {
                                CompareView(sessionId: sid)
                            } label: {
                                HistoryRowCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let idx = vm.items.firstIndex(where: { $0.id == item.id }) {
                                        vm.delete(at: IndexSet(integer: idx))
                                    }
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            
                        } else {
                            // sessionId が無いものは従来通り詳細へ
                            NavigationLink {
                                HistoryDetailView(item: item)
                            } label: {
                                HistoryRowCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let idx = vm.items.firstIndex(where: { $0.id == item.id }) {
                                        vm.delete(at: IndexSet(integer: idx))
                                    }
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    
                    if vm.canLoadMore || vm.isLoadingMore {
                        loadMoreRow
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.top, 6)
            }
        }
    }
    
    private var loadingPanel: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("読み込み中…")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.top, 30)
    }
    
    private func errorPanel(_ err: String) -> some View {
        VStack(spacing: 12) {
            Text("取得に失敗しました")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            
            Text(err)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            
            Button {
                vm.resetAndLoad()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("再読み込み")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassPrimaryButtonStyle(accent: .red))
        }
        .padding(14)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.red.opacity(0.35), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.top, 30)
    }
    
    private var emptyPanel: some View {
        VStack(spacing: 10) {
            Text("履歴がありません")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            
            Text("条件: \(vm.currentFilterLabel)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
            
            Text(vm.onlyAI
                 ? "AIの履歴がありません（トグルをOFFにすると全件表示に戻ります）"
                 : "サーバ側の /api/history に保存した記録がここに出ます。")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.top, 30)
    }
    
    private var loadMoreRow: some View {
        SectionCard(accent: .blue) {
            Button {
                vm.loadMore()
            } label: {
                HStack(spacing: 10) {
                    if vm.isLoadingMore {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                    Text(vm.isLoadingMore ? "読み込み中…" : "次の5件を読み込む")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .opacity(0.7)
                }
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoadingMore)
        }
        .padding(.top, 2)
    }
}

// MARK: - Row Card

private struct HistoryRowCard: View {
    let item: HistoryItem
    
    private var titleText: String {
        // 1) songTitle があれば最優先
        if let s = item.songTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        
        // 2) title があれば次
        if let s = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        
        // 3) songId があれば、songs.json から曲名に変換して出す（ここが今回の肝）
        if let sid = item.songId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
            if let name = SongCatalog.shared.title(for: sid), !name.isEmpty {
                return name   // ✅ "kaijyu" -> "怪獣の花唄" になる
            }
            return sid // 変換できなかった時だけ id を表示
        }
        
        return "(no title)"
    }

    
    private var bodyText: String { item.body ?? "" }
    
    private var subText: String {
        if let s = item.createdAt, !s.isEmpty { return s }
        if let s = item.songId, !s.isEmpty { return "song: \(s)" }
        if let s = item.source, !s.isEmpty { return "source: \(s)" }
        return ""
    }
    
    private var accent: Color {
        bodyText.isEmpty ? .white.opacity(0.45) : .green
    }
    
    var body: some View {
        SectionCard(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(accent.opacity(0.45), lineWidth: 1)
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: bodyText.isEmpty ? "waveform.path" : "sparkles")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titleText)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        if !subText.isEmpty {
                            Text(subText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        
                        if !bodyText.isEmpty {
                            Text(bodyText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.70))
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                ScoreLine(item: item)
            }
        }
    }
}

private struct ScoreLine: View {
    let item: HistoryItem
    
    var body: some View {
        let s  = item.score100 ?? 0
        let ss = item.score100Strict ?? 0
        let so = item.score100OctaveInvariant ?? 0
        
        VStack(spacing: 8) {
            HStack {
                Text("SCORE")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: "%.1f", s))
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            ProgressBar(value: s / 100.0)
            
            HStack(spacing: 10) {
                MiniChip(title: "通常", value: ss)
                MiniChip(title: "OCT", value: so)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct MiniChip: View {
    let title: String
    let value: Double
    
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
            Text(String(format: "%.1f", value))
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.25), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

private struct ProgressBar: View {
    let value: Double // 0...1
    
    var body: some View {
        GeometryReader { geo in
            let w = max(0, min(1, value)) * geo.size.width
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(.white.opacity(0.55))
                    .frame(width: w)
            }
        }
        .frame(height: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Detail View (Game UI)

struct HistoryDetailView: View {
    let item: HistoryItem
    
    private var titleText: String {
        if let s = item.songTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        if let s = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        if let s = item.songId?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        return "履歴"
    }
    
    private var bodyText: String { item.body ?? "" }
    private var metaText: String {
        if let s = item.createdAt, !s.isEmpty { return s }
        if let s = item.songId, !s.isEmpty { return "song: \(s)" }
        if let s = item.source, !s.isEmpty { return "source: \(s)" }
        return ""
    }
    
    var body: some View {
        ZStack {
            GameBackground()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    
                    SectionCard(accent: .green) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(titleText)
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            
                            if !metaText.isEmpty {
                                Text(metaText)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                            
                            if !bodyText.isEmpty {
                                Text(bodyText)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .padding(.top, 4)
                            }
                        }
                    }
                    
                    if let sid = item.sessionId, !sid.isEmpty {
                        NavigationLink {
                            CompareView(sessionId: sid)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "chart.xyaxis.line")
                                Text("グラフを見る")
                                Spacer()
                                Image(systemName: "chevron.right").opacity(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassPrimaryButtonStyle(accent: .blue))
                    }
                    
                    Spacer(minLength: 18)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("履歴詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared Components

private struct GameBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.06, blue: 0.16), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 340, height: 340)
                .offset(x: -140, y: -240)
                .blur(radius: 1)
            
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 460, height: 460)
                .offset(x: 180, y: 260)
                .blur(radius: 1)
            
            VStack(spacing: 16) {
                ForEach(0..<16, id: \.self) { _ in
                    Rectangle()
                        .fill(.white.opacity(0.035))
                        .frame(height: 1)
                }
            }
            .rotationEffect(.degrees(-10))
            .scaleEffect(1.15)
            .ignoresSafeArea()
        }
    }
}

private struct SectionCard<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.55), .white.opacity(0.18), accent.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: accent.opacity(0.16), radius: 18, x: 0, y: 10)
    }
}

private struct MeterPills: View {
    let text: String
    let accent: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(accent.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.45), lineWidth: 1))
    }
}

private struct GlassPrimaryButtonStyle: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(0.55), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    HistoryListView(userId: "preview_user_123")
}
