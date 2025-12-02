//
//  ContentView.swift
//  SingingApp
//
//  Created by Koutarou Arima on 2025/07/01.
//

import SwiftUI

struct ContentView: View {
    @StateObject var recorder = AudioRecorder()
    @State private var isRecording = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🎤 録音トレーニング")
                .font(.title)
                .padding(.top)
            
            Button(action: {
                if isRecording {
                    recorder.stopRecording()
                } else {
                    recorder.startRecording()
                }
                isRecording.toggle()
            }) {
                Text(isRecording ? "録音停止" : "録音開始")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Button("▶️ 再生") {
                recorder.playRecording()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            
            Divider()
                .padding()
            
            Text("📝 フィードバック")
                .font(.headline)
            
            Text(recorder.feedbackMessage)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
            
            Text("📊 スコア: \(recorder.feedbackScore)/100")
                .font(.title2)
                .bold()
            
            Spacer()
            
            if let url = URL(string: recorder.pitchImageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(height: 150)
                } placeholder: {
                    ProgressView()
                }
                .padding(.top)
            }
            
            if let url = URL(string: recorder.volumeImageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(height: 150)
                } placeholder: {
                    ProgressView()
                }
                .padding(.bottom)
            }

        }
        .padding()
    }
}

#Preview {
    ContentView()
}
