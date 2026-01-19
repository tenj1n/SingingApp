import SwiftUI
import Charts

struct CompareView: View {
    
    // total = usrPitch.track.count
    private func totalSampleCount(_ a: AnalysisResponse) -> Int {
        a.usrPitch?.track.count ?? 0
    }
    
    // effective = f0_hz が nil じゃない点の数（声が出てる判定）
    private func effectiveSampleCount(_ a: AnalysisResponse) -> Int {
        (a.usrPitch?.track ?? []).reduce(0) { $0 + (($1.f0Hz == nil) ? 0 : 1) }
    }
    
    // ==================================================
    // 基本情報
    // ==================================================
    private let sessionId: String
    
    @StateObject private var vm: CompareViewModel
    private let autoLoadOnAppear: Bool
    
    // ==================================================
    // UI設定（軽量化・見やすさ）
    // ==================================================
    @State private var showOnlyOutOfTol: Bool = false
    @State private var showTrendLine: Bool = true
    @State private var maxErrorPlotPoints: Int = 1200
    @State private var maxOverlayPlotPoints: Int = 2500
    
    // ✅ 評価を出す最低サンプル数（vm.sampleCount は density 無しの“信頼用”）
    private let minSampleCountForEvaluation = 200
    
    // ✅ ピッチ線のギャップを切る（無音を線で繋がない）
    private let overlayGapSec = 0.25
    
    // ==================================================
    // 通常モード: CompareView が自分でロードする
    // ==================================================
    init(sessionId: String = "orphans/user01") {
        self.sessionId = sessionId
        _vm = StateObject(wrappedValue: CompareViewModel())
        self.autoLoadOnAppear = true
    }
    
