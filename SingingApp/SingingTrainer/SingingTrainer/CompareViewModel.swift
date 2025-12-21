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
    
    // コメント（表示）
    @Published private(set) var commentTitle: String = "コメント"
    @Published private(set) var commentBody: String = ""
    
    // AI
    @Published var isAICommentLoading = false
    @Published var aiCommentError: String?
    
    // 履歴保存（手動）
    @Published var isHistorySaving = false
    @Published var historySaveError: String?
    @Published private(set) var didGenerateAIComment = false
    @Published private(set) var isHistorySaved = false
    @Published private(set) var sampleCount: Int = 0

    private var lastSessionId: String?
    
    func load(sessionId: String) {
        guard !isLoading else { return }
        lastSessionId = sessionId
        isLoading = true
        errorMessage = nil
        
        // ロードし直したら保存状態をリセット
        didGenerateAIComment = false
        isHistorySaved = false
        historySaveError = nil
        
        Task {
            do {
                let decoded = try await AnalysisAPI.shared.fetchAnalysis(sessionId: sessionId)
                self.analysis = decoded
                self.isLoading = false
                self.rebuildCaches()
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
                
                // ルールベースのコメント（これはAIではない）
                self.commentTitle = baseComment.title
                self.commentBody = baseComment.body
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
                let res = try await AnalysisAPI.shared.fetchAIComment(sessionId: sessionId, req: req)
                
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
    
    // ★追加：ボタン押下時だけ履歴保存
    func saveAICommentToHistory() {
        guard let sessionId = lastSessionId else { return }
        guard !commentBody.isEmpty else { return }
        guard !isHistorySaving else { return }
        
        // （あなたの方針が「AI生成後のみ保存」なら、これを残してOK）
        // guard didGenerateAIComment else { return }
        
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
        print("=== HistorySaveRequest ===")
        print("score100:", score100)
        print("score100Strict:", score100Strict)
        print("score100OctaveInvariant:", score100OctaveInvariant)
        print("octaveInvariantNow:", octaveInvariant)
        print("tolCents:", (analysis?.summary?.tolCents ?? 40.0))
        print("percentWithinTol:", percentWithinTol)
        print("meanAbsCents:", meanAbsCents)
        print("sampleCount:", sampleCount)
        print("==========================")

        Task {
            do {
                let res = try await AnalysisAPI.shared.appendHistory(sessionId: sessionId, reqBody: req)
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

    
    // ズレグラフの表示レンジ
    func errorYDomain(tol: Double) -> ClosedRange<Double> {
        let m = max(200.0, tol * 6.0)
        return (-m)...(m)
    }
    
    private static func splitSongUser(from sessionId: String) -> (String, String) {
        let parts = sessionId.split(separator: "/").map(String.init)
        if parts.count >= 2 { return (parts[0], parts[1]) }
        return ("orphans", "user01")
    }
}
