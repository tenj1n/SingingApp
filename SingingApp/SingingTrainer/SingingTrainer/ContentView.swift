import SwiftUI

struct ContentView: View {
    @StateObject private var store = LyricsStore()
    @State private var fontSize: CGFloat = 22
    
    @State private var showCompare = false
    
    var body: some View {
        NavigationStack {
            LyricsView(store: store, currentTime: nil, fontSize: $fontSize)
                .navigationTitle("歌詞")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("A−") { fontSize = max(12, fontSize - 2) }
                        Button("A＋") { fontSize = min(60, fontSize + 2) }
                        Button {
                            showCompare = true
                        } label: {
                            Label("比較グラフ", systemImage: "chart.xyaxis.line")
                        }
                    }
                }
        }
        .sheet(isPresented: $showCompare) {
            CompareView()
        }
        .onAppear {
            // ここを今の歌詞ファイル名に合わせる
            store.load(fileName: "orpheus_lyrics.json")
        }
    }
}

#Preview { ContentView() }
