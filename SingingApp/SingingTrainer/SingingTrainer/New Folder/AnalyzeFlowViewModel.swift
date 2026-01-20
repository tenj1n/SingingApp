import Foundation

@MainActor
final class AnalyzeFlowViewModel: ObservableObject {
    
    @Published var phaseText: String = ""
    @Published var isWorking: Bool = false
    @Published var errorMessage: String?
    
    @Published var sessionId: String?
    @Published var status: APIStatusResponse?
    @Published var analysis: AnalysisResponse?
    
    @Published var progressFraction: Double = 0.0
    @Published var progressLabel: String = "準備中…"
    
    // ✅ analyzing中だけじわじわ増やす用（上限）
    private let analyzingMax: Double = 0.85
    private let analyzingStep: Double = 0.01
    
    // MARK: - Full flow (upload -> analyze -> poll -> analysis)
    // （ここは DebugView 用っぽいので、いまは進捗を雑に入れるだけにしておく）
    func runFlow(userId: String, songId: String, wavFileURL: URL) {
        guard !isWorking else { return }
        
        isWorking = true
        phaseText = ""
        errorMessage = nil
        sessionId = nil
        status = nil
        analysis = nil
        
        progressFraction = 0.05
        progressLabel = "アップロード準備中…"
        
        Task { @MainActor in
            defer { self.isWorking = false }
            
            do {
                // 1) upload
                phaseText = "アップロード中..."
                progressFraction = 0.10
                progressLabel = "アップロード中…"
                
                let up = try await APIClient.shared.uploadVoice(
                    userId: userId,
                    songId: songId,
                    wavFileURL: wavFileURL
                )
                
                guard up.ok, let sid = up.sessionId else {
                    throw APIError.invalidResponse("upload failed")
                }
                sessionId = sid
                
                // 2) analyze
                phaseText = "解析開始..."
                progressFraction = max(progressFraction, 0.20)
                progressLabel = "解析開始…"
                _ = try await APIClient.shared.analyze(sessionId: sid)
                
                // 3) polling（✅ ここも while で進捗更新）
                phaseText = "polling"
                let start = Date()
                
                while true {
                    let st = try await APIClient.shared.getStatus(sessionId: sid)
                    status = st
                    
                    let state = (st.state ?? "").lowercased()
                    applyStatusToProgress(st)
                    
                    if state == "done" { break }
                    if state == "error" {
                        throw APIError.invalidResponse("status=error: \(st.message ?? "")")
                    }
                    
                    if Date().timeIntervalSince(start) > 900 {
                        throw APIError.timeout
                    }
                    
                    try await Task.sleep(nanoseconds: 800_000_000)
                }
                
                // 4) analysis
                phaseText = "結果取得中..."
                progressFraction = max(progressFraction, 0.95)
                progressLabel = "結果取得中…"
                
                let decoded = try await fetchAnalysisWithRetry(sessionId: sid)
                analysis = decoded
                
                progressFraction = 1.0
                progressLabel = "完了"
                phaseText = "done"
                
            } catch {
                errorMessage = error.localizedDescription
                phaseText = "error"
                progressFraction = 1.0
                progressLabel = "失敗"
            }
        }
    }
    
    // MARK: - From sessionId (already uploaded)
    @MainActor
    func runFromSession(sessionId sid: String) async {
        
        if isWorking { return }
        
        isWorking = true
        defer { isWorking = false }
        
        errorMessage = nil
        phaseText = "start"
        status = nil
        analysis = nil
        sessionId = sid
        
        progressFraction = 0.05
        progressLabel = "状態確認中…"
        
        do {
            // 1) status
            phaseText = "status"
            let st1 = try await APIClient.shared.getStatus(sessionId: sid)
            status = st1
            applyStatusToProgress(st1)
            
            if (st1.state ?? "").lowercased() == "error" {
                throw APIError.invalidResponse("status=error: \(st1.message ?? "")")
            }
            
            // 2) analyze (if not done)
            if (st1.state ?? "").lowercased() != "done" {
                phaseText = "analyze"
                progressFraction = max(progressFraction, 0.15)
                progressLabel = "解析開始…"
                _ = try await APIClient.shared.analyze(sessionId: sid)
            }
            
            // 3) polling（✅ while で回して逐次更新 + analyzing中じわじわ）
            phaseText = "polling"
            let start = Date()
            
            while true {
                let st = try await APIClient.shared.getStatus(sessionId: sid)
                status = st
                
                let state = (st.state ?? "").lowercased()
                
                // まず state に応じた基本値を当てる
                applyStatusToProgress(st)
                
                // ✅ analyzing の間だけ、じわじわ増やす（上限0.85）
                if state == "analyzing" {
                    progressFraction = min(analyzingMax, progressFraction + analyzingStep)
                }
                
                if state == "done" { break }
                if state == "error" {
                    throw APIError.invalidResponse("status=error: \(st.message ?? "")")
                }
                
                if Date().timeIntervalSince(start) > 900 {
                    throw APIError.timeout
                }
                
                try await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            }
            
            // 4) analysis
            phaseText = "getAnalysis"
            progressFraction = max(progressFraction, 0.95)
            progressLabel = "結果取得中…"
            let a = try await fetchAnalysisWithRetry(sessionId: sid)
            analysis = a
            
            progressFraction = 1.0
            progressLabel = "完了"
            phaseText = "done analyzed"
            
        } catch {
            errorMessage = "解析に失敗: \(error.localizedDescription)"
            phaseText = "error"
            progressFraction = 1.0
            progressLabel = "失敗"
        }
    }
    
    // MARK: - Progress mapping
    private func applyStatusToProgress(_ s: APIStatusResponse?) {
        let st = (s?.state ?? "unknown").lowercased()
        
        switch st {
        case "queued":
            progressFraction = max(progressFraction, 0.20)
            progressLabel = "解析待ち…"
            
        case "analyzing":
            // ✅ analyzing は「最低ここまで」だけ保証して、あとは while でじわじわ増やす
            progressFraction = max(progressFraction, 0.55)
            progressLabel = "解析中…"
            
        case "done":
            progressFraction = max(progressFraction, 0.90)
            progressLabel = "仕上げ中…"
            
        default:
            progressFraction = max(progressFraction, 0.10)
            progressLabel = "状態確認中…"
        }
    }
    
    // MARK: - Retry (IMPORTANT)
    private func fetchAnalysisWithRetry(sessionId sid: String) async throws -> AnalysisResponse {
        let maxTries = 20
        let delayNs: UInt64 = 500_000_000 // 0.5s
        
        var lastError: Error?
        
        for i in 1...maxTries {
            do {
                phaseText = "getAnalysis (\(i)/\(maxTries))"
                let a = try await APIClient.shared.getAnalysis(sessionId: sid)
                return a
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: delayNs)
            }
        }
        
        throw lastError ?? APIError.timeout
    }
}
