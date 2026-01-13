import Foundation
import SwiftUI

@MainActor
final class CompareViewModel: ObservableObject {
    
    @Published var analysis: AnalysisResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 表示設定
    @Published var density: Density = .x10
    @Published var octaveInvariant = true
    
    // 表示キャッシュ
    @Published private(set) var overlayPoints: [OverlayPoint] = []
    @Published private(set) var errorPoints: [ErrorPoint] = []
    
    // スコア
    @Published private(set) var score100: Double = 0
    @Published private(set) var percentWithinTol: Double = 0
    @Published private(set) var meanAbsCents: Double = 0
    @Published private(set) var score100Strict: Double = 0
    @Published private(set) var score100OctaveInvariant: Double = 0
    @Published private(set) var sampleCount: Int = 0
    
    // コメント（表示）
    @Published private(set) var commentTitle: String = "コメント"
    @Published private(set) var commentBody: String = ""
    
    // AI
    @Published var isAICommentLoading = false
    @Published var aiCommentError: String?
    
    // 履歴保存（手動＝AIコメント用）
    @Published var isHistorySaving = false
    @Published var historySaveError: String?
    @Published private(set) var didGenerateAIComment = false
    @Published private(set) var isHistorySaved = false
    
    private var lastSessionId: String?
    
    // ==================================================
    // ✅ 自動履歴保存（ルールベース）
    // ==================================================
    
    /// 1セッションにつき1回だけ自動保存するための記録
    private var autoSavedSessionIds: Set<String> = []
    
    /// 声検出が少ないと誤検出で履歴が汚れるので、これ未満は自動保存しない
    private let minSampleCountForAutoSave = 200
    
