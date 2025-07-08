//
//  AudioRecorder.swift
//  SingingApp
//
//  Created by Koutarou Arima on 2025/07/01.
//

import Foundation
import AVFoundation

class AudioRecorder: ObservableObject {
    var audioRecorder: AVAudioRecorder?
    var audioPlayer: AVAudioPlayer?
    let fileName = "recordedAudio.m4a"
    
    @Published var feedbackMessage: String = ""
    @Published var feedbackScore: Int = 0
    
    var audioURL: URL {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docDir.appendingPathComponent(fileName)
    }
    
    func startRecording() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            print("録音開始")
        } catch {
            print("録音エラー: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        print("録音停止")
        sendToServer()
    }
    
    func playRecording() {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.play()
            print("再生中")
        } catch {
            print("再生エラー: \(error.localizedDescription)")
        }
    }
    
    func sendToServer() {
        guard let audioData = try? Data(contentsOf: audioURL) else {
            print("録音ファイル読み込み失敗")
            return
        }
        
        guard let url = URL(string: "http://192.168.11.28:5000/upload") else {
            print("URLが不正です")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"record.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            if let error = error {
                print("送信失敗: \(error.localizedDescription)")
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("JSON解析失敗")
                return
            }
            
            DispatchQueue.main.async {
                self.feedbackMessage = json["feedback"] as? String ?? "コメントなし"
                self.feedbackScore = json["score"] as? Int ?? 0
                print("サーバー応答:", self.feedbackMessage, self.feedbackScore)
            }
        }.resume()
    }
}
