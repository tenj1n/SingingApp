import Foundation
import AVFoundation

@MainActor
final class KaraokePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double? = nil
    
    // ✅ 再生が「最後まで終わった」時だけ true にする
    @Published var didFinish: Bool = false
    
    @Published var singerEnabled: Bool = false {
        didSet { applySingerVolume() }
    }
    @Published var singerVolume: Double = 0.7 {
        didSet { applySingerVolume() }
    }
    
    private var bgm: AVAudioPlayer?
    private var singer: AVAudioPlayer?
    private var timer: Timer?
    
    func load(bgmURL: URL, singerURL: URL?) throws {
        stop()                // stop() 内で didFinish は false に戻す
        didFinish = false
        
        let bgmPlayer = try AVAudioPlayer(contentsOf: bgmURL)
        bgmPlayer.prepareToPlay()
        bgmPlayer.delegate = self
        self.bgm = bgmPlayer
        
        if let singerURL {
            let singerPlayer = try AVAudioPlayer(contentsOf: singerURL)
            singerPlayer.prepareToPlay()
            singerPlayer.delegate = self
            self.singer = singerPlayer
        } else {
            self.singer = nil
        }
        
        self.currentTime = 0
        applySingerVolume()
    }
    
    /// ✅ 先頭から再生（RecordVoiceView が呼んでいる想定）
    func playFromStart() {
        guard let bgm else { return }
        
        // ここで必ず false に戻す（前回の true が残らないように）
        didFinish = false
        
        bgm.currentTime = 0
        bgm.play()
        
        if let singer {
            singer.currentTime = 0
            applySingerVolume()
            singer.play()
        }
        
        isPlaying = true
        startTimer()
    }
    
    /// 互換：もし既存で play() を呼んでいる箇所があっても動くように
    func play() {
        playFromStart()
    }
    
    func stop() {
        // stop は「再生完了」ではないので didFinish を true にしない
        didFinish = false
        
        bgm?.stop()
        singer?.stop()
        isPlaying = false
        currentTime = nil
        stopTimer()
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentTime = self.bgm?.currentTime
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func applySingerVolume() {
        guard let singer else { return }
        singer.volume = Float(singerEnabled ? singerVolume : 0.0)
    }
    
    // ✅ ここだけで didFinish=true を出す（本当に最後まで再生された時のみ）
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // bgm が終わった時だけ「曲が終わった」と扱う
            if player === self.bgm {
                self.isPlaying = false
                self.stopTimer()
                self.didFinish = true
            }
        }
    }
}
