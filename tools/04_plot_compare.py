# -*- coding: utf-8 -*-
"""
参照(REF)とユーザー(USR)のピッチを同じ軸に描画し、
events.json の区間を色付きで重ねて保存します。
出力: SingingApp/analysis/user01/compare.png
"""

import json, os
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

REF_JSON = os.environ.get("REF_JSON", "SingingApp/analysis/sample01/pitch.json")
USR_JSON = os.environ.get("USR_JSON", "SingingApp/analysis/user01/pitch.json")
EVT_JSON = os.environ.get("EVT_JSON", "SingingApp/analysis/user01/events.json")
OUT_PNG  = os.environ.get("OUT_PNG",  "SingingApp/analysis/user01/compare.png")

def load_pitch(path):
    d = json.load(open(path))
    t = np.array([p["t"] for p in d["track"]], float)
    f = np.array([np.nan if p["f0_hz"] is None else float(p["f0_hz"]) for p in d["track"]], float)
    return t, f

def interp_to(times_ref, times_src, f_src):
    """ src を ref の時間に線形補間（NaNはそのまま） """
    out = np.full_like(times_ref, np.nan, dtype=float)
    m = ~np.isnan(f_src)
    if m.sum() < 2:
        return out
    out = np.interp(times_ref, times_src[m], f_src[m], left=np.nan, right=np.nan)
    return out

def main():
    tR, fR = load_pitch(REF_JSON)
    tU, fU = load_pitch(USR_JSON)
    fU_on_R = interp_to(tR, tU, fU)

    # 図作成
    fig, ax = plt.subplots(figsize=(12, 5))
    ax.plot(tR, fR, label="参考の歌手", linewidth=1.2)
    ax.plot(tR, fU_on_R, label="あなた", linewidth=1.0)

    # イベント塗り分け
    if os.path.exists(EVT_JSON):
        ev = json.load(open(EVT_JSON))
        color_map = {
            "pitch_low":  {"c":"tab:blue",  "label":"音が低め"},
            "pitch_high": {"c":"tab:red",   "label":"音が高め"},
            "unvoiced_miss":{"c":"tab:gray","label":"声が入っていない"},
        }
        used = set()
        for e in ev:
            cinfo = color_map.get(e["type"], {"c":"tab:orange","label":"その他"})
            ax.axvspan(e["start"], e.get("end", e["start"]+0.2),
                       color=cinfo["c"], alpha=0.15, lw=0)
            # 凡例は各タイプ1回だけ
            if cinfo["label"] not in used:
                ax.plot([],[], color=cinfo["c"], alpha=0.4, label=cinfo["label"])
                used.add(cinfo["label"])

    ax.set_xlabel("時間 [秒]")
    ax.set_ylabel("基本周波数 f0 [Hz]")
    ax.set_title("ピッチ比較（色帯=要修正区間）")
    ax.legend(loc="upper right")
    ax.grid(True, alpha=0.3)

    Path(os.path.dirname(OUT_PNG)).mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(OUT_PNG, dpi=150)
    print("wrote:", OUT_PNG)

if __name__ == "__main__":
    main()
