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
            ZStack {
                GameBackground()
                
                VStack(spacing: 12) {
                    filterPanel
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                    
                    content
                        .padding(.horizontal, 14)
                }
            }
            .navigationTitle("成長")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { vm.reload() }
            .onChange(of: vm.range) { _, _ in vm.reload() }
            .onChange(of: vm.songFilter) { _, _ in vm.reload() }
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
                    
                    MeterPills(text: vm.range.label, accent: .purple)
                }
                
                // 期間
                Picker("期間", selection: $vm.range) {
                    ForEach(GrowthViewModel.Range.allCases, id: \.self) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.purple)
                
                // 曲フィルタ
                HStack {
                    Text("曲")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                    
                    Spacer()
                    
                    Picker("曲", selection: $vm.songFilter) {
                        Text("全曲").tag(String?.none)
                        ForEach(vm.availableSongs, id: \.self) { s in
                            Text(s).tag(String?.some(s))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }
                
                // 表示モード
                HStack {
                    Text("グラフ")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                }
                
                Picker("グラフ", selection: $chartMode) {
                    ForEach(ChartMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.purple)
            }
        }
    }
    
    // MARK: - Content Switch
    
    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            loadingPanel
            
        } else if let err = vm.errorMessage, !err.isEmpty {
            errorPanel(err)
            
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    
                    // KPI
                    kpiGrid
                    
                    // スコア推移
                    chartPanel
                    
                    // ベスト記録
                    bestPanel
                    
                    // debug
                    Text("userId: \(userId)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 6)
                        .padding(.bottom, 16)
                }
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
        }
    }
    
    private var loadingPanel: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("集計中…")
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
                vm.reload()
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
    
    // MARK: - KPI
    
    private var kpiGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
            spacing: 10
        ) {
            KPI(title: "平均スコア", value: vm.kpiAvgScore, accent: .green)
            KPI(title: "平均ズレ(cents)", value: vm.kpiAvgMeanAbsCents, accent: .cyan)
            KPI(title: "許容内率(%)", value: vm.kpiAvgWithinTolPercent, accent: .orange)
            KPI(title: "練習回数", value: vm.kpiCount, accent: .purple)
        }
    }
    
    // MARK: - Chart Panel
    
    private var chartPanel: some View {
        SectionCard(accent: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        chartMode == .dailyAvg ? "スコア推移（1日平均）" : "スコア推移（回ごと）",
                        systemImage: "chart.xyaxis.line"
                    )
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    
                    Spacer()
                    
                    MeterPills(
                        text: chartMode == .dailyAvg ? "DAILY AVG" : "PER TAKE",
                        accent: .blue
                    )
                }
                
                let points: [GrowthViewModel.ScorePoint] =
                (chartMode == .dailyAvg) ? vm.dailyScorePoints : vm.takeScorePoints
                
                if points.isEmpty {
                    Text("表示できるデータがありません")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
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
                    .scrollIndicators(.hidden)
                    
                    // 下にメーターバー（平均スコアざっくり表示）
                    let avg = averageScore(points)
                    VStack(spacing: 8) {
                        HStack {
                            Text("AVG")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text(String(format: "%.1f", avg))
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        ProgressBar(value: avg / 100.0)
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
        }
    }
    
    // MARK: - Best Panel
    
    private var bestPanel: some View {
        SectionCard(accent: .green) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("ベスト記録", systemImage: "crown.fill")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                
                if let best = vm.bestItem {
                    Text("最高スコア: \(String(format: "%.1f", best.score))")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text(best.subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    
                    if let sid = best.sessionId, !sid.isEmpty {
                        NavigationLink {
                            CompareView(sessionId: sid)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform.path.ecg")
                                Text("この回のグラフを見る")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .opacity(0.7)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassPrimaryButtonStyle(accent: .blue))
                    } else {
                        Text("この回のグラフは開けません（session_id 未保存）")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                } else {
                    Text("データがありません")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func chartWidth(forCount n: Int) -> CGFloat {
        let base: CGFloat = 340
        let perPoint: CGFloat = 48
        return max(base, CGFloat(n) * perPoint)
    }
    
    private func averageScore(_ points: [GrowthViewModel.ScorePoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        let sum = points.reduce(0.0) { $0 + $1.score }
        return sum / Double(points.count)
    }
}

// MARK: - Components

private struct KPI: View {
    let title: String
    let value: String
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            
            ProgressBar(value: kpiBarValue(from: value))
        }
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
    
    // value が数値っぽい時だけバーを動かす（ダメなら 0.35 固定）
    private func kpiBarValue(from s: String) -> Double {
        // "12.3" "12.3%" "12.3回" みたいなのを雑に拾う
        let filtered = s
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "回", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let v = Double(filtered) {
            // スコア/率は 0-100 を想定
            if v > 1.0 { return max(0, min(1, v / 100.0)) }
            return max(0, min(1, v))
        }
        return 0.35
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

#Preview {
    GrowthView(userId: "preview_user_123")
}
