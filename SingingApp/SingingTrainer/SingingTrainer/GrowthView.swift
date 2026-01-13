import SwiftUI
import Charts

struct GrowthView: View {
    private let userId: String
    @StateObject private var vm: GrowthViewModel
    
    // ★グラフ表示モード
    enum ChartMode: String, CaseIterable, Identifiable {
        case perTake = "回ごと"
        case dailyAvg = "1日平均"
        var id: String { rawValue }
    }
    @State private var chartMode: ChartMode = .perTake
    
    init(userId: String = "user01") {
        self.userId = userId
        _vm = StateObject(wrappedValue: GrowthViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                // フィルタ（期間・曲）
                VStack(alignment: .leading, spacing: 10) {
                    Picker("期間", selection: $vm.range) {
                        ForEach(GrowthViewModel.Range.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("曲")
                        Spacer()
                        Picker("曲", selection: $vm.songFilter) {
                            Text("全曲").tag(String?.none)
                            ForEach(vm.availableSongs, id: \.self) { s in
                                Text(s).tag(String?.some(s))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // ★表示モード切替
                    Picker("グラフ", selection: $chartMode) {
                        ForEach(ChartMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Divider()
                
                if vm.isLoading {
                    ProgressView("集計中…")
                        .padding()
                    Spacer()
                    
                } else if let err = vm.errorMessage, !err.isEmpty {
                    VStack(spacing: 12) {
                        Text("取得に失敗しました").font(.headline)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("再読み込み") { vm.reload() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    Spacer()
                    
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            
                            // KPI
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                                spacing: 10
                            ) {
                                KPI(title: "平均スコア", value: vm.kpiAvgScore)
                                KPI(title: "平均ズレ(cents)", value: vm.kpiAvgMeanAbsCents)
                                KPI(title: "許容内率(%)", value: vm.kpiAvgWithinTolPercent)
                                KPI(title: "練習回数", value: vm.kpiCount)
                            }
                            
                            // スコア推移
                            GroupBox(chartMode == .dailyAvg ? "スコア推移（1日平均）" : "スコア推移（回ごと）") {
                                
                                // ★ここが本命：回ごとは vm.takeScorePoints を使う
                                let points: [GrowthViewModel.ScorePoint] = (chartMode == .dailyAvg)
                                ? vm.dailyScorePoints
                                : vm.takeScorePoints
                                
                                if points.isEmpty {
                                    Text("表示できるデータがありません")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 18)
                                } else {
                                    ScrollView(.horizontal) {
                                        Chart(points) { p in
                                            LineMark(
                                                x: .value("日付", p.t),
                                                y: .value("スコア", p.score)
                                            )
                                            .interpolationMethod(.catmullRom)
                                            
                                            // ★点を必ず出す
                                            PointMark(
                                                x: .value("日付", p.t),
                                                y: .value("スコア", p.score)
                                            )
                                        }
                                        .chartYScale(domain: 0...100)
                                        .frame(width: chartWidth(forCount: points.count), height: 220)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 6)
                                    }
                                }
                            }
                            
                            // 最近のベスト
                            GroupBox("ベスト記録") {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let best = vm.bestItem {
                                        Text("最高スコア: \(String(format: "%.1f", best.score))")
                                            .font(.headline)
                                        Text(best.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        if let sid = best.sessionId, !sid.isEmpty {
                                            NavigationLink("この回のグラフを見る") {
                                                CompareView(sessionId: sid)
                                            }
                                            .buttonStyle(.borderedProminent)
                                        } else {
                                            Text("この回のグラフは開けません（session_id 未保存）")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Text("データがありません")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("成長")
            .onAppear { vm.reload() }
            .onChange(of: vm.range) { _, _ in vm.reload() }
            .onChange(of: vm.songFilter) { _, _ in vm.reload() }
        }
    }
    
    private func chartWidth(forCount n: Int) -> CGFloat {
        let base: CGFloat = 340
        let perPoint: CGFloat = 48
        return max(base, CGFloat(n) * perPoint)
    }
}

private struct KPI: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    GrowthView()
}
