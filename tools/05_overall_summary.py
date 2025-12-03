# tools/05_overall_summary.py
import json, os, math
from pathlib import Path
import numpy as np

# ----- 入出力パス（既定値） -----
REF_JSON = os.environ.get("REF_JSON", "SingingApp/analysis/sample01/pitch.json")
USR_JSON = os.environ.get("USR_JSON", "SingingApp/analysis/user01/pitch.json")
EVT_JSON = os.environ.get("EVT_JSON", "SingingApp/analysis/user01/events.json")  # あれば＋αの集計に使う
OUT_JSON = os.environ.get("OUT_JSON", "SingingApp/analysis/user01/summary.json")
OUT_TXT  = os.environ.get("OUT_TXT",  "SingingApp/analysis/user01/summary.txt")

# 設定
TOL_CENTS   = float(os.environ.get("TOL_CENTS", "40"))     # 許容帯 ±40c 既定
MIN_SECONDS = float(os.environ.get("MIN_SECONDS", "15"))   # 有効データがこの秒数未満なら「データ不足」

# ----- 共有関数 -----
def load_pitch_json(p):
    d = json.load(open(p))
    t = np.array([float(x["t"]) for x in d["track"]], dtype=float)
    f = np.array([np.nan if x["f0_hz"] is None else float(x["f0_hz"]) for x in d["track"]], dtype=float)
    return t, f, d.get("sr", 44100), d.get("hop", 256)

def align_on_ref(t_ref, t_usr):
    """参照タイムスタンプ t_ref に一番近いユーザーのインデックスを返す"""
    idx = np.searchsorted(t_usr, t_ref)
    idx = np.clip(idx, 1, len(t_usr)-1)
    return np.where(np.abs(t_usr[idx-1]-t_ref) <= np.abs(t_usr[idx]-t_ref), idx-1, idx)

def dur_from_events(ev, evtype=None):
    if ev is None: return 0.0
    s = 0.0
    for e in ev:
        if (evtype is None) or (e.get("type")==evtype):
            s += float(e.get("end", e["start"])) - float(e["start"])
    return max(0.0, s)

def percentile(x, q):
    return float(np.nanpercentile(x, q)) if x.size else float("nan")

