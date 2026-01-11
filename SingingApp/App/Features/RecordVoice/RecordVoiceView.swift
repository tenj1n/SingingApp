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
                songPickerRow
                lyricsSection
                fontRow
                playbackControls
                recordedFileRow
                recordUploadRow
                errorRow
                Spacer()
            }
            .padding()
            .navigationTitle("歌声を録音")
            
            // ✅ 曲が終わったら自動で録音停止 → 自動アップロード
            .onChange(of: karaoke.didFinish) { _, finished in
                guard finished else { return }
                guard recorder.isRecording else { return }
                stopRecordAndUpload(stopMusic: false)
            }
            
            .onAppear {
                _ = AnalysisAPI.shared
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
    
    // MARK: - Parts (分割して型チェック地獄を回避)
    
    private var songPickerRow: some View {
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
    }
    
    private var lyricsSection: some View {
        LyricsView(store: lyricsStore, currentTime: karaoke.currentTime, fontSize: $fontSize)
            .frame(height: 260)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var fontRow: some View {
        HStack {
            Button("A−") { fontSize = max(12, fontSize - 2) }
            Button("A＋") { fontSize = min(60, fontSize + 2) }
            Spacer()
        }
    }
    
    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(karaoke.isPlaying ? "停止" : "曲を再生") {
                    if karaoke.isPlaying {
                        karaoke.stop()
                    } else {
                        karaoke.playFromStart()
                    }
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
    }
    
    private var recordedFileRow: some View {
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
    }
    
    private var recordUploadRow: some View {
        HStack(spacing: 12) {
            if recorder.isRecording {
                Button("録音停止") {
                    stopRecordAndUpload(stopMusic: true)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("録音開始") {
                    startRecordingFlow()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Button(vm.isUploading ? "アップロード中..." : "アップロードして比較へ") {
                manualUploadFlow()
            }
            .buttonStyle(.bordered)
            .disabled(vm.isUploading || recorder.isRecording || recorder.recordedFileURL == nil)
        }
    }
    
    private var errorRow: some View {
        Group {
            if let msg = vm.errorMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Actions
    
    private func startRecordingFlow() {
        Task {
            let ok = await recorder.requestPermission()
            guard ok else {
                await MainActor.run {
                    vm.errorMessage = "マイク権限がありません（設定で許可してください）"
                }
                return
            }
            
            await MainActor.run {
                vm.errorMessage = nil
                karaoke.stop()
            }
            
            do {
                try await MainActor.run {
                    try recorder.startRecording()
                }
                await MainActor.run {
                    karaoke.playFromStart()
                }
            } catch {
                await MainActor.run {
                    vm.errorMessage = "録音開始に失敗: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func manualUploadFlow() {
        Task {
            guard let songId = songStore.selectedId else {
                await MainActor.run { vm.errorMessage = "曲が選択されていません" }
                return
            }
            
            let url = await MainActor.run { recorder.recordedFileURL }
            let ok = await vm.uploadOnlyReturnBool(fileURL: url, songId: songId)
            if ok {
                await MainActor.run {
                    recorder.deleteRecordedFile()
                }
            }
        }
    }
    
    /// 録音停止 → （必要なら曲停止）→ アップロード → 成功なら端末ファイル削除
    private func stopRecordAndUpload(stopMusic: Bool) {
        let url = recorder.recordedFileURL
        
        recorder.stopRecording()
        if stopMusic { karaoke.stop() }
        
        Task {
            guard let songId = songStore.selectedId else {
                await MainActor.run { vm.errorMessage = "曲が選択されていません" }
                return
            }
            
            let ok = await vm.uploadOnlyReturnBool(fileURL: url, songId: songId)
            if ok {
                await MainActor.run {
                    recorder.deleteRecordedFile()
                }
            }
        }
    }
    
    private func loadSelectedSong() {
        guard let song = songStore.selected else { return }
        
        karaoke.stop()
        vm.errorMessage = nil
        
        lyricsStore.load(fileName: song.lyrics)
        
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
