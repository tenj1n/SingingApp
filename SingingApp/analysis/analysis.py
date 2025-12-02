# SingingApp/analysis/analysis.py

# --- imports ---
from pathlib import Path
import os
import numpy as np
import librosa
import matplotlib
matplotlib.use('Agg')  # GUI不要のバックエンド
import matplotlib.pyplot as plt

# --- constants (保存先フォルダ) ---
BASE_DIR   = Path(__file__).resolve().parent      # = SingingApp/analysis
SAMPLE_DIR = BASE_DIR / "sample01"
USER_DIR   = BASE_DIR / "user01"
SAMPLE_DIR.mkdir(exist_ok=True)
USER_DIR.mkdir(exist_ok=True)

# --- functions ---
def extract_pitch_array(wav_path: str):
    """ピッチ配列のみを抽出して返す（コメント生成やスコア評価に使う）"""
    try:
        y, sr = librosa.load(wav_path, sr=None, mono=True)
        pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
        pitch = np.max(pitches, axis=0)
        pitch[pitch == 0] = np.nan
        return pitch[~np.isnan(pitch)]  # NaNを除外
    except Exception as e:
        print(f"ピッチ抽出エラー: {e}")
        return None

def analyze_audio(wav_path: str, out_dir: Path = USER_DIR):
    """
    wavファイルからピッチと音量を解析してPNG保存。
    デフォルト保存先は USER_DIR（= SingingApp/analysis/user01）
    """
    out_dir = Path(out_dir); out_dir.mkdir(parents=True, exist_ok=True)

    try:
        y, sr = librosa.load(wav_path, sr=None, mono=True)
        pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
        pitch = np.max(pitches, axis=0); pitch[pitch == 0] = np.nan
        rms = librosa.feature.rms(y=y)[0]

        name = Path(wav_path).stem
        pitch_path  = out_dir / f'{name}_pitch.png'
        volume_path = out_dir / f'{name}_volume.png'

        # ピッチ
        plt.figure(figsize=(10, 4))
        plt.plot(pitch, label='Pitch (Hz)')
        plt.title('Pitch Over Time'); plt.xlabel('Frame'); plt.ylabel('Frequency (Hz)')
        plt.legend(); plt.tight_layout(); plt.savefig(pitch_path); plt.close()

        # 音量
        plt.figure(figsize=(10, 4))
        plt.plot(rms, label='Volume (RMS)')
        plt.title('Volume Over Time'); plt.xlabel('Frame'); plt.ylabel('RMS')
        plt.legend(); plt.tight_layout(); plt.savefig(volume_path); plt.close()

        print('解析成功:', pitch_path, volume_path)
        return str(pitch_path), str(volume_path)
    except Exception as e:
        print(f'解析失敗: {e}')
        return None, None

# --- optional: 手動テスト ---
if __name__ == "__main__":
    test_wav = "/Users/arima/Downloads/myvoice_44k_mono.wav"
    analyze_audio(test_wav, USER_DIR)
