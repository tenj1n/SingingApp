# tools/01_user_pitch_extract_json.py
import os, json
from pathlib import Path
import numpy as np
import librosa

# 入力・出力（環境変数で上書き可能）
IN_WAV = os.environ.get("IN_WAV", "/Users/arima/Downloads/myvoice_44k_mono.wav")
OUT    = os.environ.get("OUT_JSON", "SingingApp/analysis/user01/pitch.json")

# 解析
y, sr = librosa.load(IN_WAV, sr=44100, mono=True)
hop = 256
f0 = librosa.yin(y, fmin=80, fmax=800, sr=sr, frame_length=2048, hop_length=hop)
rms = librosa.feature.rms(y=y, frame_length=2048, hop_length=hop).squeeze()
f0[(rms < np.median(rms)*0.3)] = np.nan
t = librosa.times_like(f0, sr=sr, hop_length=hop)

# 保存
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
