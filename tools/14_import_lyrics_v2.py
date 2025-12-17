# SingingApp/tools/14_import_lyrics_v2.py
import os, re, json
from pathlib import Path
from _song_paths import get_song_id, paths

def parse_time(s):
    s = s.strip().strip("[]").replace(",", ".")
    parts = s.split(":")
    try:
        if len(parts) == 3:
            h,m,sec = int(parts[0]), int(parts[1]), float(parts[2])
            return h*3600 + m*60 + sec
        elif len(parts) == 2:
            m,sec = int(parts[0]), float(parts[1])
            return m*60 + sec
        else:
            return float(parts[0])
    except:
        return None

def detect_format(text_head):
    if re.search(r"\[\d+:\d+(?:\.\d+)?\]", text_head): return "lrc"
    if "-->" in text_head: return "srt"
    return "txt"

def read_lrc(lines):
    res=[]
    for ln in lines:
        tags = re.findall(r"\[(\d+:\d+(?:\.\d+)?)\]", ln)
        text = re.sub(r"\[.*?\]", "", ln).strip()
        for t in tags:
            tt = parse_time(t)
            if tt is not None and text:
                res.append((tt, text))
    res.sort()
    out=[]
    for i,(st,tx) in enumerate(res):
        en = res[i+1][0] if i+1<len(res) else st+3.0
        out.append({"start": round(st,3), "end": round(en,3), "text": tx})
    return out

def read_srt(lines):
    blocks=[]; buf=[]
    for ln in lines:
        if ln.strip(): buf.append(ln.rstrip("\n"))
        else:
            if buf: blocks.append(buf); buf=[]
    if buf: blocks.append(buf)
    out=[]
    for b in blocks:
        st=en=None; texts=[]
        for ln in b:
            if "-->" in ln:
                a,b = ln.split("-->")
                st, en = parse_time(a.strip()), parse_time(b.strip())
            else:
                if not re.fullmatch(r"\d+", ln.strip()):
                    texts.append(ln.strip())
        if st is not None and en is not None and texts:
            out.append({"start": round(st,3), "end": round(en,3), "text":" ".join(texts)})
    return out

def read_txt(lines, total_sec):
    rows=[ln.strip() for ln in lines if ln.strip()]
    if not rows:
        return []
    if total_sec <= 0:
        total_sec = max(180.0, len(rows)*2.0)
    seg = total_sec/len(rows)
    out=[]
    for i,tx in enumerate(rows):
        st=i*seg; en=(i+1)*seg
        out.append({"start": round(st,3), "end": round(en,3), "text": tx})
    return out

def load_ref_total_sec(ref_pitch_json: Path) -> float:
    if ref_pitch_json.exists():
        d=json.load(open(ref_pitch_json, encoding="utf-8"))
        t=[float(p["t"]) for p in d.get("track",[])]
        return t[-1] if t else 0.0
    return 0.0

def main():
    song = os.environ.get("SONG", "sample01")
    p = paths(song)
    ref_pitch    = p["files"]["ref_pitch"]
    lyrics_input = p["files"]["ref_lyrics_input"]
    out_json     = p["files"]["ref_lyrics"]
    out_json.parent.mkdir(parents=True, exist_ok=True)

    if not lyrics_input.exists():
        raise SystemExit(f"lyrics_input がありません: {lyrics_input}")

    head  = "".join(open(lyrics_input, encoding="utf-8", errors="ignore").readlines()[:5])
    fmt   = detect_format(head)
    lines = open(lyrics_input, encoding="utf-8", errors="ignore").read().splitlines()
    total = load_ref_total_sec(ref_pitch)

    if fmt=="lrc":
        rows = read_lrc(lines)
    elif fmt=="srt":
        rows = read_srt(lines)
    else:
        rows = read_txt(lines, total)

    json.dump({"lyrics": rows}, open(out_json,"w"), ensure_ascii=False, indent=2)
    print(f"[{song}] wrote:", out_json, "items:", len(rows), "format:", fmt)

if __name__ == "__main__":
    main()