# ----- メイン処理 -----
def main():
    # 1) 読み込み
    tR, fR, srR, hopR = load_pitch_json(REF_JSON)
    tU, fU, srU, hopU = load_pitch_json(USR_JSON)

    # 2) 時間合わせ（参照にユーザーを合わせる）
    idx = align_on_ref(tR, tU)
    fU_on_R = fU[idx]

    # 3) 有声フレームで差分（セント）を計算
    mask = (~np.isnan(fR)) & (~np.isnan(fU_on_R)) & (fR>0) & (fU_on_R>0)
    t_ref = tR[mask]
    f_ref = fR[mask]
    f_usr = fU_on_R[mask]
    cents = 1200.0 * np.log2(f_usr / f_ref)

    # 実データ秒数（参照の hop 秒で見積もり）
    fps = srR / hopR if hopR else (1.0/np.median(np.diff(tR)))
    seconds = float(len(t_ref) / fps)

    # 4) 集計
    within = np.abs(cents) <= TOL_CENTS
    low    = cents < -TOL_CENTS
    high   = cents >  TOL_CENTS

    p_within = float(np.nanmean(within)) if within.size else float("nan")
    p_low    = float(np.nanmean(low))
    p_high   = float(np.nanmean(high))

    mean_c   = float(np.nanmean(cents)) if cents.size else float("nan")
    med_c    = float(np.nanmedian(cents)) if cents.size else float("nan")
    std_c    = float(np.nanstd(cents)) if cents.size else float("nan")

    p10 = percentile(cents, 10)
    p90 = percentile(cents, 90)

    # 5) 参考：イベントから無声ミス秒数（ある場合）
    ev = None
    if os.path.exists(EVT_JSON):
        try:
            ev = json.load(open(EVT_JSON))
        except Exception:
            ev = None
    uv_sec = dur_from_events(ev, "unvoiced_miss") if ev else 0.0

    # 6) 総評のルール
    verdict = "insufficient_data"
    reason  = "有効データが少ないため判定できません。"
    tips    = ""

    if seconds >= MIN_SECONDS and cents.size:
        # バイアス（平均/中央値）と偏り（low vs high）
        bias  = med_c if not math.isnan(med_c) else mean_c
        diff_ratio = (p_high - p_low)  # 正なら高め、負なら低め

        # 閾値（経験則）：
        # ・中央値が ±20c を越えている → 明確に高/低
        # ・±20c 以内でも、低/高の割合差が 0.15 以上 → そちらに偏り
        # ・上記に当てはまらず、±TOL 内率 < 0.55 かつ 標準偏差が大きい → アンバランス
        # ・それ以外 → だいたい合っている
        if bias <= -20 or diff_ratio <= -0.15:
            verdict = "overall_low"
            reason  = "全体にピッチが低め（音程が下に寄りがち）です。"
            tips    = "息のスピードを少し速くし、口の中の天井を高めに意識。語尾で落ちないように、音の支えを保ったまま次の音へ。"
        elif bias >= 20 or diff_ratio >= 0.15:
            verdict = "overall_high"
            reason  = "全体にピッチが高め（音程が上に寄りがち）です。"
            tips    = "首と喉を力ませず、息の量を少し抑えめに。上あごに当てるイメージを薄めて、基準の音に“落ち着かせる”意識。"
        elif (p_within < 0.55) or (std_c > 120):
            verdict = "inconsistent"
            reason  = "高い・低いのブレ（上下の揺れ）が大きいです。"
            tips    = "1音をまっすぐ保つ練習を短いフレーズ単位で。メトロノームに合わせ、1音を3〜4拍キープ→次の音へ移る練習を繰り返す。"
        else:
            verdict = "mostly_ok"
            reason  = "おおむね基準に近いピッチで歌えています。"
            tips    = "細かいズレを減らすために、語尾の処理と次の音への入りだけを重点チェック。"

    # 7) 書き出し
    out = {
        "tol_cents": TOL_CENTS,
        "frames": int(cents.size),
        "seconds": round(seconds, 2),
        "mean_cents": round(mean_c, 1) if cents.size else None,
        "median_cents": round(med_c, 1) if cents.size else None,
        "std_cents": round(std_c, 1) if cents.size else None,
        "percent_within_tol": round(p_within, 3) if within.size else None,
        "percent_low": round(p_low, 3) if low.size else None,
        "percent_high": round(p_high, 3) if high.size else None,
        "p10_cents": round(p10, 1) if cents.size else None,
        "p90_cents": round(p90, 1) if cents.size else None,
        "unvoiced_miss_seconds": round(uv_sec, 2) if ev else None,
        "verdict": verdict,
        "reason": reason,
        "tips": tips,
    }
    Path(os.path.dirname(OUT_JSON)).mkdir(parents=True, exist_ok=True)
    json.dump(out, open(OUT_JSON, "w"), ensure_ascii=False, indent=2)

    # TXT も
    with open(OUT_TXT, "w") as f:
        f.write("=== Pitch overall summary ===\n")
        f.write(f"Data seconds      : {seconds:.2f} s\n")
        f.write(f"Tolerance         : ±{TOL_CENTS:.0f} cents\n")
        if cents.size:
            f.write(f"Median / Mean     : {med_c:.1f} c / {mean_c:.1f} c\n")
            f.write(f"Std (spread)      : {std_c:.1f} c\n")
            f.write(f"Within tolerance  : {p_within*100:.1f}%\n")
            f.write(f"Too low / high    : {p_low*100:.1f}% / {p_high*100:.1f}%\n")
            f.write(f"p10 / p90         : {p10:.1f} c / {p90:.1f} c\n")
        if ev:
            f.write(f"Unvoiced-miss     : {uv_sec:.2f} s\n")
        f.write(f"\nVerdict: {verdict}\n")
        f.write(f"Summary: {reason}\n")
        f.write(f"Tips   : {tips}\n")

    print("wrote:", OUT_JSON, "and", OUT_TXT)
    print("verdict:", out["verdict"], "| within_tol:", out["percent_within_tol"])

if __name__ == "__main__":
    main()
