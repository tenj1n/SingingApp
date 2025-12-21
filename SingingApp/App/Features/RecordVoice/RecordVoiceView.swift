import SwiftUI

struct RecordVoiceView: View {
    
    private let userId: String
    
    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var vm: RecordVoiceViewModel
    
    init(userId: String = "user01") {
        self.userId = userId
        _vm = StateObject(wrappedValue: RecordVoiceViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                
                // 録音ファイル表示
                Group {
                    if let url = recorder.recordedFileURL {
                        Text("録音: \(url.lastPathComponent)")
                            .font(.footnote)
                            .lineLimit(1)
                    } else {
                        Text("まだ録音していません")
                            .font(.footnote)
                    }
                }
                
                // 録音ボタン
                if recorder.isRecording {
                    Button("録音停止") {
                        recorder.stopRecording()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("録音開始") {
                        Task {
                            let ok = await recorder.requestPermission()
                            guard ok else {
                                vm.errorMessage = "マイク権限がありません（設定で許可してください）"
                                return
                            }
                            do {
                                try recorder.startRecording()
                            } catch {
                                vm.errorMessage = "録音開始に失敗: \(error.localizedDescription)"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // アップロード
                Button(vm.isUploading ? "アップロード中..." : "録音をアップロードして比較へ") {
                    Task { await vm.uploadIfPossible(fileURL: recorder.recordedFileURL) }
                }
                .buttonStyle(.bordered)
                .disabled(vm.isUploading || recorder.isRecording || recorder.recordedFileURL == nil)
                
                if let msg = vm.errorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("歌声を録音")
            .navigationDestination(
                item: Binding(
                    get: { vm.nextSessionId.map { SessionIdBox(id: $0) } },
                    set: { _ in }
                )
            ) { box in
                CompareView(sessionId: box.id)
            }
        }
    }
}

// navigationDestination(item:) 用の箱
private struct SessionIdBox: Identifiable, Hashable {
    let id: String
}

#Preview {
    RecordVoiceView()
}
