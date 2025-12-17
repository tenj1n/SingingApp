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
    
    // スコア・コメント
    @Published private(set) var score100: Double = 0
    @Published private(set) var percentWithinTol: Double = 0
    @Published private(set) var meanAbsCents: Double = 0
    @Published private(set) var commentTitle: String = "コメント"
    @Published private(set) var commentBody: String = ""
    
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
        let octaveInvariant = self.octaveInvariant
        
        // 重い計算はバックグラウンドへ
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            
            let result = PitchMath.makeDisplayData(
                usr: a.usrPitch,
                ref: a.refPitch,
                density: density,
                octaveInvariant: octaveInvariant,
                tolCents: tol
            )
            
            let score = result.stats.percentWithinTol * 100.0
            let comment = PitchMath.makeCommentJP(stats: result.stats, summary: a.summary)
            
            await MainActor.run {
                self.overlayPoints = result.overlay
                self.errorPoints = result.errors
                
                self.score100 = score
                self.percentWithinTol = result.stats.percentWithinTol
                self.meanAbsCents = result.stats.meanAbsCents
                
                self.commentTitle = comment.title
                self.commentBody = comment.body
            }
        }
    }
    
    // ズレグラフの表示レンジ（極端な値で潰れないように）
    func errorYDomain(tol: Double) -> ClosedRange<Double> {
        // だいたい±(tol*6) くらいを上限にして見やすく
        let m = max(200.0, tol * 6.0)
        return (-m)...(m)
    }
}
