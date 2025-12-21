import Foundation

@MainActor
final class SongStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published var selectedId: String? = nil
    
    var selected: Song? {
        guard let id = selectedId else { return songs.first }
        return songs.first(where: { $0.id == id }) ?? songs.first
    }
    
    func load() {
        do {
            let url = try BundleFileLocator.findJSON(named: "songs") // songs.json を探す
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(SongManifest.self, from: data)
            self.songs = decoded.songs
            if selectedId == nil {
                selectedId = decoded.songs.first?.id
            }
        } catch {
            print("songs.json load error:", error)
            self.songs = []
        }
    }
}
