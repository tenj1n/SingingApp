import Foundation
import AVFoundation

@MainActor
final class KaraokePlayer: ObservableObject {
    
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double? = nil
    
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
        stop()
        
        let bgmPlayer = try AVAudioPlayer(contentsOf: bgmURL)
        bgmPlayer.prepareToPlay()
        self.bgm = bgmPlayer
        
        if let singerURL {
            let singerPlayer = try AVAudioPlayer(contentsOf: singerURL)
            singerPlayer.prepareToPlay()
            self.singer = singerPlayer
        } else {
            self.singer = nil
        }
        
        self.currentTime = 0
        applySingerVolume()
    }
    
    func play() {
        guard let bgm else { return }
        
        // 2つを同時に0秒から（必要ならここを「現在位置から再開」でもOK）
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
    
    func stop() {
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
}
