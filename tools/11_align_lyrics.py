# tools/11_align_lyrics.py
import os, json, math
from pathlib import Path
import numpy as np

REF_JSON  = os.environ.get("REF_JSON",  "SingingApp/analysis/sample01/pitch.json")
IN_JSON   = os.environ.get("IN_JSON",   "SingingApp/analysis/sample01/lyrics.json")
OUT_JSON  = os.environ.get("OUT_JSON",  "SingingApp/analysis/sample01/lyrics_aligned.json")

GAP_SEC   = float(os.environ.get("GAP_SEC", "0.60"))  # 無声の穴がこの秒数以上ならフレーズ境界
MIN_DUR   = float(os.environ.get("MIN_DUR","0.40"))   # 各フレーズの最小長

Path(Path(OUT_JSON).parent).mkdir(parents=True, exist_ok=True)

def load_pitch(path):
    d = json.load(open(path, encoding="utf-8"))
    t = np.array([float(x["t"]) for x in d.get("track", [])], dtype=float)
    f = np.array([np.nan if x.get("f0_hz") is None else float(x["f0_hz"]) for x in d.get("track", [])], dtype=float)
    return t, f, int(d.get("sr", 44100)), int(d.get("hop", 256))

def voiced_segments(t, f, gap_sec=0.60):
    """簡易な有声区間抽出（NaN/0以外が続く場所をまとめる）。"""
    if t.size == 0 or f.size == 0:
        return []
    mask = (~np.isnan(f)) & (f > 0)
    idx = np.where(mask)[0]
    if idx.size == 0:
        return []
    starts = [idx[0]]; ends = []
    for a, b in zip(idx, idx[1:]):
        if b != a + 1:
            ends.append(a); starts.append(b)
    ends.append(idx[-1])
    segs = [(float(t[s]), float(t[e])) for s, e in zip(starts, ends)]

    # 最小長保証
    fixed = []
    for s, e in segs:
        if e - s < MIN_DUR:
            e = s + MIN_DUR
        fixed.append((s, e))
    return fixed

def detect_input_rows(raw):
    """
    IN_JSON が {"lyrics":[...]} でも {"lines":[...]} でも受け付ける。
    さらに、要素が {"text": "..."} だけ（無タイム）の場合も許容。
    """
    rows = raw.get("lines")
    if rows is None:
        rows = raw.get("lyrics")
    if rows is None:
        # 互換: {"source":..., "lines":[...]} や {"lyrics":[...]} 以外はエラー
        raise KeyError("入力JSONに 'lines' も 'lyrics' も見つかりませんでした。")

    norm = []
    for r in rows:
        # 許容する形：
        # 1) {"text": "..."}                          -> 無タイム
        # 2) {"start":秒, "end":秒, "text":"..."}     -> 既にタイムあり
        if "text" not in r:
            continue
        item = {"text": str(r["text"])}
        if "start" in r and "end" in r:
            try:
                item["start"] = float(r["start"])
                item["end"]   = float(r["end"])
            except Exception:
                pass
        norm.append(item)
    return norm

def assign_from_timed(rows, total_end):
    """start/end がある行はそのまま、end 無しは次行直前か最小長で補完。"""
    # start で昇順ソート
    timed = []
    for r in rows:
        if "start" in r:
            s = float(r["start"])
            e = float(r.get("end", s + MIN_DUR))
            timed.append({"start": s, "end": e, "text": r["text"]})
    timed.sort(key=lambda x: x["start"])

    out = []
    for i, r in enumerate(timed):
        s = float(r["start"])
        e = float(r["end"])
        # 次の start より長い場合はトリム、短すぎなら最小長
        if i + 1 < len(timed):
            e = min(e, float(timed[i + 1]["start"]))
        if e - s < MIN_DUR:
            e = s + MIN_DUR
        out.append({"start": round(s, 3), "end": round(e, 3), "text": r["text"]})
    return out

def split_or_merge(segs, n_lines):
    """セグメント数と歌詞行数を合わせる（多ければマージ、少なければ等分分割）。"""
    if n_lines <= 0:
        return []
    if not segs:
        # 何もない場合はダミー均等
        dur = max(MIN_DUR * n_lines, 2.0 * n_lines)
        return [(i * dur / n_lines, (i + 1) * dur / n_lines) for i in range(n_lines)]

    if len(segs) == n_lines:
        return segs

    lens = [e - s for s, e in segs]
    total = sum(lens)

    if len(segs) > n_lines:
        # マージ：長さにあまり依らない素朴版（均等寄せ）
        ratio = len(segs) / n_lines
        out, bag = [], []
        acc = 0.0
        for i, seg in enumerate(segs):
            bag.append(seg); acc += 1.0
            if acc >= ratio or i == len(segs) - 1:
                s = bag[0][0]; e = bag[-1][1]
                if e - s < MIN_DUR:
                    e = s + MIN_DUR
                out.append((s, e))
                bag = []; acc = 0.0
        # 数ズレ微調整
        while len(out) > n_lines:
            a = out.pop(); b = out.pop()
            out.append((b[0], a[1]))
        while len(out) < n_lines:
            s, e = out[-1]
            m = (s + e) / 2
            out[-1] = (s, m); out.append((m, e))
        return out
    else:
        # 分割
        out = []
        for s, e in segs:
            out.append((s, e))
        # 足りない分を長い区間から割る
        while len(out) < n_lines:
            # 一番長い区間を二等分
            idx = max(range(len(out)), key=lambda i: out[i][1] - out[i][0])
            s, e = out.pop(idx)
            m = (s + e) / 2
            out.insert(idx, (s, m))
            out.insert(idx + 1, (m, e))
        return out[:n_lines]

def main():
    # 参照ピッチから総尺と有声セグメントを拾う
    tR, fR, sr, hop = load_pitch(REF_JSON)
    total_end = float(tR[-1]) if tR.size else 0.0
    segs = voiced_segments(tR, fR, GAP_SEC)

    raw = json.load(open(IN_JSON, encoding="utf-8"))
    # {"lines":[...]} / {"lyrics":[...]} 両対応
    rows = detect_input_rows(raw)

    # タイムあり行が1つでもあれば「タイム優先」
    has_timed = any(("start" in r or "end" in r) for r in rows)
    if has_timed:
        aligned = assign_from_timed(rows, total_end if total_end > 0 else 180.0)
    else:
        # 無タイム：有声セグメントに行数を合わせる
        n = len(rows)
        if not segs:
            # 参照が空ならダミー均等
            dur = max(180.0, n * 2.0)
            segs = [(i * dur / n, (i + 1) * dur / n) for i in range(n)]
        segs2 = split_or_merge(segs, n)
        aligned = []
        for (s, e), r in zip(segs2, rows):
            if e - s < MIN_DUR:
                e = s + MIN_DUR
            aligned.append({"start": round(float(s), 3),
                            "end":   round(float(e), 3),
                            "text":  r["text"]})

    out = {"source": raw.get("source", "lyrics_input"), "lines": aligned}
    json.dump(out, open(OUT_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("wrote:", OUT_JSON, "lines:", len(aligned))

if __name__ == "__main__":
    main()
