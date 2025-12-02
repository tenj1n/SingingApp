# -*- coding: utf-8 -*-
"""
02_compare_with_reference.py
参照ピッチとユーザーピッチを比較し、ズレ区間をイベント化して JSON 出力する。

入力:
  - REF_JSON: 参照ピッチ JSON（省略時: SingingApp/analysis/sample01/pitch.json）
  - USR_JSON: ユーザーピッチ JSON（省略時: SingingApp/analysis/user01/pitch.json）
  - OUT_JSON: 出力イベント JSON（省略時: SingingApp/analysis/user01/events.json）

ピッチJSONの想定形式:
{
  "sr": 44100,
  "hop": 256,
  "algo": "yin_simple",
  "track": [{"t": 0.000, "f0_hz": 220.0 or null}, ...]
}
"""
import json, math, os, sys
from typing import List, Dict, Any

# ── パラメータ（必要に応じて調整） ───────────────────────────
PITCH_LOW_TH_CENTS  = -35.0   # これより低ければ「低い」
PITCH_HIGH_TH_CENTS = +35.0   # これより高ければ「高い」
MIN_DURATION_SEC    = 0.20    # これ未満は短すぎるので無視
# ────────────────────────────────────────────────────────

def load_pitch_json(path: str):
    with open(path, "r") as f:
        d = json.load(f)
    t = [float(p["t"]) for p in d["track"]]
    f0 = []
    for p in d["track"]:
        v = p.get("f0_hz", None)
        f0.append(None if v is None else float(v))
    return d.get("sr", 44100), d.get("hop", 256), t, f0

def align_user_to_ref(t_ref, t_usr):
    """参照の各時刻に最も近いユーザーフレームのインデックスを返す"""
    # 二分探索（searchsorted 相当の簡易版）
    idx = []
    j = 0
    for tr in t_ref:
        # t_usr[j] <= tr となる最大 j を探す
        while j + 1 < len(t_usr) and t_usr[j + 1] <= tr:
            j += 1
        # j と j+1 のどちらが近いか
        if j + 1 < len(t_usr) and abs(t_usr[j + 1] - tr) < abs(t_usr[j] - tr):
            idx.append(j + 1)
        else:
            idx.append(j)
    return idx

def hz_to_cents_ratio(f_usr, f_ref):
    """比率からセント差を計算（どちらか欠損なら None）"""
    if f_usr is None or f_ref is None or f_usr <= 0 or f_ref <= 0:
        return None
    return 1200.0 * math.log2(f_usr / f_ref)

def segment_mask(mask: List[bool], min_len_frames: int):
    """True が連続する区間を [start, end) で返す（end は含まない）"""
    out = []
    s = None
    for i, v in enumerate(mask + [False]):  # 番兵
        if v and s is None:
            s = i
        elif not v and s is not None:
            if i - s >= min_len_frames:
                out.append((s, i))
            s = None
    return out

def main():
    # 入出力パス（環境変数優先、無ければ既定値）
    REF_JSON = os.environ.get("REF_JSON", "SingingApp/analysis/sample01/pitch.json")
    USR_JSON = os.environ.get("USR_JSON", "SingingApp/analysis/user01/pitch.json")
    OUT_JSON = os.environ.get("OUT_JSON", "SingingApp/analysis/user01/events.json")
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)

    # 読み込み
    sr_r, hop_r, t_ref, f_ref = load_pitch_json(REF_JSON)
    sr_u, hop_u, t_usr, f_usr = load_pitch_json(USR_JSON)

    # 参照のフレームレートから 1フレーム秒数を推定
    fps = sr_r / float(hop_r) if hop_r else 172.0
    min_frames = max(1, int(round(MIN_DURATION_SEC * fps)))

    # 時間合わせ（参照各フレーム→最も近いユーザーフレーム）
    choose = align_user_to_ref(t_ref, t_usr)
    f_usr_on_ref = [f_usr[i] if 0 <= i < len(f_usr) else None for i in choose]

    # セント差リスト（None は欠損）
    cents = [hz_to_cents_ratio(u, r) for u, r in zip(f_usr_on_ref, f_ref)]

    # 判定用マスク
    is_low  = [ (c is not None) and (c <  PITCH_LOW_TH_CENTS)  for c in cents ]
    is_high = [ (c is not None) and (c >  PITCH_HIGH_TH_CENTS) for c in cents ]
    # 参照に声はあるがユーザーが無声
    unvoiced_miss = [ (r is not None and r > 0) and (u is None or u <= 0)
                      for r, u in zip(f_ref, f_usr_on_ref) ]

    # 区間抽出
    events: List[Dict[str, Any]] = []

    for s, e in segment_mask(is_low, min_frames):
        seg = [c for c in cents[s:e] if c is not None]
        avg = sum(seg) / len(seg) if seg else 0.0
        mx  = max(seg, key=abs) if seg else 0.0
        events.append({
            "start": round(t_ref[s], 3),
            "end":   round(t_ref[e - 1], 3),
            "type":  "pitch_low",
            "avg_cents": round(avg, 1),
            "max_cents": round(mx, 1),
        })

    for s, e in segment_mask(is_high, min_frames):
        seg = [c for c in cents[s:e] if c is not None]
        avg = sum(seg) / len(seg) if seg else 0.0
        mx  = max(seg, key=abs) if seg else 0.0
        events.append({
            "start": round(t_ref[s], 3),
            "end":   round(t_ref[e - 1], 3),
            "type":  "pitch_high",
            "avg_cents": round(avg, 1),
            "max_cents": round(mx, 1),
        })

    for s, e in segment_mask(unvoiced_miss, min_frames):
        events.append({
            "start": round(t_ref[s], 3),
            "end":   round(t_ref[e - 1], 3),
            "type":  "unvoiced_miss"
        })

    # 時間順に整列
    events.sort(key=lambda x: x["start"])

    # 出力
    with open(OUT_JSON, "w") as f:
        json.dump(events, f, ensure_ascii=False, indent=2)

    # サマリ出力
    n_low  = sum(1 for e in events if e["type"] == "pitch_low")
    n_high = sum(1 for e in events if e["type"] == "pitch_high")
    n_uv   = sum(1 for e in events if e["type"] == "unvoiced_miss")
    print(f"wrote: {OUT_JSON}  total:{len(events)}  low:{n_low}  high:{n_high}  unvoice:{n_uv}")

if __name__ == "__main__":
    sys.exit(main())
