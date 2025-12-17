# 13_copy_lyrics_to_user_export.py
import os, json
from pathlib import Path

# ルート（…/SingingTrainerApp/SingingApp）
ROOT = Path(__file__).resolve().parents[1]
BASE_ANALYSIS = ROOT / "SingingApp" / "analysis"

# SONG があれば songs/<SONG>/...、なければ sample01/... を使う
SONG = os.environ.get("SONG", "").strip()

if SONG:
    base = BASE_ANALYSIS / "songs" / SONG
    ref_dir    = base / "ref"
    user_dir   = base / "user"
    export_dir = base / "export"
    candidates = [
        ref_dir / "lyrics_aligned.json",
        ref_dir / "lyrics.json",
    ]
else:
    base = BASE_ANALYSIS / "sample01"
    ref_dir    = base
    user_dir   = BASE_ANALYSIS / "user01"
    export_dir = base / "export"
    candidates = [
        base / "lyrics_aligned.json",
        base / "lyrics.json",
    ]

src = None
for c in candidates:
    if c.is_file():
        src = c
        break

if not src:
    print("ERROR: 歌詞の入力ファイルが見つかりませんでした。探したパス：")
    for c in candidates:
        print(" -", c)
    raise SystemExit(1)

user_dir.mkdir(parents=True, exist_ok=True)
export_dir.mkdir(parents=True, exist_ok=True)

dst_user   = user_dir   / "lyrics.json"
dst_export = export_dir / "lyrics.json"

with open(src, "r", encoding="utf-8") as f:
    data = json.load(f)

with open(dst_user, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

with open(dst_export, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print("copied:")
print(" -", src, "→", dst_user)
print(" -", src, "→", dst_export)
