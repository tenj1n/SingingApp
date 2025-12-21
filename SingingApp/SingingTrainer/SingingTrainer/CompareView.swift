import SwiftUI
import Charts

struct CompareView: View {
    
    private let sessionId: String
    @StateObject private var vm = CompareViewModel()
    
    // ズレ（cents）を見やすく＆軽くする設定
    @State private var showOnlyOutOfTol: Bool = false
    @State private var showTrendLine: Bool = true
    @State private var maxErrorPlotPoints: Int = 1200
    @State private var maxOverlayPlotPoints: Int = 2500
    @State private var showHistory = false
    
    init(sessionId: String = "orphans/user01") {
        self.sessionId = sessionId
    }
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("結果")
        }
        .onAppear {
            if vm.analysis == nil && !vm.isLoading {
                vm.load(sessionId: sessionId)
            }
        }
        .onChange(of: vm.density) { _, _ in
            vm.rebuildCaches()
        }
        .onChange(of: vm.octaveInvariant) { _, _ in
            vm.rebuildCaches()
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("解析情報を読み込み中…")
                .padding()
            
        } else if let err = vm.errorMessage {
            VStack(spacing: 12) {
                Text("取得に失敗しました").font(.headline)
                Text(err).font(.caption).foregroundStyle(.secondary)
                Button("再読み込み") { vm.reload() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            
        } else if let a = vm.analysis {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection(a)
                    commentSection()      // ← ここにボタンが入る
                    settingsSection(a)
                    
                    Divider()
                    
                    pitchOverlaySection(a)
                    
                    Divider()
                    
                    errorCentsSection(a)
                    
                    Divider()
                    
                    eventsPreviewSection(a)
                }
                .padding()
            }
            
        } else {
            VStack(spacing: 12) {
                Text("解析結果がありません").font(.headline)
                Button("読み込む") { vm.load(sessionId: sessionId) }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
    
    // MARK: - Summary
    
    private func summarySection(_ a: AnalysisResponse) -> some View {
        let eventCount = a.events?.count ?? 0
        let tol = a.summary?.tolCents ?? 40.0
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("比較結果概要").font(.title3.bold())
            
            Text("問題区間イベント数：\(eventCount) 件")
            Text("判定：\(PitchMath.verdictJP(a.summary?.verdict))")
            
            VStack(alignment: .leading, spacing: 6) {
                Text("スコア \(vm.score100, specifier: "%.1f") 点")
                    .font(.title3.bold())
                
                Text("通常: \(vm.score100Strict, specifier: "%.1f") 点 / オクターブ無視: \(vm.score100OctaveInvariant, specifier: "%.1f") 点")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Text("一致率: \(vm.percentWithinTol * 100, specifier: "%.1f")% / 平均ズレ: \(vm.meanAbsCents, specifier: "%.1f")c")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            
            Text("許容範囲：±\(Int(tol)) cents（半音=100c）")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let meta = a.meta?.paths {
                if let ref = meta.refPitch { Text("参照ピッチ：\(ref)").font(.caption2).foregroundStyle(.secondary) }
                if let usr = meta.usrPitch { Text("自分ピッチ：\(usr)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Comment
    
    private func commentSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.commentTitle).font(.headline)
            
            // ★AI生成ボタン + ローディング表示
            HStack(spacing: 12) {
                if vm.isAICommentLoading {
                    ProgressView()
                    Text("AIコメント生成中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("AIでコメント生成") {
                        vm.generateAIComment()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isAICommentLoading)
                    Button(vm.isHistorySaved ? "保存済み" : (vm.isHistorySaving ? "保存中…" : "履歴に保存")) {
                        vm.saveAICommentToHistory()
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.commentBody.isEmpty || vm.isHistorySaving || vm.isHistorySaved || vm.isAICommentLoading)
                    
                    if let e = vm.historySaveError, !e.isEmpty {
                        Text(e)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                Spacer()
            }
            
            // ★エラー表示
            if let e = vm.aiCommentError, !e.isEmpty {
                Text(e)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            // コメント本文
            Text(vm.commentBody.isEmpty ? "（まだありません）" : vm.commentBody)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Settings
    
    private func settingsSection(_ a: AnalysisResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("表示設定").font(.headline)
            
            Toggle("オクターブ差を無視して比較（推奨）", isOn: $vm.octaveInvariant)
            
            HStack {
                Text("表示密度（間引き）")
                Spacer()
                Picker("", selection: $vm.density) {
                    ForEach(Density.allCases) { d in
                        Text(d.label).tag(d)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Divider().padding(.vertical, 4)
            
            Text("ズレ表示（軽量化）").font(.subheadline.weight(.semibold))
            Toggle("許容外（±tol）だけ表示", isOn: $showOnlyOutOfTol)
            Toggle("傾向線（平均）を表示", isOn: $showTrendLine)
            
            HStack { Text("ズレ最大点数：\(maxErrorPlotPoints)"); Spacer() }
            Slider(value: Binding(
                get: { Double(maxErrorPlotPoints) },
                set: { maxErrorPlotPoints = Int($0) }
            ), in: 300...3000, step: 100)
            
            HStack { Text("ピッチ最大点数：\(maxOverlayPlotPoints)"); Spacer() }
            Slider(value: Binding(
                get: { Double(maxOverlayPlotPoints) },
                set: { maxOverlayPlotPoints = Int($0) }
            ), in: 800...6000, step: 200)
            
            Text("点が多いほど重くなります。まず密度×20〜×50＋最大点数を下げるのが効きます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Pitch Overlay
    
    private struct OverlayPlotPoint: Identifiable {
        let id = UUID()
        let time: Double
        let midi: Double
        let series: String
    }
    
    private func pitchOverlaySection(_ a: AnalysisResponse) -> some View {
        let raw: [OverlayPlotPoint] = vm.overlayPoints.map {
            .init(time: $0.time, midi: $0.midi, series: $0.series.rawValue)
        }
        let plot = downsampleToMax(raw.sorted(by: { $0.time < $1.time }), maxPoints: maxOverlayPlotPoints)
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("ピッチ比較（自分 vs 歌手）").font(.headline)
            Text("縦軸は「音名（MIDIノート）」。線が近いほど同じ音程です。")
                .font(.caption2).foregroundStyle(.secondary)
            
            if plot.isEmpty {
                Text("ピッチデータがありません").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(plot) { p in
                        LineMark(
                            x: .value("時間（秒）", p.time),
                            y: .value("音程（ノート）", p.midi),
                            series: .value("系列", p.series)
                        )
                        .foregroundStyle(by: .value("系列", p.series))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 320)
                .chartXAxisLabel("時間（秒）")
                .chartYAxisLabel("音程（ノート）")
                .chartLegend(position: .bottom)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 10)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let t = value.as(Double.self) { Text("\(Int(t))") }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .stride(by: 12)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let m = value.as(Double.self) {
                                Text(PitchMath.midiToNoteNameJP(m))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Error (cents)
    
    private struct ErrorPlotPoint: Identifiable {
        let id = UUID()
        let time: Double
        let cents: Double
    }
    
    private struct TrendPoint: Identifiable {
        let id: Int
        let time: Double
        let cents: Double
    }
    
    private func errorCentsSection(_ a: AnalysisResponse) -> some View {
        let tol = a.summary?.tolCents ?? 40.0
        
        let raw: [ErrorPlotPoint] = vm.errorPoints.map { .init(time: $0.time, cents: $0.cents) }
            .sorted(by: { $0.time < $1.time })
        
        let (plot, xMin, xMax) = makeErrorPlotPoints(src: raw, tol: tol, onlyOut: showOnlyOutOfTol, maxPoints: maxErrorPlotPoints)
        let trend: [TrendPoint] = showTrendLine ? makeTrend(points: plot, bins: 80) : []
        
        let maxAbs = plot.map { abs($0.cents) }.max() ?? 0
        let yMax = max(200.0, min(600.0, max(maxAbs * 1.1, tol * 2.0)))
        let yDomain = (-yMax)...(yMax)
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("ズレ（cents）").font(.headline)
            Text("0 が基準。＋は自分が高い／−は自分が低い。灰色の帯が許容範囲（±\(Int(tol))c）。")
                .font(.caption2).foregroundStyle(.secondary)
            
            if plot.isEmpty {
                Text("ズレデータがありません").foregroundStyle(.secondary)
            } else {
                Chart {
                    RectangleMark(
                        xStart: .value("開始", xMin),
                        xEnd: .value("終了", xMax),
                        yStart: .value("下限", -tol),
                        yEnd: .value("上限", tol)
                    )
                    .foregroundStyle(.gray.opacity(0.12))
                    
                    RuleMark(y: .value("基準", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    
                    RuleMark(y: .value("許容上", tol))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    
                    RuleMark(y: .value("許容下", -tol))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    
                    ForEach(plot) { p in
                        PointMark(
                            x: .value("時間（秒）", p.time),
                            y: .value("ズレ（cents）", p.cents)
                        )
                        .symbolSize(10)
                        .opacity(showOnlyOutOfTol ? 0.85 : 0.35)
                    }
                    
                    ForEach(trend) { t in
                        LineMark(
                            x: .value("時間（秒）", t.time),
                            y: .value("平均ズレ（cents）", t.cents)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .opacity(0.9)
                    }
                }
                .frame(height: 260)
                .chartYScale(domain: yDomain)
                .chartXAxisLabel("時間（秒）")
                .chartYAxisLabel("ズレ（cents）")
                .chartXAxis {
                    AxisMarks(values: .stride(by: 10)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let t = value.as(Double.self) { Text("\(Int(t))") }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .stride(by: 100)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v))") }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Events preview
    
    private func eventsPreviewSection(_ a: AnalysisResponse) -> some View {
        let evs = a.events ?? []
        let head = evs.prefix(10)
        
        return VStack(alignment: .leading, spacing: 6) {
            Text("問題区間（先頭10件）").font(.headline)
            
            if head.isEmpty {
                Text("問題区間はありません").foregroundStyle(.secondary)
            } else {
                ForEach(Array(head.enumerated()), id: \.offset) { _, e in
                    let s = e.start ?? 0
                    let ed = e.end ?? 0
                    Text("・\(String(format: "%.2f", s))〜\(String(format: "%.2f", ed)) 秒（\(e.type ?? "unknown")）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Helpers（軽量化）
    
    private func downsampleToMax<T>(_ src: [T], maxPoints: Int) -> [T] {
        guard !src.isEmpty else { return [] }
        guard src.count > maxPoints else { return src }
        let step = max(1, src.count / maxPoints)
        var out: [T] = []
        out.reserveCapacity(src.count / step + 1)
        var i = 0
        while i < src.count {
            out.append(src[i])
            i += step
        }
        return out
    }
    
    private func makeErrorPlotPoints(
        src: [ErrorPlotPoint],
        tol: Double,
        onlyOut: Bool,
        maxPoints: Int
    ) -> (points: [ErrorPlotPoint], xMin: Double, xMax: Double) {
        
        guard !src.isEmpty else { return ([], 0.0, 1.0) }
        
        let xMin = src.first?.time ?? 0.0
        let lastT = src.last?.time ?? (xMin + 1.0)
        let xMax = max(lastT, xMin + 1e-3)
        
        let filtered: [ErrorPlotPoint] = onlyOut ? src.filter { abs($0.cents) > tol } : src
        guard filtered.count > maxPoints else { return (filtered, xMin, xMax) }
        
        let step = max(1, filtered.count / maxPoints)
        var out: [ErrorPlotPoint] = []
        out.reserveCapacity(filtered.count / step + 1)
        
        var i = 0
        while i < filtered.count {
            out.append(filtered[i])
            i += step
        }
        return (out, xMin, xMax)
    }
    
    private func makeTrend(points: [ErrorPlotPoint], bins: Int) -> [TrendPoint] {
        guard !points.isEmpty, bins >= 2 else { return [] }
        
        let xMin = points.first!.time
        let xMax = points.last!.time
        let span = max(1e-6, xMax - xMin)
        let binSize = span / Double(bins)
        
        var sum = Array(repeating: 0.0, count: bins)
        var cnt = Array(repeating: 0, count: bins)
        
        for p in points {
            let raw = Int((p.time - xMin) / binSize)
            let idx = min(max(raw, 0), bins - 1)
            sum[idx] += p.cents
            cnt[idx] += 1
        }
        
        var out: [TrendPoint] = []
        out.reserveCapacity(bins)
        
        for i in 0..<bins {
            guard cnt[i] > 0 else { continue }
            let t = xMin + (Double(i) + 0.5) * binSize
            out.append(.init(id: i, time: t, cents: sum[i] / Double(cnt[i])))
        }
        return out
    }
}

#Preview {
    CompareView()
}