    // ==================================================
    // 注入モード: 外から CompareViewModel を渡す（AnalyzeFlow用）
    // ==================================================
    init(sessionId: String, viewModel: CompareViewModel) {
        self.sessionId = sessionId
        _vm = StateObject(wrappedValue: viewModel)
        self.autoLoadOnAppear = false
    }
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("結果")
        }
        .onAppear {
            guard autoLoadOnAppear else { return }
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
    
    // ==================================================
    // MARK: - Content
    // ==================================================
    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("解析情報を読み込み中…")
                .padding()
        } else if let err = vm.errorMessage {
            VStack(spacing: 12) {
                Text("取得に失敗しました").font(.headline)
                Text(err).font(.caption).foregroundStyle(.secondary)
                
                if autoLoadOnAppear {
                    Button("再読み込み") { vm.reload() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("この画面は表示専用です。録音後の解析（AnalyzeFlow）が完了した結果が注入されていません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        } else if let a = vm.analysis {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summarySection(a)
                    commentSection()
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
                
                if autoLoadOnAppear {
                    Button("読み込む") { vm.load(sessionId: sessionId) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("録音→アップロード→解析完了後に、この画面へ結果が注入されると表示されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
    
    // ==================================================
    // MARK: - Summary
    // ==================================================
    private func summarySection(_ a: AnalysisResponse) -> some View {
        let eventCount = a.events?.count ?? 0
        let tol = a.summary?.tolCents ?? 40.0
        
        let lowConfidence = vm.sampleCount < minSampleCountForEvaluation
        
        let total = totalSampleCount(a)
        let effective = effectiveSampleCount(a)
        
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
            
            if vm.score100 <= 0.01 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("デバッグ: score=0 の原因確認")
                        .font(.caption.weight(.semibold))
                    Text("vm.sampleCount=\(vm.sampleCount), meanAbs=\(vm.meanAbsCents, specifier: "%.2f"), within=\(vm.percentWithinTol * 100, specifier: "%.1f")%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("usr effective=\(effective) / total=\(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            if lowConfidence {
                VStack(alignment: .leading, spacing: 6) {
                    Text("声検出不足のため、評価の信頼性が低いです（参考表示）")
                        .font(.subheadline.weight(.semibold))
                    Text("有効サンプル数が少ない状態では、外音やノイズの誤検出でスコアやズレが不正確になりやすいです。マイクを近づける／声量を上げる／イヤホン使用などを試してください。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("有効サンプル数: \(effective) / \(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // ==================================================
    // MARK: - Comment
    // ==================================================
    private func commentSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vm.commentTitle).font(.headline)
            
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
                        // ✅ songStore は使わない（未定義で落ちるため）
                        // sessionId から songId を取り出す（"kaijyu/xxxx/xxxx" の先頭）
                        let songId = sessionId.split(separator: "/").first.map(String.init) ?? "unknown"
                        
                        // ✅ いったん曲名は songId を仮で入れる（後で履歴一覧では song_title を表示する）
                        let songTitle = songId
                        
                        vm.saveAICommentToHistory(songId: songId, songTitle: songTitle)
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
            
            if let e = vm.aiCommentError, !e.isEmpty {
                Text(e)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            Text(vm.commentBody.isEmpty ? "（まだありません）" : vm.commentBody)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // ==================================================
    // MARK: - Settings
    // ==================================================
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
            Slider(
                value: Binding(
                    get: { Double(maxErrorPlotPoints) },
                    set: { maxErrorPlotPoints = Int($0) }
                ),
                in: 300...3000,
                step: 100
            )
            
            HStack { Text("ピッチ最大点数：\(maxOverlayPlotPoints)"); Spacer() }
            Slider(
                value: Binding(
                    get: { Double(maxOverlayPlotPoints) },
                    set: { maxOverlayPlotPoints = Int($0) }
                ),
                in: 800...6000,
                step: 200
            )
            
            Text("点が多いほど重くなります。まず密度×20〜×50＋最大点数を下げるのが効きます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // ==================================================
    // MARK: - Pitch Overlay
    // ==================================================
    private struct OverlayPlotPoint: Identifiable {
        let id = UUID()
        let time: Double
        let midi: Double?
        let series: String
    }
    
    private func pitchOverlaySection(_ a: AnalysisResponse) -> some View {
        let lowConfidence = vm.sampleCount < minSampleCountForEvaluation
        
        let raw: [OverlayPlotPoint] = vm.overlayPoints.map {
            .init(time: $0.time, midi: $0.midi, series: $0.series.rawValue)
        }
        
        let sortedAll = raw.sorted { $0.time < $1.time }
        let downsampledAll = downsampleToMax(sortedAll, maxPoints: maxOverlayPlotPoints)
        let grouped = Dictionary(grouping: downsampledAll, by: { $0.series })
        
        func breakLineOnGaps(_ pts: [OverlayPlotPoint]) -> [OverlayPlotPoint] {
            guard !pts.isEmpty else { return [] }
            var out: [OverlayPlotPoint] = []
            out.reserveCapacity(pts.count + 16)
            
            var prevT: Double? = nil
            for p in pts {
                if let prev = prevT, (p.time - prev) > overlayGapSec {
                    out.append(.init(time: p.time, midi: nil, series: p.series))
                }
                out.append(p)
                prevT = p.time
            }
            return out
        }
        
        let refSeries = "歌手"
        let usrSeries = "自分"
        
        let refPts = breakLineOnGaps((grouped[refSeries] ?? []).sorted { $0.time < $1.time })
        let usrPts = breakLineOnGaps((grouped[usrSeries] ?? []).sorted { $0.time < $1.time })
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ピッチ比較（自分 vs 歌手）").font(.headline)
                Spacer()
                if lowConfidence {
                    Text("参考")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }
            
            Text("縦軸は「音名（MIDIノート）」。線が近いほど同じ音程です。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            if refPts.isEmpty && usrPts.isEmpty {
                Text("ピッチデータがありません").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(refPts) { p in
                        if let m = p.midi {
                            LineMark(
                                x: .value("時間（秒）", p.time),
                                y: .value("音程（ノート）", m)
                            )
                            .foregroundStyle(by: .value("系列", refSeries))
                            .interpolationMethod(.linear)
                        }
                    }
                    
                    ForEach(usrPts) { p in
                        if let m = p.midi {
                            LineMark(
                                x: .value("時間（秒）", p.time),
                                y: .value("音程（ノート）", m)
                            )
                            .foregroundStyle(by: .value("系列", usrSeries))
                            .interpolationMethod(.linear)
                        }
                    }
                }
                .frame(height: 320)
                .chartXAxisLabel("時間（秒）")
                .chartYAxisLabel("音程（ノート）")
                .chartLegend(position: .bottom)
            }
        }
    }
    
    // ==================================================
    // MARK: - Error (cents)
    // ==================================================
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
        let lowConfidence = vm.sampleCount < minSampleCountForEvaluation
        
        var raw: [ErrorPlotPoint] = vm.errorPoints.map { .init(time: $0.time, cents: $0.cents) }
        raw.sort { $0.time < $1.time }
        
        let down = downsampleToMax(raw, maxPoints: maxErrorPlotPoints)
        
        let filtered: [ErrorPlotPoint]
        if showOnlyOutOfTol {
            filtered = down.filter { abs($0.cents) > tol }
        } else {
            filtered = down
        }
        
        let trend: [TrendPoint] = {
            guard showTrendLine, !filtered.isEmpty else { return [] }
            let bins = 24
            let t0 = filtered.first!.time
            let t1 = filtered.last!.time
            if t1 <= t0 { return [] }
            let w = (t1 - t0) / Double(bins)
            
            var out: [TrendPoint] = []
            out.reserveCapacity(bins + 1)
            
            for i in 0...bins {
                let left = t0 + Double(i) * w
                let right = left + w
                let chunk = filtered.filter { $0.time >= left && $0.time < right }
                if chunk.isEmpty { continue }
                let mean = chunk.reduce(0.0) { $0 + $1.cents } / Double(chunk.count)
                out.append(.init(id: i, time: left + w * 0.5, cents: mean))
            }
            return out
        }()
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ズレ（cents）").font(.headline)
                Spacer()
                if lowConfidence {
                    Text("参考")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }
            
            Text("0c が完全一致。±\(Int(tol))c 以内なら許容範囲です。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            if filtered.isEmpty {
                Text(showOnlyOutOfTol ? "許容外の点がありません" : "ズレデータがありません")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    RuleMark(y: .value("0", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                    
                    RuleMark(y: .value("+tol", tol))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary)
                    RuleMark(y: .value("-tol", -tol))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary)
                    
                    ForEach(filtered) { p in
                        PointMark(
                            x: .value("時間（秒）", p.time),
                            y: .value("ズレ（cents）", p.cents)
                        )
                        .symbolSize(10)
                    }
                    
                    if showTrendLine, trend.count >= 2 {
                        ForEach(trend) { tp in
                            LineMark(
                                x: .value("時間（秒）", tp.time),
                                y: .value("平均", tp.cents)
                            )
                            .interpolationMethod(.linear)
                        }
                    }
                }
                .frame(height: 260)
                .chartXAxisLabel("時間（秒）")
                .chartYAxisLabel("ズレ（cents）")
            }
        }
    }
    
    // ==================================================
    // MARK: - Events preview
    // ==================================================
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
    
    // ==================================================
    // MARK: - Helpers
    // ==================================================
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
}

#Preview {
    CompareView()
}
