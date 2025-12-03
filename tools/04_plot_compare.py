# tools/04_plot_compare.py
# Compare pitch (reference vs you) and show cents difference clearly-zoomable.
# Env vars (optional):
#   START_SEC, END_SEC : focus window (e.g., 0 and 90). Omit to show full.
#   TOL_CENTS          : acceptable band (default 40)
#   SMOOTH_SEC         : smoothing window seconds for cents (default 2.0)

import os, json, math
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

# ---------- Config ----------
REF_JSON = Path("SingingApp/analysis/sample01/pitch.json")
USR_JSON = Path("SingingApp/analysis/user01/pitch.json")
EVT_JSON = Path("SingingApp/analysis/user01/events.json")  # あれば色塗りに使う
OUT_PNG  = Path("SingingApp/analysis/user01/compare.png")

TOL_CENTS   = float(os.getenv("TOL_CENTS", 40))
SMOOTH_SEC  = float(os.getenv("SMOOTH_SEC", 2.0))
START_SEC   = os.getenv("START_SEC")
END_SEC     = os.getenv("END_SEC")
START_SEC   = None if START_SEC in (None, "") else float(START_SEC)
END_SEC     = None if END_SEC   in (None, "") else float(END_SEC)

# ---------- Helpers ----------
def load_pitch_json(p):
    d = json.load(open(p))
    t = np.array([x["t"] for x in d["track"]], float)
    f = np.array([np.nan if x["f0_hz"] is None else float(x["f0_hz"]) for x in d["track"]], float)
    sr, hop = int(d["sr"]), int(d["hop"])
    return t, f, sr, hop

def align_to_ref(t_ref, f_ref, t_usr, f_usr):
    idx = np.searchsorted(t_usr, t_ref)
    idx = np.clip(idx, 1, len(t_usr)-1)
    choose = np.where(np.abs(t_usr[idx-1]-t_ref) <= np.abs(t_usr[idx]-t_ref), idx-1, idx)
    return f_usr[choose]

def cents_diff(f_ref, f_usr):
    diff = np.full_like(f_ref, np.nan, dtype=float)
    mask = (~np.isnan(f_ref)) & (~np.isnan(f_usr)) & (f_ref>0) & (f_usr>0)
    diff[mask] = 1200.0*np.log2(f_usr[mask]/f_ref[mask])
    return diff

def nan_moving_avg(y, win):
    """NaN を無視した移動平均。win は奇数に丸める。"""
    if win < 1: return y.copy()
    win = int(max(1, round(win)))
    if win % 2 == 0: win += 1
    k = np.ones(win, dtype=float)

    v = np.where(np.isnan(y), 0.0, y)
    val = np.convolve(v, k, mode="same")
    cnt = np.convolve(np.where(np.isnan(y), 0.0, 1.0), k, mode="same")
    out = np.full_like(y, np.nan, dtype=float)
    nz = cnt > 0
    out[nz] = val[nz]/cnt[nz]
    return out

def window_slice(t, *arrays, start=None, end=None):
    """
    時間配列 t を基準に [start, end] 秒の窓で切り出し。
    t も含めて返す（= 常に 1 + len(arrays) 本を返す）。
    """
    if start is None and end is None:
        sl = slice(None)
    else:
        s = 0 if start is None else np.searchsorted(t, start, side="left")
        e = len(t) if end is None else np.searchsorted(t, end, side="right")
        s = max(0, min(s, len(t)))
        e = max(s, min(e, len(t)))
        sl = slice(s, e)

    # t も含めて返すのがポイント
    return sl, (t[sl],) + tuple(a[sl] for a in arrays)

def load_events(ev_path):
    if not ev_path.exists(): 
        return {"low":[], "high":[], "unv":[]}
    ev = json.load(open(ev_path))
    low, high, unv = [], [], []
    for e in ev:
        t1, t2 = float(e["start"]), float(e.get("end", e["start"]))
        ty = e["type"]
        if ty == "pitch_low": low.append((t1,t2))
        elif ty == "pitch_high": high.append((t1,t2))
        elif ty == "unvoiced_miss": unv.append((t1,t2))
    return {"low":low, "high":high, "unv":unv}

