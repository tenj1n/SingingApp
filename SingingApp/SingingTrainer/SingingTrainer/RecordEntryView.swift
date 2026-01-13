import SwiftUI

struct RecordEntryView: View {
    @State private var ready = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.06, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if ready {
                RecordVoiceView()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("録音画面を準備中…")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .navigationTitle("録音")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 1フレーム待って先に画面を出す（体感が激変する）
            await Task.yield()
            ready = true
        }
    }
}
