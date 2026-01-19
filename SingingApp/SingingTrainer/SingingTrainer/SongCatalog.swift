import Foundation

// songs.json（アプリBundle）から id -> title を引けるようにする
final class SongCatalog {
    static let shared = SongCatalog()
    
    private var idToTitle: [String: String] = [:]
    
    private init() {
        load()
    }
    
    private func load() {
        guard let url = Bundle.main.url(forResource: "songs", withExtension: "json") else {
            print("SongCatalog: songs.json not found in Bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            // ✅ songs.json は { "songs": [ ... ] } の形
            let wrapper = try JSONDecoder().decode(SongsWrapper.self, from: data)
            
            self.idToTitle = Dictionary(uniqueKeysWithValues: wrapper.songs.map { ($0.id, $0.title) })
            print("SongCatalog: loaded \(idToTitle.count) songs")
            
        } catch {
            print("SongCatalog: failed to load songs.json: \(error)")
        }
    }
    
    func title(for songId: String) -> String? {
        idToTitle[songId]
    }
}

// ✅ songs.json のルート { "songs": [...] } 用
private struct SongsWrapper: Decodable {
    let songs: [BundleSong]
}

// ✅ songs 配列の中身（必要最低限）
private struct BundleSong: Decodable {
    let id: String
    let title: String
}
