# tools/10_import_lyrics.py
import os, re, json
from pathlib import Path

REF_JSON = os.environ.get("REF_JSON", "SingingApp/analysis/sample01/pitch.json")
IN_FILE  = os.environ.get("IN_LYRICS", "SingingApp/analysis/sample01/lyrics_input.txt")
OUT_JSON = os.environ.get("OUT_JSON", "SingingApp/analysis/sample01/lyrics.json")

Path(Path(OUT_JSON).parent).mkdir(parents=True, exist_ok=True)

def load_ref_duration(ref_json):
    d = json.load(open(ref_json))
    t = [float(p["t"]) for p in d["track"]]
    return (t[-1] if t else 0.0)

def parse_time(s):
    # "mm:ss.xx" / "hh:mm:ss,ms" / "[mm:ss.xx]" などを素朴に拾う
    s = s.strip().strip("[]")
    if "," in s: s = s.replace(",", ".")
    parts = s.split(":")
    try:
        if len(parts) == 3:
            h, m, sec = int(parts[0]), int(parts[1]), float(parts[2])
            return h*3600 + m*60 + sec
        elif len(parts) == 2:
            m, sec = int(parts[0]), float(parts[1])
            return m*60 + sec
        else:
            return float(parts[0])
    except:
        return None

def read_lrc(lines):
    res = []
    for ln in lines:
        # [mm:ss.xx]歌詞
        m = re.findall(r"\[(\d+:\d+(?:\.\d+)?)\]", ln)
        text = re.sub(r"\[.*?\]", "", ln).strip()
        for tag in m:
            t = parse_time(tag)
            if t is not None and text:
                res.append((t, text))
    res.sort()
    # end は次行の start、最後は+3秒（仮）
    out = []
    for i,(st,tx) in enumerate(res):
        en = res[i+1][0] if i+1 < len(res) else st + 3.0
        out.append({"start": round(st,3), "end": round(en,3), "text": tx})
    return out

def read_srt(lines):
    # 1)
    # 00:00:12,000 --> 00:00:15,000
    # 歌詞
    out = []
    block = []
    for ln in lines:
        if ln.strip():
            block.append(ln.rstrip("\n"))
        else:
            if block: out.append(block); block=[]
    if block: out.append(block)
    rows = []
    for b in out:
        times = None
        text  = []
        for ln in b:
            if "-->" in ln:
                a,b = ln.split("-->")
                st = parse_time(a.strip())
                en = parse_time(b.strip())
                times = (st,en)
            else:
                # 番号行は飛ばす
                if re.fullmatch(r"\d+", ln.strip()): continue
                text.append(ln.strip())
        if times and text:
            rows.append({"start": round(times[0],3), "end": round(times[1],3), "text": " ".join(text)})
    return rows

def read_txt(lines, total_sec):
    # 均等割り：行数で総時間を割って区間を配分
    rows = [ln.strip() for ln in lines if ln.strip()]
    n = len(rows)
    if n == 0:
        return []
    dur = max(total_sec, n*2)  # 全体が0なら一行=2秒で最低限並べる
    seg = dur / n
    out = []
    for i,tx in enumerate(rows):
        st = i*seg
        en = (i+1)*seg
        out.append({"start": round(st,3), "end": round(en,3), "text": tx})
    return out

def detect_format(path):
    p = Path(path)
    ext = p.suffix.lower()
    if ext in [".lrc", ".srt", ".txt"]:
        return ext
    # 拡張子なしでも行を覗いて判定
    head = "".join(open(path, encoding="utf-8", errors="ignore").readlines()[:5])
    if "[" in head and "]" in head: return ".lrc"
    if "-->" in head: return ".srt"
    return ".txt"

def main():
    total = load_ref_duration(REF_JSON)
    fmt = detect_format(IN_FILE)
    lines = open(IN_FILE, encoding="utf-8", errors="ignore").read().splitlines()

    if fmt == ".lrc":
        rows = read_lrc(lines)
    elif fmt == ".srt":
        rows = read_srt(lines)
    else:
        rows = read_txt(lines, total)

    json.dump({"lyrics": rows}, open(OUT_JSON,"w"), ensure_ascii=False, indent=2)
    print("wrote:", OUT_JSON, "items:", len(rows), "format:", fmt)

if __name__ == "__main__":
    main()
