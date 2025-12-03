# 01_user_pitch_extract_json.py
import os, json
from pathlib import Path
import numpy as np
import librosa

# 入力・出力（環境変数で上書き可能）
# - IN_WAV: 解析したいモノラル WAV ファイルのパス
# - OUT_JSON: 出力したい JSON ファイルのパス
#   （デフォルトはリポジトリ直下のSingingApp/analysis/user01/pitch.json）
IN_WAV = os.environ.get("IN_WAV", "/Users/arima/Downloads/myvoice_44k_mono.wav")
OUT    = os.environ.get("OUT_JSON", "SingingApp/analysis/user01/pitch.json")

# 解析
# librosa.load: 44100Hz にリサンプリングし、モノラル化して読み込み
# hop_length=256 は 44100Hz / 256 ≒ 172.3 fps（約5.8ms間隔）の時間解像度
y, sr = librosa.load(IN_WAV, sr=44100, mono=True)
hop = 256
# YIN アルゴリズムで基本周波数をフレームごとに推定
f0 = librosa.yin(y, fmin=80, fmax=800, sr=sr, frame_length=2048, hop_length=hop)
# 目立った発声区間のみを残すため、RMS が中央値の 30% 未満の区間を NaN にする
rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=hop).squeeze()
f0[(rms < np.median(rms)*0.3)] = np.nan
# 各フレームの時間（秒）を算出
t = librosa.times_like(f0, sr=sr, hop_length=hop)

# 保存
# 出力先ディレクトリが無ければ作成
Path(os.path.dirname(OUT)).mkdir(parents=True, exist_ok=True)
data = {
    "sr": sr, "hop": hop, "algo": "yin_simple",
    "track": [
        {"t": round(float(tt), 3),
         "f0_hz": (None if np.isnan(ff) else float(ff))}
        for tt, ff in zip(t, f0)
    ],
}
with open(OUT, "w") as f:
    json.dump(data, f)
print("wrote:", OUT, "frames:", len(t))