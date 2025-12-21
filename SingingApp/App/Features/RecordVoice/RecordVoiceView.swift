import SwiftUI

struct RecordVoiceView: View {
    
    private let userId: String
    
    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var vm: RecordVoiceViewModel
    @StateObject private var karaoke = KaraokePlayer()
    
    @StateObject private var lyricsStore = LyricsStore()
    @State private var fontSize: CGFloat = 22
    
    @StateObject private var songStore = SongStore()
    
    init(userId: String = "user01") {
        self.userId = userId
        _vm = StateObject(wrappedValue: RecordVoiceViewModel(userId: userId))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                // 曲選択
                HStack {
                    Text("曲")
                    Spacer()
                    Picker("曲", selection: $songStore.selectedId) {
                        ForEach(songStore.songs) { song in
                            Text(song.title).tag(Optional(song.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // 歌詞
                LyricsView(store: lyricsStore, currentTime: karaoke.currentTime, fontSize: $fontSize)
                    .frame(height: 260)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // フォント
                HStack {
                    Button("A−") { fontSize = max(12, fontSize - 2) }
                    Button("A＋") { fontSize = min(60, fontSize + 2) }
                    Spacer()
                }
                
                // 再生コントロール
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button(karaoke.isPlaying ? "停止" : "曲を再生") {
                            if karaoke.isPlaying { karaoke.stop() } else { karaoke.play() }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                    }
                    
                    Toggle("歌手音源も流す", isOn: $karaoke.singerEnabled)
                    
                    HStack {
                        Text("歌手音量")
                        Slider(value: $karaoke.singerVolume, in: 0...1)
                    }
                    .opacity(karaoke.singerEnabled ? 1 : 0.4)
                    .disabled(!karaoke.singerEnabled)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
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
                
                // 録音/アップロード
                HStack(spacing: 12) {
                    if recorder.isRecording {
                        Button("録音停止") {
                            recorder.stopRecording()
                            karaoke.stop() // ★録音停止で曲も止める（止めたくないなら削除OK）
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
                                
                                // ★録音開始と同時に曲を先頭から再生
                                karaoke.stop()
                                
                                do {
                                    try recorder.startRecording()
                                    karaoke.play()
                                } catch {
                                    vm.errorMessage = "録音開始に失敗: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Button(vm.isUploading ? "アップロード中..." : "アップロードして比較へ") {
                        Task { await vm.uploadIfPossible(fileURL: recorder.recordedFileURL) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isUploading || recorder.isRecording || recorder.recordedFileURL == nil)
                }
                
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
            .onAppear {
                songStore.load()
                loadSelectedSong()
            }
            .onChange(of: songStore.selectedId) { _, _ in
                loadSelectedSong()
            }
            .onDisappear {
                karaoke.stop()
                if recorder.isRecording { recorder.stopRecording() }
            }
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
    
    private func loadSelectedSong() {
        guard let song = songStore.selected else { return }
        
        karaoke.stop()
        vm.errorMessage = nil
        
        // 歌詞ロード
        lyricsStore.load(fileName: song.lyrics)
        
        // 音源URLをBundleから探す
        do {
            let bgmURL = try BundleFileLocator.findByFileName(song.instrumental)
            let singerURL = try song.singer.map { try BundleFileLocator.findByFileName($0) }
            
            try karaoke.load(bgmURL: bgmURL, singerURL: singerURL)
        } catch {
            vm.errorMessage = "音源のロードに失敗: \(error.localizedDescription)"
        }
    }
}

private struct SessionIdBox: Identifiable, Hashable {
    let id: String
}

#Preview {
    RecordVoiceView()
}
