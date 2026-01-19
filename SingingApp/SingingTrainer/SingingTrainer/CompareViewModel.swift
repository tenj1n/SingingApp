import Foundation
import SwiftUI

@MainActor
final class CompareViewModel: ObservableObject {
    
    // -------- API結果 --------
    @Published var analysis: AnalysisResponse?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // -------- 表示設定 --------
    @Published var density: Density = .x10
    @Published var octaveInvariant: Bool = true
    
    // -------- 描画用キャッシュ --------
    @Published private(set) var overlayPoints: [OverlayPoint] = []
    @Published private(set) var errorPoints: [ErrorPoint] = []
    
    // -------- 指標 --------
    @Published private(set) var sampleCount: Int = 0
    @Published private(set) var score100: Double = 0
    @Published private(set) var score100Strict: Double = 0
    @Published private(set) var score100OctaveInvariant: Double = 0
    @Published private(set) var percentWithinTol: Double = 0
    @Published private(set) var meanAbsCents: Double = 0
    
    // -------- AIコメント/履歴 --------
    @Published var isAICommentLoading = false
    @Published var aiCommentError: String?
    @Published var commentTitle: String = "AIコメント"
    @Published var commentBody: String = ""
    
    @Published var isHistorySaving = false
    @Published var isHistorySaved = false
    @Published var historySaveError: String?
    @Published var didGenerateAIComment: Bool = false
    
    // -------- セッション管理 --------
    @Published private(set) var lastSessionId: String?
    
    // ==================================================
    // MARK: - Public
    // ==================================================
    
    func load(sessionId: String) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                let decoded = try await APIClient.shared.getAnalysis(sessionId: sessionId)
                self.applyAnalysis(decoded, sessionIdFallback: sessionId)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func reload() {
        guard let sid = lastSessionId else {
            errorMessage = "sessionId がありません"
            return
        }
        load(sessionId: sid)
    }
    
    func applyAnalysis(_ decoded: AnalysisResponse, sessionIdFallback: String) {
        self.lastSessionId = decoded.sessionId ?? sessionIdFallback
        
        self.isLoading = false
        self.errorMessage = nil
        
        self.didGenerateAIComment = false
        self.isHistorySaved = false
        self.historySaveError = nil
        
        self.analysis = decoded
        self.rebuildCaches()
    }
    
    // ==================================================
    // MARK: - Core
    // ==================================================
    