    func load(sessionId: String) {
        guard !isLoading else { return }
        lastSessionId = sessionId
        isLoading = true
        errorMessage = nil
        
        // 手動（AI保存）状態のみリセット
        didGenerateAIComment = false
        isHistorySaved = false
        historySaveError = nil
        
        Task {
            do {
                let decoded = try await AnalysisAPI.shared.fetchAnalysis(sessionId: sessionId)
                self.analysis = decoded
                self.isLoading = false
                self.rebuildCaches() // ← ここで計算完了後に自動保存される
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func reload() {
        guard let s = lastSessionId else { return }
        load(sessionId: s)
    }
    
    func rebuildCaches() {
        guard let a = analysis else { return }
        
        let usrCount = a.usrPitch?.track?.count ?? 0
        let refCount = a.refPitch?.track?.count ?? 0
        if usrCount == 0 || refCount == 0 {
            self.overlayPoints = []
            self.errorPoints = []
            
            self.score100 = 0
            self.percentWithinTol = 0
            self.meanAbsCents = 0
            self.sampleCount = 0
            
            self.score100Strict = 0
            self.score100OctaveInvariant = 0
            
            self.commentTitle = "コメント"
            self.commentBody = a.summary?.reason ?? "解析準備中です。しばらくしてから再読み込みしてください。"
            return
        }
        
        let tol = a.summary?.tolCents ?? 40.0
        let density = self.density
        let showOctaveInvariant = self.octaveInvariant
        
        let usrPitch = a.usrPitch
        let refPitch = a.refPitch
        let summary = a.summary
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let strictResult = PitchMath.makeDisplayData(
                usr: usrPitch, ref: refPitch,
                density: density,
                octaveInvariant: false,
                tolCents: tol
            )
            
            let octaveResult = PitchMath.makeDisplayData(
                usr: usrPitch, ref: refPitch,
                density: density,
                octaveInvariant: true,
                tolCents: tol
            )
            
            let active = showOctaveInvariant ? octaveResult : strictResult
            
            let strictScore100 = strictResult.stats.percentWithinTol * 100.0
            let octaveScore100 = octaveResult.stats.percentWithinTol * 100.0
            let activeScore100 = active.stats.percentWithinTol * 100.0
            
            let baseComment = PitchMath.makeCommentJP(stats: active.stats, summary: summary)
            
            await MainActor.run {
                self.overlayPoints = active.overlay
                self.errorPoints = active.errors
                
                self.score100 = activeScore100
                self.percentWithinTol = active.stats.percentWithinTol
                self.meanAbsCents = active.stats.meanAbsCents
                self.sampleCount = active.stats.sampleCount
                
                self.score100Strict = strictScore100
                self.score100OctaveInvariant = octaveScore100
                
                // ルールベース（AIではない）
                self.commentTitle = baseComment.title
                self.commentBody = baseComment.body
                
                // ✅ ここが重要：値が確定した瞬間に自動保存を走らせる（sleep不要）
                self.autoSaveRuleBasedHistoryIfNeeded()
            }
        }
    }
    
    // ==================================================
    // ✅ 自動履歴保存（ルールベースコメント）
    // ==================================================
    private func autoSaveRuleBasedHistoryIfNeeded() {
        guard let sessionId = lastSessionId else { return }
        
        // 同じsessionIdは二重保存しない
        if autoSavedSessionIds.contains(sessionId) { return }
        
        // 評価できるだけの声検出が無いなら自動保存しない
        guard self.sampleCount >= self.minSampleCountForAutoSave else { return }
        
        // ルールコメントが空なら保存しない
        guard self.commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        
        let autoTitle = "自動保存：解析コメント"
        
        let req = HistorySaveRequest(
            commentTitle: autoTitle,
            commentBody: self.commentBody,
            
            score100: self.score100,
            score100Strict: self.score100Strict,
            score100OctaveInvariant: self.score100OctaveInvariant,
            octaveInvariantNow: self.octaveInvariant,
            
            tolCents: (self.analysis?.summary?.tolCents ?? 40.0),
            percentWithinTol: self.percentWithinTol,
            meanAbsCents: self.meanAbsCents,
            sampleCount: self.sampleCount
        )
        
        Task {
            do {
                // ✅ source をサーバ側で区別したいなら appendHistory にヘッダ対応を入れる（後述）
                // 自動保存
                let res = try await AnalysisAPI.shared.appendHistory(
                    sessionId: sessionId,
                    reqBody: req,
                    commentSource: .rule
                )
                if res.ok {
                    self.autoSavedSessionIds.insert(sessionId)
                } else {
                    print("[autoSave] failed:", res.message ?? "(no message)")
                }
            } catch {
                print("[autoSave] error:", error.localizedDescription)
            }
        }
    }
    
    func generateAIComment() {
        guard let a = analysis else { return }
        guard let sessionId = lastSessionId else { return }
        guard !isAICommentLoading else { return }
        
        isAICommentLoading = true
        aiCommentError = nil
        
        // AI生成し直したら「未保存」に戻す
        didGenerateAIComment = false
        isHistorySaved = false
        historySaveError = nil
        
        let tol = a.summary?.tolCents ?? 40.0
        let density = self.density
        let octaveNow = self.octaveInvariant
        
        let usrPitch = a.usrPitch
        let refPitch = a.refPitch
        
        let strictScore = self.score100Strict
        let octaveScore = self.score100OctaveInvariant
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let activeResult = PitchMath.makeDisplayData(
                usr: usrPitch,
                ref: refPitch,
                density: density,
                octaveInvariant: octaveNow,
                tolCents: tol
            )
            
            let req = AICommentRequest(
                stats: AICommentStats(
                    tolCents: activeResult.stats.tolCents,
                    percentWithinTol: activeResult.stats.percentWithinTol,
                    meanAbsCents: activeResult.stats.meanAbsCents,
                    sampleCount: activeResult.stats.sampleCount,
                    scoreStrict: strictScore,
                    scoreOctaveInvariant: octaveScore,
                    octaveInvariantNow: octaveNow
                )
            )
            
            do {
                let res = try await AnalysisAPI.shared.fetchAIComment(sessionId: sessionId, reqBody: req)
                await MainActor.run {
                    if res.ok {
                        self.commentTitle = res.title ?? "AIコメント"
                        self.commentBody = res.body ?? "（本文が空でした）"
                        self.aiCommentError = nil
                        
                        self.didGenerateAIComment = true
                        self.isHistorySaved = false
                        self.historySaveError = nil
                    } else {
                        self.aiCommentError = res.message ?? "AIコメント生成に失敗しました"
                    }
                    self.isAICommentLoading = false
                }
            } catch {
                await MainActor.run {
                    self.aiCommentError = error.localizedDescription
                    self.isAICommentLoading = false
                }
            }
        }
    }
    
    // ボタン押下時だけ履歴保存（AIコメント用）
    func saveAICommentToHistory() {
        guard let sessionId = lastSessionId else { return }
        guard !commentBody.isEmpty else { return }
        guard !isHistorySaving else { return }
        
        // ✅ 重要：AI生成してないなら保存しない（ルールベースが混ざるのを防ぐ）
        guard didGenerateAIComment else { return }
        
        isHistorySaving = true
        historySaveError = nil
        
        let req = HistorySaveRequest(
            commentTitle: commentTitle.isEmpty ? "AIコメント" : commentTitle,
            commentBody: commentBody,
            
            score100: score100,
            score100Strict: score100Strict,
            score100OctaveInvariant: score100OctaveInvariant,
            octaveInvariantNow: octaveInvariant,
            
            tolCents: (analysis?.summary?.tolCents ?? 40.0),
            percentWithinTol: percentWithinTol,
            meanAbsCents: meanAbsCents,
            sampleCount: sampleCount
        )
        
        Task {
            do {
                // AIボタン保存
                let res = try await AnalysisAPI.shared.appendHistory(
                    sessionId: sessionId,
                    reqBody: req,
                    commentSource: .ai
                )
                if res.ok {
                    isHistorySaved = true
                    historySaveError = nil
                } else {
                    historySaveError = res.message ?? "履歴の保存に失敗しました"
                }
                isHistorySaving = false
            } catch {
                historySaveError = error.localizedDescription
                isHistorySaving = false
            }
        }
    }
    
    func errorYDomain(tol: Double) -> ClosedRange<Double> {
        let m = max(200.0, tol * 6.0)
        return (-m)...(m)
    }
}
