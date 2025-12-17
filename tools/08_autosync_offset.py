# tools/08_autosync_offset.py
import os, json, math, subprocess, shutil
from pathlib import Path
import numpy as np

REF_JSON   = os.environ.get("REF_JSON",  "SingingApp/analysis/sample01/pitch.json")
USR_JSON   = os.environ.get("USR_JSON",  "SingingApp/analysis/user01/pitch.json")
OUT_SHIFT  = os.environ.get("OUT_SHIFT", "SingingApp/analysis/user01/pitch.shifted.json")
OUT_EVT    = os.environ.get("OUT_EVT",   "SingingApp/analysis/user01/events.json")
MAX_SHIFT  = float(os.environ.get("AUTOSYNC_MAX", "3.0"))  # ±この秒数で探索
MIN_DUR    = 0.20  # 20ms×10=約0.2s相当（イベント最小長）

Path(os.path.dirname(OUT_SHIFT)).mkdir(parents=True, exist_ok=True)

def load_pitch(path):
    d = json.load(open(path))
    t = np.array([float(x["t"]) for x in d["track"]], dtype=float)
    f = np.array([np.nan if x["f0_hz"] is None else float(x["f0_hz"]) for x in d["track"]], dtype=float)
    sr = int(d.get("sr", 44100))
    hop = int(d.get("hop", 256))
    return d, t, f, sr, hop

def voiced_mask(f):
    return (~np.isnan(f)) & (f > 0)

def crosscorr_offset(tR, mR, tU, mU, max_shift):
    """
    シンプルな相互相関。時間軸は参照のフレーム時間に合わせる。
    """
    # 参照のフレーム数にユーザーを最近傍で合わせる
    idx = np.searchsorted(tU, tR)
    idx = np.clip(idx, 1, len(tU)-1)
    choose = np.where(np.abs(tU[idx-1]-tR) <= np.abs(tU[idx]-tR), idx-1, idx)
    mU_on_R = mU[choose].astype(float)

    # シフト探索（フレーム単位）
    dt = float(np.median(np.diff(tR))) if len(tR) > 1 else 0.01
    max_shift_frames = int(round(max_shift / dt))
    best_score = -1.0
    best_k = 0
    for k in range(-max_shift_frames, max_shift_frames+1):
        if k < 0:
            a = mR[-k:]; b = mU_on_R[:len(a)]
        elif k > 0:
            a = mR[:-k]; b = mU_on_R[k:k+len(a)]
        else:
            a = mR; b = mU_on_R
        if len(a) < 10:
            continue
        score = np.dot(a.astype(float), b.astype(float))
        if score > best_score:
            best_score = score
            best_k = k
    # フレーム→秒
    return best_k * dt, best_score

def shift_user_pitch(dU, shift_sec):
    # 時刻にシフトを加えるだけ（データ密度は変えない）
    tr = []
    for p in dU["track"]:
        tr.append({"t": float(p["t"]) + float(shift_sec),
                   "f0_hz": p["f0_hz"]})
    out = dict(dU)
    out["track"] = tr
    out["autosync_shift_sec"] = shift_sec
    return out

def compare_make_events(dR, dU, tol_cents=40.0, min_event_sec=0.20):
    # 既存02の縮約版：セント差を算出→連続区間をイベント化
    tR = np.array([float(p["t"]) for p in dR["track"]], float)
    fR = np.array([np.nan if p["f0_hz"] is None else float(p["f0_hz"]) for p in dR["track"]], float)
    tU = np.array([float(p["t"]) for p in dU["track"]], float)
    fU = np.array([np.nan if p["f0_hz"] is None else float(p["f0_hz"]) for p in dU["track"]], float)

    # 時間合わせ（最近傍）
    idx = np.searchsorted(tU, tR)
    idx = np.clip(idx, 1, len(tU)-1)
    choose = np.where(np.abs(tU[idx-1]-tR) <= np.abs(tU[idx]-tR), idx-1, idx)
    fU2 = fU[choose]

    mask = (~np.isnan(fR)) & (~np.isnan(fU2)) & (fR>0) & (fU2>0)
    cents = np.full_like(fR, np.nan, dtype=float)
    cents[mask] = 1200.0 * np.log2(fU2[mask] / fR[mask])

    fps = dR.get("sr", 44100) / dR.get("hop", 256)
    min_frames = max(1, int(math.ceil(min_event_sec * fps)))

    def seg_from_mask(msk):
        ev=[]
        s=None
        for i,flag in enumerate(msk):
            if flag and s is None: s=i
            if (not flag or i==len(msk)-1) and s is not None:
                e = i if not flag else i+1
                if e - s >= min_frames:
                    ev.append((s,e))
                s=None
        return ev

    ev=[]
    # 高すぎ/低すぎ
    hi = cents >  tol_cents
    lo = cents < -tol_cents
    for s,e in seg_from_mask(lo):
        seg=cents[s:e]; tr=tR[s:e]
        ev.append({"start": float(round(tr[0],3)),
                   "end":   float(round(tr[-1],3)),
                   "type":  "pitch_low",
                   "avg_cents": float(round(np.nanmean(seg),1)),
                   "max_cents": float(round(np.nanmax(np.abs(seg))*np.sign(np.nanmean(seg)),1))})
    for s,e in seg_from_mask(hi):
        seg=cents[s:e]; tr=tR[s:e]
        ev.append({"start": float(round(tr[0],3)),
                   "end":   float(round(tr[-1],3)),
                   "type":  "pitch_high",
                   "avg_cents": float(round(np.nanmean(seg),1)),
                   "max_cents": float(round(np.nanmax(np.abs(seg))*np.sign(np.nanmean(seg)),1))})

    # 参照は有声だがユーザー無声
    uv = (~np.isnan(fR)) & (fR>0) & (np.isnan(fU2) | (fU2<=0))
    for s,e in seg_from_mask(uv):
        tr=tR[s:e]
        ev.append({"start": float(round(tr[0],3)),
                   "end":   float(round(tr[-1],3)),
                   "type":  "unvoiced_miss"})

    ev.sort(key=lambda x: x["start"])
    return ev

def main():
    dR, tR, fR, srR, hopR = load_pitch(REF_JSON)
    dU, tU, fU, srU, hopU = load_pitch(USR_JSON)

    mR = voiced_mask(fR).astype(int)
    mU = voiced_mask(fU).astype(int)

    shift_sec, score = crosscorr_offset(tR, mR, tU, mU, MAX_SHIFT)
    print(f"autosync shift: {shift_sec:+.3f} sec (score={score:.1f})")

    dU_shift = shift_user_pitch(dU, shift_sec)
    json.dump(dU_shift, open(OUT_SHIFT,"w"), ensure_ascii=False, indent=2)

    ev = compare_make_events(dR, dU_shift, tol_cents=40.0, min_event_sec=MIN_DUR)
    json.dump(ev, open(OUT_EVT,"w"), ensure_ascii=False, indent=2)

    print("wrote:", OUT_SHIFT, "and", OUT_EVT, "events:", len(ev))

if __name__ == "__main__":
    main()
