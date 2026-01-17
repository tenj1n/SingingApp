import Foundation

@MainActor
final class AnalyzeFlowViewModel: ObservableObject {
    
    @Published var phaseText: String = ""
    @Published var isWorking: Bool = false
    @Published var errorMessage: String?
    
    @Published var sessionId: String?
    @Published var status: APIStatusResponse?
    @Published var analysis: AnalysisResponse?
    
    // MARK: - Full flow (upload -> analyze -> poll -> analysis)
    func runFlow(userId: String, songId: String, wavFileURL: URL) {
        guard !isWorking else { return }
        
        isWorking = true
        phaseText = ""
        errorMessage = nil
        sessionId = nil
        status = nil
        analysis = nil
        
        // ✅ UI更新を確実に MainActor 上で行う
        Task { @MainActor in
            // ✅ 必ず最後に止める（成功/失敗どちらでも）
            defer { self.isWorking = false }
            
            do {
                // 1) upload
                phaseText = "アップロード中..."
                let up = try await APIClient.shared.uploadVoice(
                    userId: userId,
                    songId: songId,
                    wavFileURL: wavFileURL
                )
                
                guard up.ok, let sid = up.session_id else {
                    throw APIError.invalidResponse("upload failed")
                }
                sessionId = sid
                
                // 2) analyze
                phaseText = "解析開始..."
                _ = try await APIClient.shared.analyze(sessionId: sid)
                
                // 3) poll
                phaseText = "解析中..."
                status = try await APIClient.shared.pollStatusUntilDone(
                    sessionId: sid,
                    intervalSec: 1.5,
                    timeoutSec: 900
                )
                
                // 4) analysis（done直後にファイルが遅れることがあるのでリトライ）
                phaseText = "結果取得中..."
                let decoded = try await fetchAnalysisWithRetry(sessionId: sid)
                analysis = decoded
                
                phaseText = "done"
                
            } catch {
                errorMessage = error.localizedDescription
                phaseText = "error"
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
        
        do {
            // 1) status
            phaseText = "status"
            let st1 = try await APIClient.shared.getStatus(sessionId: sid)
            status = st1
            
            if (st1.state ?? "").lowercased() == "error" {
                throw APIError.invalidResponse("status=error: \(st1.message ?? "")")
            }
            
            // 2) analyze (if not done)
            if (st1.state ?? "").lowercased() != "done" {
                phaseText = "analyze"
                _ = try await APIClient.shared.analyze(sessionId: sid)
            }
            
            // 3) polling
            phaseText = "polling"
            let stDone = try await APIClient.shared.pollStatusUntilDone(
                sessionId: sid,
                intervalSec: 1.0,
                timeoutSec: 900
            )
            status = stDone
            
            // 4) analysis
            phaseText = "getAnalysis"
            let a = try await fetchAnalysisWithRetry(sessionId: sid)
            analysis = a
            
            // 表示用（好みで）
            phaseText = "done analyzed"
            
        } catch {
            errorMessage = "解析に失敗: \(error.localizedDescription)"
            phaseText = "error"
        }
    }

    // MARK: - Retry (IMPORTANT)
    /// status=done でも analysis ファイルが一瞬遅れることがあるので、少し待って取りに行く
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
