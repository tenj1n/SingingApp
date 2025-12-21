import SwiftUI

struct LyricsView: View {
    
    @ObservedObject var store: LyricsStore
    let currentTime: Double?       // nil ならハイライトなし
    @Binding var fontSize: CGFloat
    
    private let blockSpacing: CGFloat = 10
    private let lineSpacing: CGFloat  = 3
    private let verticalPadding: CGFloat = 12
    
    private func isActive(_ line: LyricsLine) -> Bool {
        guard let t = currentTime else { return false }
        return line.start <= t && t < line.end
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: blockSpacing) {
                ForEach(store.lines) { line in
                    Text(line.text)
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, verticalPadding)
                        .background(isActive(line) ? Color.primary.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    @Previewable @State var size: CGFloat = 22
    let s = LyricsStore()
    s.lines = [
        .init(start: 0, end: 2, text: "テスト1"),
        .init(start: 2, end: 4, text: "テスト2")
    ]
    return LyricsView(store: s, currentTime: 2.5, fontSize: $size)
}
