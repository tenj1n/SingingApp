import argparse, json
import numpy as np

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="in_path", required=True)
    ap.add_argument("--out", dest="out_path", required=True)
    ap.add_argument("--sr", type=int, default=44100)
    ap.add_argument("--hop", type=int, default=256)
    ap.add_argument("--fmin", type=float, default=65.0)    # C2
    ap.add_argument("--fmax", type=float, default=1046.5)  # C6
    args = ap.parse_args()

    import librosa

    y, sr = librosa.load(args.in_path, sr=args.sr, mono=True)

    f0, voiced_flag, voiced_prob = librosa.pyin(
        y,
        fmin=args.fmin,
        fmax=args.fmax,
        sr=sr,
        hop_length=args.hop
    )

    n = len(f0)
    t = (np.arange(n) * args.hop) / sr

    track = []
    for i in range(n):
        f = f0[i]
        track.append({
            "t": float(t[i]),
            "f0_hz": None if (f is None or (isinstance(f, float) and np.isnan(f))) else float(f)
        })

    out = {
        "algo": "pyin",
        "sr": int(sr),
        "hop": int(args.hop),
        "track": track
    }

    with open(args.out_path, "w", encoding="utf-8") as fw:
        json.dump(out, fw, ensure_ascii=False)

    print("WROTE:", args.out_path)
    print("sr=", sr, "hop=", args.hop, "frames=", len(track))

if __name__ == "__main__":
    main()
