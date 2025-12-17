//
//  ContentView.swift
//  SingingTrainer
//
//  Created by Koutarou Arima on 2025/12/04.
//

import SwiftUI

struct LyricsLine: Decodable, Identifiable {
    let id = UUID()
    let start: Double
    let end: Double
    let text: String
    private enum CodingKeys: String, CodingKey { case start, end, text }
}

final class LyricsStore: ObservableObject {
    @Published var lines: [LyricsLine] = []
    func load() {
        guard let url = Bundle.main.url(forResource: "lyrics", withExtension: "json") else {
            print("lyrics.json not found in bundle"); return
        }
        do {
            struct Root: Decodable { let lines: [LyricsLine] }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(Root.self, from: data)
            self.lines = decoded.lines
        } catch {
            print("lyrics.json decode error:", error)
        }
    }
}

struct ContentView: View {
    @StateObject private var store = LyricsStore()
    @State private var fontSize: CGFloat = 22
    
    // レイアウト調整
    private let blockSpacing: CGFloat = 10
    private let lineSpacing: CGFloat  = 3
    private let verticalPadding: CGFloat = 12
    
    // 画面表示（シート）
    @State private var showCompare = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: blockSpacing) {
                    ForEach(store.lines) { line in
                        Text(line.text)
                            .font(.system(size: fontSize))
                            .lineSpacing(lineSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, verticalPadding)
                    }
                }
                .padding(.horizontal)
            }
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
            CompareView()   // 既に作成した CompareView.swift を表示
        }
        .onAppear { store.load() }
    }
}
#Preview { ContentView() }