    func rebuildCaches() {
        guard let a = analysis else {
            overlayPoints = []
            errorPoints = []
            sampleCount = 0
            score100 = 0
            score100Strict = 0
            score100OctaveInvariant = 0
            percentWithinTol = 0
            meanAbsCents = 0
            return
        }
        
        let tol = a.summary?.tolCents ?? 40.0
        
        let ref = (a.refPitch?.track ?? []).compactMap { p -> TimedF0? in
            guard let t = p.t else { return nil }
            let f0 = p.f0Hz
            return TimedF0(t: t, f0Hz: (f0 != nil && (f0 ?? 0) > 0) ? f0 : nil)
        }
        
        let usr = (a.usrPitch?.track ?? []).compactMap { p -> TimedF0? in
            guard let t = p.t else { return nil }
            let f0 = p.f0Hz
            return TimedF0(t: t, f0Hz: (f0 != nil && (f0 ?? 0) > 0) ? f0 : nil)
        }
        
        if ref.isEmpty || usr.isEmpty {
            overlayPoints = []
            errorPoints = []
            sampleCount = 0
            score100 = 0
            score100Strict = 0
            score100OctaveInvariant = 0
            percentWithinTol = 0
            meanAbsCents = 0
            return
        }
        
        let refS = ref.sorted { $0.t < $1.t }
        let usrS = usr.sorted { $0.t < $1.t }
        
        let t0 = max(refS.first!.t, usrS.first!.t)
        let t1 = min(refS.last!.t, usrS.last!.t)
        if t1 <= t0 {
            overlayPoints = []
            errorPoints = []
            sampleCount = 0
            score100 = 0
            score100Strict = 0
            score100OctaveInvariant = 0
            percentWithinTol = 0
            meanAbsCents = 0
            return
        }
        
        let refDtBase = Self.estimateDt(sr: a.refPitch?.sr, hop: a.refPitch?.hop)
        let usrDtBase = Self.estimateDt(sr: a.usrPitch?.sr, hop: a.usrPitch?.hop)
        var dtBase = min(refDtBase, usrDtBase)
        if !(dtBase > 0 && dtBase < 0.2) { dtBase = 0.02 }
        
        let refInterp = LinearInterp(track: refS)
        let usrInterp = LinearInterp(track: usrS)
        
        // 信頼性判定用（density 無し）
        var validForConfidence: Int = 0
        do {
            var t = t0
            while t <= t1 {
                let rf = refInterp.value(at: t)
                let uf = usrInterp.value(at: t)
                if (rf != nil && (rf ?? 0) > 0) && (uf != nil && (uf ?? 0) > 0) {
                    validForConfidence += 1
                }
                t += dtBase
            }
        }
        self.sampleCount = validForConfidence
        
        // 表示用（density 反映）
        var dt = dtBase * Double(density.multiplier)
        
        var aligned: [AlignedPoint] = []
        aligned.reserveCapacity(Int((t1 - t0) / dt) + 8)
        
        var t = t0
        while t <= t1 {
            let rf = refInterp.value(at: t)
            let uf = usrInterp.value(at: t)
            let rVoiced = (rf != nil && (rf ?? 0) > 0)
            let uVoiced = (uf != nil && (uf ?? 0) > 0)
            aligned.append(.init(t: t, refHz: rf, usrHz: uf, refVoiced: rVoiced, usrVoiced: uVoiced))
            t += dt
        }
        
        let valid = aligned.filter { $0.refVoiced && $0.usrVoiced }
        
        // --------------------------------------------------
        // ✅ octaveInvariant が ON のときは、
        //    overlay(usr) と error(usr-ref) の両方で
        //    usrHz を “refHz に近いオクターブ” に寄せる
        // --------------------------------------------------
        
        // overlayPoints
        var ov: [OverlayPoint] = []
        ov.reserveCapacity(aligned.count * 2)
        
        for p in aligned {
            let refMidi = p.refHz.flatMap { PitchMath.hzToMidi($0) }
            
            var usrHzForOverlay = p.usrHz
            if octaveInvariant, let rhz = p.refHz, let uhz = p.usrHz {
                usrHzForOverlay = PitchMath.shiftUsrHzToClosestOctave(refHz: rhz, usrHz: uhz)
            }
            let usrMidi = usrHzForOverlay.flatMap { PitchMath.hzToMidi($0) }
            
            ov.append(.init(time: p.t, midi: refMidi, series: .ref))
            ov.append(.init(time: p.t, midi: usrMidi, series: .usr))
        }
        self.overlayPoints = ov
        
        // errorPoints + 指標
        var errs: [ErrorPoint] = []
        errs.reserveCapacity(valid.count)
        
        var absCentsSum: Double = 0
        var withinTolCount: Int = 0
        
        for p in valid {
            guard let rhz = p.refHz, let uhz = p.usrHz else { continue }
            
            let usrHzAligned: Double
            if octaveInvariant {
                usrHzAligned = PitchMath.shiftUsrHzToClosestOctave(refHz: rhz, usrHz: uhz)
            } else {
                usrHzAligned = uhz
            }
            
            let cents = PitchMath.centsDiff(refHz: rhz, usrHz: usrHzAligned)
            errs.append(.init(time: p.t, cents: cents))
            
            let absV = abs(cents)
            absCentsSum += absV
            if absV <= tol { withinTolCount += 1 }
        }
        self.errorPoints = errs
        
        let n = max(1, valid.count)
        self.meanAbsCents = absCentsSum / Double(n)
        self.percentWithinTol = Double(withinTolCount) / Double(n)
        
        // スコア（今の PitchMath 設定をそのまま使う）
        self.score100 = PitchMath.scoreFromMeanAbsCents(meanAbsCents: meanAbsCents)
        
        // 表示用の2種（今のUIの “通常/オクターブ無視” 表示を維持）
        if octaveInvariant {
            let strictMean = Self.computeMeanAbsCentsStrict(valid: valid) // ここは “無視しない” 平均
            self.score100Strict = PitchMath.scoreFromMeanAbsCents(meanAbsCents: strictMean)
            self.score100OctaveInvariant = self.score100
        } else {
            self.score100Strict = self.score100
            let oiMean = Self.computeMeanAbsCentsOctaveInvariant(valid: valid)
            self.score100OctaveInvariant = PitchMath.scoreFromMeanAbsCents(meanAbsCents: oiMean)
        }
    }
    
