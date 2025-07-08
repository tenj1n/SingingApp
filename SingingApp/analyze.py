#
#  analyze.py
#  SingingApp

#  Created by Koutarou Arima on 2025/07/07.

import librosa
import numpy as np
import matplotlib.pyplot as plt
import os

def extract_pitch_array(wav_path):
    try:
        y, sr = librosa.load(wav_path)
        pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
        pitch = np.max(pitches, axis=0)
        pitch[pitch == 0] = np.nan
        return pitch
    except Exception as e:
        print(f"ピッチ抽出エラー: {e}")
        return None


def analyze_audio(wav_path, output_dir='analysis'):
    """
    wavファイルからピッチと音量を解析してプロットを保存する
    """
    os.makedirs(output_dir, exist_ok=True)

    try:
        y, sr = librosa.load(wav_path)
        times = librosa.times_like(y, sr=sr)

        # ピッチ抽出（非ゼロの部分のみ対象）
        pitches, magnitudes = librosa.piptrack(y=y, sr=sr)
        pitch = np.max(pitches, axis=0)
        pitch[pitch == 0] = np.nan  # 0をNaNに置き換えてプロットで消す

        # 抑揚（音量）を振幅から抽出
        rms = librosa.feature.rms(y=y)[0]

        # ファイル名
        name = os.path.splitext(os.path.basename(wav_path))[0]

        # ピッチグラフ
        plt.figure(figsize=(10, 4))
        plt.plot(pitch, label='Pitch (Hz)')
        plt.title('Pitch Over Time')
        plt.xlabel('Frame')
        plt.ylabel('Frequency (Hz)')
        plt.legend()
        pitch_path = os.path.join(output_dir, f'{name}_pitch.png')
        plt.savefig(pitch_path)
        plt.close()

        # 音量グラフ
        plt.figure(figsize=(10, 4))
        plt.plot(rms, color='orange', label='Volume (RMS)')
        plt.title('Volume Over Time')
        plt.xlabel('Frame')
        plt.ylabel('RMS')
        plt.legend()
        volume_path = os.path.join(output_dir, f'{name}_volume.png')
        plt.savefig(volume_path)
        plt.close()

        print('解析成功:', pitch_path, volume_path)
        return pitch_path, volume_path

    except Exception as e:
        print(f'解析失敗: {e}')
        return None, None
