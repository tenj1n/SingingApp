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
    let cents: Double
}

struct PitchStats {
    let tolCents: Double
    let percentWithinTol: Double   // 0..1
    let meanAbsCents: Double
    let sampleCount: Int
}

enum PitchMath {
    
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
    
    static func alignMidiToNearestOctave(usrMidi: Double, refMidi: Double) -> Double {
        let k = round((refMidi - usrMidi) / 12.0)
        return usrMidi + 12.0 * k
    }
    
    static func centsDiff(usrMidi: Double, refMidi: Double) -> Double {
        (usrMidi - refMidi) * 100.0
    }
    
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
        
        let step = max(1, density.rawValue)
        
        var rawPairs: [(t: Double, usrMidi: Double, refMidi: Double, cents: Double)] = []
        rawPairs.reserveCapacity(n / step)
        
        for i in stride(from: 0, to: n, by: step) {
            let ut = usrTrack[i].t
            let rt = refTrack[i].t
            let t = min(ut, rt)
            
            guard let uHz = usrTrack[i].f0Hz, uHz > 0,
                  let rHz = refTrack[i].f0Hz, rHz > 0 else { continue }
            
            var uMidi = hzToMidi(uHz)
            let rMidi = hzToMidi(rHz)
            
            if octaveInvariant {
                uMidi = alignMidiToNearestOctave(usrMidi: uMidi, refMidi: rMidi)
            }
            
            let c = centsDiff(usrMidi: uMidi, refMidi: rMidi)
            rawPairs.append((t: t, usrMidi: uMidi, refMidi: rMidi, cents: c))
        }
        
        if rawPairs.isEmpty {
            return ([], [], PitchStats(tolCents: tolCents, percentWithinTol: 0, meanAbsCents: 0, sampleCount: 0))
        }
        
        rawPairs.sort { $0.t < $1.t }
        
        // ビン幅（秒）
        let binSec = max(0.10, 0.02 * Double(step))
        
        var overlay: [OverlayPoint] = []
        var errors: [ErrorPoint] = []
        overlay.reserveCapacity(rawPairs.count * 2)
        errors.reserveCapacity(rawPairs.count)
        
        var within = 0
        var sumAbs = 0.0
        var sample = 0
        
        var curBinIndex: Int? = nil
        var curTime: Double = 0
        var sumUsr = 0.0
        var sumRef = 0.0
        var sumC = 0.0
        var count = 0
        
        func flushBin() {
            guard count > 0 else { return }
            let u = sumUsr / Double(count)
            let r = sumRef / Double(count)
            let c = sumC / Double(count)
            
            overlay.append(.init(series: .user, time: curTime, midi: u))
            overlay.append(.init(series: .ref,  time: curTime, midi: r))
            errors.append(.init(time: curTime, cents: c))
            
            sample += 1
            let absC = abs(c)
            sumAbs += absC
            if absC <= tolCents { within += 1 }
            
            sumUsr = 0; sumRef = 0; sumC = 0; count = 0
        }
        
        for p in rawPairs {
            let k = Int(floor(p.t / binSec))
            if curBinIndex == nil {
                curBinIndex = k
                curTime = Double(k) * binSec
            } else if k != curBinIndex {
                flushBin()
                curBinIndex = k
                curTime = Double(k) * binSec
            }
            
            sumUsr += p.usrMidi
            sumRef += p.refMidi
            sumC += p.cents
            count += 1
        }
        flushBin()
        
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
        
        let title = "コメント"
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
                lines.append("改善ヒント：まずは短い区間に絞って、基準音に合わせる練習から始めましょう。")
            }
        }
        
        return (title, lines.joined(separator: "\n"))
    }
}
