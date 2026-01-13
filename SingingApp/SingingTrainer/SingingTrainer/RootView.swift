import SwiftUI

struct RootView: View {
    @EnvironmentObject var userSession: UserSession
    
    var body: some View {
        Group {
            if userSession.isReady, let _ = userSession.userId {
                HomeView()
            } else if let msg = userSession.errorMessage {
                VStack(spacing: 12) {
                    Text("ユーザー準備に失敗しました")
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                    Button("再試行") {
                        Task { await userSession.bootstrapIfNeeded(displayName: nil) }
                    }
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("初回準備中…")
                }
                .task {
                    await userSession.bootstrapIfNeeded(displayName: nil)
                }
                .padding()
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(UserSession(previewUserId: "preview_user_123"))
}