# ---------- Load & compute ----------
tR, fR, sr, hop = load_pitch_json(REF_JSON)
tU, fU, _, _    = load_pitch_json(USR_JSON)
fU_on_R = align_to_ref(tR, fR, tU, fU)
diff_c  = cents_diff(fR, fU_on_R)

# スムージング（秒→フレーム）
fps = sr/float(hop)
win = max(1, int(round(SMOOTH_SEC*fps)))
diff_s = nan_moving_avg(diff_c, win)

# まず切り出し（ここが “拡大できない” を直すコア）
sl, (tR_w, fR_w, fU_w, diff_w, diff_s_w) = window_slice(tR, fR, fU_on_R, diff_c, diff_s,
                                                        start=START_SEC, end=END_SEC)

# イベント（あれば）も切り出し
events = load_events(EVT_JSON)
def clip_spans(spans, st, en):
    if st is None and en is None: return spans
    r=[]
    for a,b in spans:
        aa = a if st is None else max(a, st)
        bb = b if en is None else min(b, en)
        if bb > aa: r.append((aa,bb))
    return r
events_w = {
    "low": clip_spans(events["low"], START_SEC, END_SEC),
    "high": clip_spans(events["high"], START_SEC, END_SEC),
    "unv": clip_spans(events["unv"], START_SEC, END_SEC),
}

# 下段 y 軸レンジはデータに合わせて左右対称に
abs_max = np.nanpercentile(np.abs(diff_w), 98) if np.isfinite(diff_w).any() else 200
ymax = max(TOL_CENTS*2, abs_max)
ymax = float(min(max(ymax, 120), 4000))  # 暴れ防止

# ---------- Plot ----------
plt.close("all")
fig, (ax1, ax2) = plt.subplots(
    2, 1, figsize=(18, 7.5), height_ratios=[3,1.6], constrained_layout=True
)
# 右側に凡例スペース
fig.subplots_adjust(right=0.82)

# 上段：ピッチ
ax1.plot(tR_w, fR_w, lw=1.2, label="Reference (singer)")
ax1.plot(tR_w, fU_w, lw=1.2, label="You")

# 背景塗り（イベント）
def shade(spans, color, alpha):
    for a,b in spans:
        ax1.axvspan(a, b, color=color, alpha=alpha, linewidth=0)

shade(events_w["unv"],  "#6abf69", 0.20)  # no voice (green)
# high/low をひとまず「問題区間」として赤系を塗る
shade(events_w["low"],  "#ff7d7d", 0.18)
shade(events_w["high"], "#ff7d7d", 0.18)

ax1.set_title("Pitch comparison (shaded = issue segments)")
ax1.set_ylabel("Pitch f0 [Hz]")
ax1.grid(True, alpha=0.25)
ax1.legend(loc="center left", bbox_to_anchor=(1.005, 0.5), frameon=True)

# 下段：セント差
# 瞬間値の縦スティック（視認性用）
ax2.vlines(tR_w, 0, diff_w, color="#4a86e8", lw=0.8, alpha=0.35, label="Cents (instant)")

# スムージング線
ax2.plot(tR_w, diff_s_w, color="#c00000", lw=1.2, label="Smoothed cents")

# 許容帯 ±TOL_CENTS と 0 ライン
ax2.axhline(+TOL_CENTS, color="gray", ls="--", lw=1.0, alpha=0.9, label=f"Acceptable band (±{int(TOL_CENTS)}c)")
ax2.axhline(-TOL_CENTS, color="gray", ls="--", lw=1.0, alpha=0.9)
ax2.axhline(0,          color="k",    ls=":",  lw=1.0, alpha=0.8, label="Zero (perfect)")

ax2.set_ylim(-ymax, ymax)
ax2.set_ylabel("Cents")
ax2.set_xlabel("Time [s]")
ax2.grid(True, alpha=0.25)
ax2.legend(loc="center left", bbox_to_anchor=(1.005, 0.5), frameon=True)

# x 範囲は配列を切っているので “拡大” になっていますが、念のため明示
if START_SEC is not None or END_SEC is not None:
    xl = START_SEC if START_SEC is not None else float(tR[0])
    xr = END_SEC   if END_SEC   is not None else float(tR[-1])
    ax1.set_xlim(xl, xr)
    ax2.set_xlim(xl, xr)

OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(OUT_PNG, dpi=160)
print("wrote:", OUT_PNG)
