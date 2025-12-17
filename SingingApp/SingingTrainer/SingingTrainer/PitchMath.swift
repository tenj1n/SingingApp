import Foundation

enum Density: Int, CaseIterable, Identifiable {
    case x1 = 1, x2 = 2, x5 = 5, x10 = 10, x20 = 20, x50 = 50
    var id: Int { rawValue }
    var label: String { "×\(rawValue)" }
}

enum PitchSeries: String {
    case user = "自分"
    case ref  = "歌手"
}

struct OverlayPoint: Identifiable {
    let id = UUID()
    let series: PitchSeries
    let time: Double
    let midi: Double
}

struct ErrorPoint: Identifiable {
    let id = UUID()
    let time: Double
    let cents: Double   // 0基準。+は高い / -は低い
}

struct PitchStats {
    let tolCents: Double
    let percentWithinTol: Double   // 0..1
    let meanAbsCents: Double
    let sampleCount: Int
}

enum PitchMath {
    
    // Hz -> MIDI (A4=69)
    static func hzToMidi(_ hz: Double) -> Double {
        69.0 + 12.0 * log2(hz / 440.0)
    }
    
    static func midiToNoteNameJP(_ midi: Double) -> String {
        let names = ["ド","ド#","レ","レ#","ミ","ファ","ファ#","ソ","ソ#","ラ","ラ#","シ"]
        let m = Int(round(midi))
        let note = (m % 12 + 12) % 12
        let octave = (m / 12) - 1
        return "\(names[note])\(octave)"
    }
    
    static func centsDiff(usrHz: Double, refHz: Double) -> Double {
        1200.0 * log2(usrHz / refHz)
    }
    
    /// ref に対して usr を「最も近いオクターブ」に寄せる（±12の倍数）
    static func alignMidiToNearestOctave(usrMidi: Double, refMidi: Double) -> Double {
        let k = round((refMidi - usrMidi) / 12.0)
        return usrMidi + 12.0 * k
    }
    
    /// データ作成（軽量化の要：ここで間引き＋ビニング）
    static func makeDisplayData(
        usr: PitchTrack?,
        ref: PitchTrack?,
        density: Density,
        octaveInvariant: Bool,
        tolCents: Double
    ) -> (overlay: [OverlayPoint], errors: [ErrorPoint], stats: PitchStats) {
        
        let usrTrack = usr?.track ?? []
        let refTrack = ref?.track ?? []
        let n = min(usrTrack.count, refTrack.count)
        if n == 0 {
            return ([], [], PitchStats(tolCents: tolCents, percentWithinTol: 0, meanAbsCents: 0, sampleCount: 0))
        }
        
        let step = density.rawValue
        
        // --- ペア比較（同じindexを同時刻扱い） ---
        // 点が多すぎると重いので、まず step で間引いてから cents を作る
        var rawPairs: [(t: Double, usrMidi: Double, refMidi: Double, cents: Double)] = []
        rawPairs.reserveCapacity(n / step)
        
        for i in stride(from: 0, to: n, by: step) {
            let ut = usrTrack[i].t
            let rt = refTrack[i].t
            let t = min(ut, rt)
            
            guard let uHz = usrTrack[i].f0Hz, uHz > 0,
                  let rHz = refTrack[i].f0Hz, rHz > 0 else { continue }
            
            let uMidi = hzToMidi(uHz)
            let rMidi = hzToMidi(rHz)
            
            let uAlignedMidi = octaveInvariant ? alignMidiToNearestOctave(usrMidi: uMidi, refMidi: rMidi) : uMidi
            let uAlignedHz = 440.0 * pow(2.0, (uAlignedMidi - 69.0) / 12.0)
            let c = centsDiff(usrHz: uAlignedHz, refHz: rHz)
            
            rawPairs.append((t: t, usrMidi: uAlignedMidi, refMidi: rMidi, cents: c))
        }
        
        // --- さらに軽くする：時間ビンで平均化（ギザギザを減らして見やすくする） ---
        // density が粗いほど binSec も少し大きくして “点数” を減らす
        let binSec = max(0.10, 0.02 * Double(step))  // 例: x10なら0.2秒程度
        var bins: [Int: (sumUsr: Double, sumRef: Double, sumC: Double, count: Int, time: Double)] = [:]
        bins.reserveCapacity(rawPairs.count / 3)
        
        for p in rawPairs {
            let k = Int(floor(p.t / binSec))
            if var b = bins[k] {
                b.sumUsr += p.usrMidi
                b.sumRef += p.refMidi
                b.sumC += p.cents
                b.count += 1
                bins[k] = b
            } else {
                bins[k] = (sumUsr: p.usrMidi, sumRef: p.refMidi, sumC: p.cents, count: 1, time: Double(k) * binSec)
            }
        }
        
        let sortedKeys = bins.keys.sorted()
        var overlay: [OverlayPoint] = []
        var errors: [ErrorPoint] = []
        overlay.reserveCapacity(sortedKeys.count * 2)
        errors.reserveCapacity(sortedKeys.count)
        
        var within = 0
        var sumAbs = 0.0
        var sample = 0
        
        for k in sortedKeys {
            guard let b = bins[k] else { continue }
            let t = b.time
            let u = b.sumUsr / Double(b.count)
            let r = b.sumRef / Double(b.count)
            let c = b.sumC / Double(b.count)
            
            overlay.append(.init(series: .user, time: t, midi: u))
            overlay.append(.init(series: .ref,  time: t, midi: r))
            errors.append(.init(time: t, cents: c))
            
            sample += 1
            let absC = abs(c)
            sumAbs += absC
            if absC <= tolCents { within += 1 }
        }
        
        let percent = sample > 0 ? Double(within) / Double(sample) : 0.0
        let meanAbs = sample > 0 ? (sumAbs / Double(sample)) : 0.0
        
        let stats = PitchStats(
            tolCents: tolCents,
            percentWithinTol: percent,
            meanAbsCents: meanAbs,
            sampleCount: sample
        )
        
        return (overlay, errors, stats)
    }
    
    static func verdictJP(_ v: String?) -> String {
        switch v {
        case "mostly_ok": return "おおむね良い"
        case "needs_work": return "要改善"
        case "good": return "良い"
        default: return v ?? "不明"
        }
    }
    
    static func makeCommentJP(stats: PitchStats, summary: AnalysisSummary?) -> (title: String, body: String) {
        let score = stats.percentWithinTol * 100.0
        let tol = stats.tolCents
        let verdict = verdictJP(summary?.verdict)
        
        var title = "コメント"
        var lines: [String] = []
        
        lines.append("判定：\(verdict)")
        lines.append("一致率（±\(Int(tol)) cents）：\(String(format: "%.1f", score)) 点")
        lines.append("平均ズレ（絶対値）：\(String(format: "%.1f", stats.meanAbsCents)) cents")
        
        if let reason = summary?.reason, !reason.isEmpty {
            lines.append("")
            lines.append("理由：\(reason)")
        }
        if let tips = summary?.tips, !tips.isEmpty {
            lines.append("")
            lines.append("改善ヒント：\(tips)")
        } else {
            lines.append("")
            if score >= 80 {
                lines.append("改善ヒント：狙った音の入り（出だし）と語尾の安定に意識を置くと、さらに伸びます。")
            } else if score >= 50 {
                lines.append("改善ヒント：低い/高い側に外れやすい区間を探して、そこだけ繰り返し練習すると効率が良いです。")
            } else {
                lines.append("改善ヒント：まずはサビ前後など短い区間に絞って、基準音に合わせる練習から始めましょう。")
            }
        }
        
        return (title, lines.joined(separator: "\n"))
    }
}
