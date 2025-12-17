# tools/12_make_subtitles.py  （置き換え版）
import os, json
from pathlib import Path

IN_JSON = os.environ.get("IN_JSON", "SingingApp/analysis/sample01/lyrics_aligned.json")
OUT_DIR = os.environ.get("OUT_DIR", "SingingApp/analysis/sample01")

def _sec_to_timestamp_srt(sec: float) -> str:
    # 00:MM:SS,ms（SRT）
    ms = int(round((sec - int(sec)) * 1000))
    sec = int(sec)
    hh = sec // 3600
    mm = (sec % 3600) // 60
    ss = sec % 60
    return f"{hh:02d}:{mm:02d}:{ss:02d},{ms:03d}"

def _sec_to_timestamp_lrc(sec: float) -> str:
    # [MM:SS.xx]（LRC）
    sec_int = int(sec)
    mm = sec_int // 60
    ss = sec_int % 60
    xx = int(round((sec - sec_int) * 100))  # 小数2桁
    return f"[{mm:02d}:{ss:02d}.{xx:02d}]"

def _load_lines(path: Path):
    d = json.loads(path.read_text(encoding="utf-8"))
    # どちらのキーにも対応
    rows = d.get("lines") or d.get("lyrics") or []
    # shape: [{"start": float, "end": float, "text": str}, ...]
    return rows

def _write_srt(rows, out_path: Path):
    out = []
    for i, r in enumerate(rows, start=1):
        a = _sec_to_timestamp_srt(float(r["start"]))
        b = _sec_to_timestamp_srt(float(r["end"]))
        t = (r.get("text") or "").strip()
        out.append(str(i))
        out.append(f"{a} --> {b}")
        out.append(t if t else " ")
        out.append("")  # 空行
    out_path.write_text("\n".join(out), encoding="utf-8")

def _write_lrc(rows, out_path: Path):
    out = []
    for r in rows:
        tag = _sec_to_timestamp_lrc(float(r["start"]))
        t = (r.get("text") or "").strip()
        out.append(f"{tag}{t}")
    out_path.write_text("\n".join(out) + "\n", encoding="utf-8")

def _write_overlay_json(rows, out_path: Path):
    # 軽量オーバーレイ（UI重ね表示用）
    simple = [{"s": float(r["start"]), "e": float(r["end"]), "t": r.get("text","")} for r in rows]
    out_path.write_text(json.dumps(simple, ensure_ascii=False, indent=2), encoding="utf-8")

def main():
    in_path = Path(IN_JSON)
    out_dir = Path(OUT_DIR)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = _load_lines(in_path)
    if not rows:
        raise SystemExit(f"No lyrics rows in: {in_path}")

    # 出力ファイル
    out_lrc = out_dir / "lyrics.lrc"
    out_srt = out_dir / "lyrics.srt"
    out_overlay = out_dir / "lyrics_overlay.json"
    out_json_copy = out_dir / "lyrics.json"  # 元JSONも持っておく

    # 書き出し
    _write_lrc(rows, out_lrc)
    _write_srt(rows, out_srt)
    _write_overlay_json(rows, out_overlay)
    # 元JSONをコピー（lines/lyrics どちらでもOKなラッパーで揃える）
    out_json_copy.write_text(json.dumps({"lines": rows}, ensure_ascii=False, indent=2), encoding="utf-8")

    print("wrote:", out_lrc, out_srt, out_overlay, out_json_copy, "items:", len(rows))

if __name__ == "__main__":
    main()
