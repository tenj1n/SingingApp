import Foundation

enum BundleFileLocator {
    
    /// groups(黄フォルダ) は Bundle の subdirectory にならないことが多いので、
    /// "Songs", "Audio", そして root(nil) を順に探す。
    private static let candidateSubdirs: [String?] = ["Songs", "Audio", nil]
    
    static func findResource(name: String, ext: String) throws -> URL {
        for sub in candidateSubdirs {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        throw NSError(
            domain: "BundleFileLocator",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Bundle resource not found: \(name).\(ext)"]
        )
    }
    
    static func findByFileName(_ fileName: String) throws -> URL {
        let ns = fileName as NSString
        let name = ns.deletingPathExtension
        let ext  = ns.pathExtension.isEmpty ? "json" : ns.pathExtension
        return try findResource(name: name, ext: ext)
    }
    
    static func findJSON(named name: String) throws -> URL {
        return try findResource(name: name, ext: "json")
    }
}
