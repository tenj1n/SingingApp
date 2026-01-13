import SwiftUI

struct ContentView: View {
    
    @EnvironmentObject var userSession: UserSession
    
    var body: some View {
        NavigationStack {
            ZStack {
                GameBackground()
                
                if userSession.isReady, let uid = userSession.userId {
                    menu(uid: uid)
                } else if let msg = userSession.errorMessage {
                    errorView(msg: msg)
                } else {
                    loadingView()
                        .task { await userSession.bootstrapIfNeeded(displayName: nil) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SingingTrainer")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    // MARK: - Menu
    
    private func menu(uid: String) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("READY")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Text("今日も1曲いこう")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                
                VStack(spacing: 12) {
                    NavigationLink {
                        RecordVoiceView()
                    } label: {
                        RhythmMenuCard(
                            title: "録音して解析",
                            subtitle: "1曲録って、ズレを可視化",
                            iconSystemName: "mic.fill",
                            style: .primary
                        )
                    }
                    
                    NavigationLink {
                        HistoryListView(userId: uid)
                    } label: {
                        RhythmMenuCard(
                            title: "履歴",
                            subtitle: "過去のコメントとスコア",
                            iconSystemName: "clock.arrow.circlepath",
                            style: .secondary
                        )
                    }
                    
                    NavigationLink {
                        GrowthView(userId: uid)
                    } label: {
                        RhythmMenuCard(
                            title: "成長",
                            subtitle: "上達の推移をグラフで",
                            iconSystemName: "chart.line.uptrend.xyaxis",
                            style: .accent
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                
                // デバッグ（小さく）
                VStack(alignment: .leading, spacing: 6) {
                    Text("userId")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(uid)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
    }
    
    // MARK: - States
    
    private func loadingView() -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("初回準備中…")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }
    
    private func errorView(msg: String) -> some View {
        VStack(spacing: 12) {
            Text("ユーザ準備に失敗しました")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
            Text(msg)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Button("再試行") {
                Task { await userSession.bootstrapIfNeeded(displayName: nil) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.15))
        }
        .padding()
    }
}

// MARK: - UI Parts

private struct GameBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.07, green: 0.05, blue: 0.12),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(0.10), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()
        )
    }
}

private struct RhythmMenuCard: View {
    
    enum Style { case primary, secondary, accent }
    
    let title: String
    let subtitle: String
    let iconSystemName: String
    let style: Style
    
    private var cardBackground: some ShapeStyle {
        switch style {
        case .primary:
            return LinearGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            return LinearGradient(
                colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .accent:
            return LinearGradient(
                colors: [Color.white.opacity(0.20), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: iconSystemName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        // ここが「ShapeStyle が必要」な箇所。AnyView を返すとエラーになる。
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 10, y: 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    ContentView()
        .environmentObject(UserSession(previewUserId: "preview_user_123"))
}

