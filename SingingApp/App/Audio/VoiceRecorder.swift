import Foundation
import AVFoundation

@MainActor
final class VoiceRecorder: ObservableObject {
    
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var recordedFileURL: URL?
    
    private var recorder: AVAudioRecorder?
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }
    
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        
        let url = Self.makeNewRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM), // WAV(PCM)
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.prepareToRecord()
        rec.record()
        
        recorder = rec
        recordedFileURL = url
        isRecording = true
    }
    
    func stopRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
    }
    
    /// ✅ 端末に残したくないので、アップロード後に消す用
    func deleteRecordedFile() {
        guard let url = recordedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        recordedFileURL = nil
    }
    
    private static func makeNewRecordingURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let ts = formatter.string(from: Date())
        let name = "user_voice_\(ts)_\(UUID().uuidString.prefix(8)).wav"
        return dir.appendingPathComponent(name)
    }
}
