import SwiftUI

struct HomeView: View {
    @EnvironmentObject var userSession: UserSession
    
    private var hasUserId: Bool {
        guard let id = userSession.userId else { return false }
        return !id.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                background
                
                VStack(spacing: 18) {
                    header
                    
                    VStack(spacing: 14) {
                        // 録音
                        NavCard(
                            title: "録音して解析",
                            subtitle: "1曲録音してピッチを可視化",
                            systemImage: "mic.fill",
                            accent: .red,
                            isEnabled: hasUserId
                        ) {
                            RecordVoiceView()
                        }
                        
                        // 履歴
                        NavCard(
                            title: "履歴を見る",
                            subtitle: "過去の解析結果・コメント",
                            systemImage: "clock.arrow.circlepath",
                            accent: .orange,
                            isEnabled: hasUserId
                        ) {
                            // userId が確定してから遷移
                            HistoryListView(userId: userSession.userId!)
                        }
                        
                        // 成長
                        NavCard(
                            title: "成長を見る",
                            subtitle: "スコア推移をまとめて確認",
                            systemImage: "chart.line.uptrend.xyaxis",
                            accent: .blue,
                            isEnabled: hasUserId
                        ) {
                            GrowthView(userId: userSession.userId!)
                        }
                    }
                    
                    Spacer(minLength: 0)
                    
                    // デバッグ表示（小さく）
                    Text("userId: \(userSession.userId ?? "loading...")")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                        .padding(.bottom, 6)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SingingTrainer")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("歌唱トレーニングメニュー")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            
            Spacer()
            
            // 右上の装飾（音ゲーっぽいメーター風）
            VStack(alignment: .trailing, spacing: 6) {
                Text("STATUS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                
                HStack(spacing: 6) {
                    Capsule().fill(hasUserId ? Color.green.opacity(0.9) : Color.white.opacity(0.25))
                        .frame(width: 42, height: 6)
                    Capsule().fill(Color.white.opacity(0.18))
                        .frame(width: 26, height: 6)
                    Capsule().fill(Color.white.opacity(0.10))
                        .frame(width: 16, height: 6)
                }
            }
        }
        .padding(.bottom, 4)
    }
    
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.08, green: 0.06, blue: 0.16),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // 光る円（グロー）
            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 1)
                .offset(x: -140, y: -220)
            
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 420, height: 420)
                .blur(radius: 1)
                .offset(x: 170, y: 240)
            
            // 薄いグリッド（横線）
            VStack(spacing: 16) {
                ForEach(0..<18, id: \.self) { _ in
                    Rectangle()
                        .fill(.white.opacity(0.04))
                        .frame(height: 1)
                        .blur(radius: 0.2)
                }
            }
            .rotationEffect(.degrees(-10))
            .scaleEffect(1.15)
            .ignoresSafeArea()
        }
    }
}

// MARK: - NavCard

private struct NavCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let isEnabled: Bool
    let destination: () -> Destination
    
    var body: some View {
        Group {
            if isEnabled {
                NavigationLink {
                    destination()
                } label: {
                    cardBody
                }
                .buttonStyle(PressScaleStyle())   // ✅ ここで押下アニメ
            } else {
                cardBody
                    .opacity(0.55)
                    .overlay(
                        Text("initializing...")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.35), in: Capsule())
                            .padding(.trailing, 10)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    )
            }
        }
    }
    
    private var cardBody: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accent.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: accent.opacity(0.25), radius: 14, x: 0, y: 8)
                
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.55),
                            .white.opacity(0.18),
                            accent.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: accent.opacity(0.18), radius: 18, x: 0, y: 10)
        .contentShape(Rectangle()) // ✅ タップ領域を確実に
    }
}

// ✅ NavigationLink/Buttonに安全に効く押下アニメ
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environmentObject(UserSession(previewUserId: "preview_user_123"))
}
