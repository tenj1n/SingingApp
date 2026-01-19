import Foundation

enum Density: Int, CaseIterable, Identifiable {
    case x1 = 1, x2 = 2, x5 = 5, x10 = 10, x20 = 20, x50 = 50
    var id: Int { rawValue }
    var label: String { "×\(rawValue)" }
    var multiplier: Int { rawValue }
}

struct OverlayPoint: Identifiable {
    enum Series: String {
        case ref = "歌手"
        case usr = "自分"
    }
    let id = UUID()
    let time: Double
    let midi: Double?
    let series: Series
}

struct ErrorPoint: Identifiable {
    let id = UUID()
    let time: Double
    let cents: Double
}

enum PitchMath {
    static func hzToMidi(_ hz: Double) -> Double {
        guard hz > 0 else { return 0 }
        return 69.0 + 12.0 * log2(hz / 440.0)
    }
    
    static func centsDiff(refHz: Double, usrHz: Double) -> Double {
        guard refHz > 0, usrHz > 0 else { return 0 }
        return 1200.0 * log2(usrHz / refHz)
    }
    
    static func wrapCentsToOctave(_ cents: Double) -> Double {
        var x = cents
        while x > 600 { x -= 1200 }
        while x < -600 { x += 1200 }
        return x
    }
    
    // ==================================================
    // ✅ スコア設計（ここを修正）
    // ==================================================
    static func scoreFromMeanAbsCents(meanAbsCents: Double) -> Double {
        if !meanAbsCents.isFinite { return 0 }
        
        // 0〜600c にクリップ（wrapしてる場合も最大600付近）
        let x = max(0.0, min(600.0, meanAbsCents))
        
        // ✅ k は 1e-5 オーダー（x^2 なので）
        // 目安：
        // 40c  ≈ 96.8
        // 100c ≈ 81.9
        // 200c ≈ 44.9
        // 233c ≈ 33〜35 点
        // 300c ≈ 16.5
        // 600c ≈ 0 点付近
        let k = 2.0e-5
        
        let raw = 100.0 * exp(-k * x * x)
        
        // 600c を 0 に寄せて 0〜100 に正規化
        let base = 100.0 * exp(-k * 600.0 * 600.0) // 600c 時の値
        let normalized = (raw - base) / max(1e-9, (100.0 - base)) * 100.0
        
        return max(0.0, min(100.0, normalized))
    }

    /// summary.verdict を日本語表示にする
    static func verdictJP(_ verdict: String?) -> String {
        guard let v = verdict?.trimmingCharacters(in: .whitespacesAndNewlines),
              !v.isEmpty else {
            return "不明"
        }
        
        switch v.lowercased() {
        case "great", "excellent":
            return "非常に良い"
        case "good":
            return "良い"
        case "ok", "fair":
            return "普通"
        case "bad", "poor":
            return "悪い"
        case "ng":
            return "NG"
        default:
            return v
        }
    }
    static func shiftUsrHzToClosestOctave(refHz: Double, usrHz: Double) -> Double {
        guard refHz > 0, usrHz > 0 else { return usrHz }
        
        var best = usrHz
        var bestAbs = abs(centsDiff(refHz: refHz, usrHz: usrHz))
        
        var h = usrHz
        
        // 上方向へ最大±3オクターブくらい探索
        for _ in 0..<3 {
            h *= 2
            let a = abs(centsDiff(refHz: refHz, usrHz: h))
            if a < bestAbs { bestAbs = a; best = h }
        }
        
        // 下方向へ最大±3オクターブくらい探索
        h = usrHz
        for _ in 0..<3 {
            h /= 2
            let a = abs(centsDiff(refHz: refHz, usrHz: h))
            if a < bestAbs { bestAbs = a; best = h }
        }
        
        return best
    }

}