    // ==================================================
    // MARK: - AI Comment / History
    // ==================================================
    
    func generateAIComment() {
        guard let sid = lastSessionId else { return }
        guard !isAICommentLoading else { return }
        
        isAICommentLoading = true
        aiCommentError = nil
        
        Task { @MainActor in
            defer { isAICommentLoading = false }
            do {
                let res = try await APIClient.shared.generateAIComment(sessionId: sid)
                self.commentTitle = res.title ?? "AIコメント"
                self.commentBody = res.body ?? ""
                self.didGenerateAIComment = true
                self.isHistorySaved = false
                self.historySaveError = nil
            } catch {
                self.aiCommentError = error.localizedDescription
            }
        }
    }
    
    func saveAICommentToHistory() {
        guard let sid = lastSessionId else { return }
        
        print("[SAVE] didGenerateAIComment=\(didGenerateAIComment) bodyLen=\(commentBody.count) titleLen=\(commentTitle.count) sid=\(sid)")
        
        guard !commentBody.isEmpty else { return }
        guard didGenerateAIComment else { return }
        guard !isHistorySaving else { return }
        
        isHistorySaving = true
        historySaveError = nil
        
        Task { @MainActor in
            defer { isHistorySaving = false }
            do {
                let req = HistorySaveRequest(
                    title: commentTitle,
                    body: commentBody,
                    score100: score100,
                    score100Strict: score100Strict,
                    score100OctaveInvariant: score100OctaveInvariant,
                    meanAbsCents: meanAbsCents,
                    percentWithinTol: percentWithinTol,
                    sampleCount: sampleCount
                )
                _ = try await APIClient.shared.appendHistory(sessionId: sid, reqBody: req, commentSource: .ai)
                self.isHistorySaved = true
            } catch {
                self.historySaveError = error.localizedDescription
            }
        }
    }

    
    // ==================================================
    // MARK: - Helpers
    // ==================================================
    
    private static func estimateDt(sr: Int?, hop: Int?) -> Double {
        guard let sr, let hop, sr > 0, hop > 0 else { return 0.0 }
        return Double(hop) / Double(sr)
    }
    
    private static func computeMeanAbsCentsStrict(valid: [AlignedPoint]) -> Double {
        var sum: Double = 0
        var n: Int = 0
        for p in valid {
            guard let rhz = p.refHz, let uhz = p.usrHz else { continue }
            let cents = PitchMath.centsDiff(refHz: rhz, usrHz: uhz)
            sum += abs(cents)
            n += 1
        }
        return n > 0 ? (sum / Double(n)) : 0
    }
    
    private static func computeMeanAbsCentsOctaveInvariant(valid: [AlignedPoint]) -> Double {
        var sum: Double = 0
        var n: Int = 0
        for p in valid {
            guard let rhz = p.refHz, let uhz = p.usrHz else { continue }
            let u2 = PitchMath.shiftUsrHzToClosestOctave(refHz: rhz, usrHz: uhz)
            let cents = PitchMath.centsDiff(refHz: rhz, usrHz: u2)
            sum += abs(cents)
            n += 1
        }
        return n > 0 ? (sum / Double(n)) : 0
    }
}

// ==================================================
// MARK: - Local types
// ==================================================

private struct TimedF0 {
    let t: Double
    let f0Hz: Double?
}

private struct AlignedPoint {
    let t: Double
    let refHz: Double?
    let usrHz: Double?
    let refVoiced: Bool
    let usrVoiced: Bool
}

private struct LinearInterp {
    let t: [Double]
    let f: [Double?]
    
    init(track: [TimedF0]) {
        self.t = track.map { $0.t }
        self.f = track.map { $0.f0Hz }
    }
    
    func value(at x: Double) -> Double? {
        if t.isEmpty { return nil }
        if x < t.first! || x > t.last! { return nil }
        
        var lo = 0
        var hi = t.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if t[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        let i1 = lo
        if i1 == 0 { return f[0] }
        let i0 = i1 - 1
        
        let t0 = t[i0], t1 = t[i1]
        if t1 == t0 { return f[i0] }
        
        guard let f0 = f[i0], let f1 = f[i1] else { return nil }
        let r = (x - t0) / (t1 - t0)
        return f0 + (f1 - f0) * r
    }
}
