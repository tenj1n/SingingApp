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
    
    // 表示キャッシュ（軽量化済みの点群）
    @Published private(set) var overlayPoints: [OverlayPoint] = []
    @Published private(set) var errorPoints: [ErrorPoint] = []
    
    // スコア・コメント（現在選択中の表示モードのスコア）
    @Published private(set) var score100: Double = 0
    @Published private(set) var percentWithinTol: Double = 0
    @Published private(set) var meanAbsCents: Double = 0
    
    // 両方のスコア（通常 / オクターブ無視）
    @Published private(set) var score100Strict: Double = 0              // octaveInvariant=false
    @Published private(set) var score100OctaveInvariant: Double = 0      // octaveInvariant=true
    
    @Published private(set) var commentTitle: String = "コメント"
    @Published private(set) var commentBody: String = ""
    
    // AI生成ボタン
    @Published var isAICommentLoading = false
    @Published var aiCommentError: String?
    
    private var lastSessionId: String?
    
    func load(sessionId: String) {
        guard !isLoading else { return }
        lastSessionId = sessionId
        isLoading = true
        errorMessage = nil
        
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
        
        // detached に渡す値は先に退避
        let usrPitch = a.usrPitch
        let refPitch = a.refPitch
        let summary = a.summary
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let strictResult = PitchMath.makeDisplayData(
                usr: usrPitch,
                ref: refPitch,
                density: density,
                octaveInvariant: false,
                tolCents: tol
            )
            
            let octaveResult = PitchMath.makeDisplayData(
                usr: usrPitch,
                ref: refPitch,
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
                
                self.score100Strict = strictScore100
                self.score100OctaveInvariant = octaveScore100
                
                self.commentTitle = baseComment.title
                self.commentBody = baseComment.body
            }
        }
    }
    
    // AIコメント生成（サーバへPOSTしてコメントを受け取る）
    func generateAIComment() {
        guard let a = analysis else { return }
        guard let sessionId = lastSessionId else { return }
        guard !isAICommentLoading else { return }
        
        isAICommentLoading = true
        aiCommentError = nil
        
        // ★ detached に入る前に、MainActor上で必要な値を全部コピーしておく（ここが重要）
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
    
    func errorYDomain(tol: Double) -> ClosedRange<Double> {
        let m = max(200.0, tol * 6.0)
        return (-m)...(m)
    }
}
