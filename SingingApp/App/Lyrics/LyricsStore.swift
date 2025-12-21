import Foundation

@MainActor
final class LyricsStore: ObservableObject {
    @Published var lines: [LyricsLine] = []
    
    /// fileName: "orpheus_lyrics.json" のような名前
    func load(fileName: String) {
        do {
            let url = try BundleFileLocator.findByFileName(fileName)
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(LyricsRoot.self, from: data)
            self.lines = decoded.lines
        } catch {
            print("Lyrics load error:", error)
            self.lines = []
        }
    }
}
