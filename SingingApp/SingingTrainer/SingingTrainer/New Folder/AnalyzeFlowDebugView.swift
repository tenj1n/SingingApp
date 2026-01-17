import SwiftUI

struct AnalyzeFlowDebugView: View {
    
    @StateObject private var flowVM = AnalyzeFlowViewModel()
    @StateObject private var compareVM = CompareViewModel()
    
    let userId: String
    let songId: String
    let wavFileURL: URL
    
    var body: some View {
        VStack(spacing: 16) {
            
            Text(flowVM.phaseText)
            
            if let sid = flowVM.sessionId {
                Text("session: \(sid)")
                    .font(.caption)
            }
            
            if let s = flowVM.status {
                Text("status: \(s.state ?? "-") \(s.message ?? "")")
                    .font(.caption)
            }
            
            if let err = flowVM.errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Button(flowVM.isWorking ? "処理中..." : "解析実行") {
                flowVM.runFlow(
                    userId: userId,
                    songId: songId,
                    wavFileURL: wavFileURL
                )
            }
            .disabled(flowVM.isWorking)
            
            Divider()
            
            Text("CompareVM sampleCount: \(compareVM.sampleCount)")
                .font(.caption)
            
            // ✅ CompareView を注入モードで表示
            CompareView(
                sessionId: flowVM.sessionId ?? "orphans/user01",
                viewModel: compareVM
            )
        }
        .padding()
        
        // ✅ ここが一番確実：analysis の sessionId が変わったら必ず注入
        .task(id: flowVM.sessionId ?? "") {
            guard let a = flowVM.analysis else { return }
            let fallbackSid = flowVM.sessionId ?? "orphans/user01"
            compareVM.applyAnalysis(a, sessionIdFallback: fallbackSid)
        }

    }
}
