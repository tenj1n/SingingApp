# tools/09_export_bundle.py
import os, json, gzip, shutil
from pathlib import Path
from datetime import datetime

BASE      = Path("SingingApp/analysis/user01")
PITCH     = BASE / "pitch.shifted.json"   # 08で作ったもの（なければ pitch.json を使う）
PITCH_FALLBACK = BASE / "pitch.json"
EVENTS    = BASE / "events.json"
SUMMARY   = BASE / "summary.txt"          # 05で作った総評（なければスキップOK）
KEYOFF    = BASE / "key_offset.json"      # 05内で作っていれば（なければスキップOK）
COMMENTS  = BASE / "comments.json"        # 07で作ったコメント
EXPORTDIR = BASE / "export"

EXPORTDIR.mkdir(parents=True, exist_ok=True)

def load_json(p: Path):
    return json.load(open(p)) if p.exists() else None

def main():
    pitch_path = PITCH if PITCH.exists() else PITCH_FALLBACK

    meta = {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "files": {}
    }

    # pitch（そのまま or 圧縮も併せて）
    if pitch_path.exists():
        shutil.copy2(pitch_path, EXPORTDIR / "pitch.json")
        meta["files"]["pitch.json"] = "OK"

    # events
    if EVENTS.exists():
        ev = load_json(EVENTS)
        json.dump(ev, open(EXPORTDIR / "events.json", "w"), ensure_ascii=False)
        with gzip.open(EXPORTDIR / "events.min.json.gz", "wt") as f:
            json.dump(ev, f)
        meta["files"]["events.json"] = "OK"
        meta["files"]["events.min.json.gz"] = "OK"

    # comments
    if COMMENTS.exists():
        shutil.copy2(COMMENTS, EXPORTDIR / "comments.json")
        meta["files"]["comments.json"] = "OK"

    # summary（任意）
    if SUMMARY.exists():
        shutil.copy2(SUMMARY, EXPORTDIR / "summary.txt")
        meta["files"]["summary.txt"] = "OK"

    # key_offset（任意）
    if KEYOFF.exists():
        shutil.copy2(KEYOFF, EXPORTDIR / "key_offset.json")
        meta["files"]["key_offset.json"] = "OK"

    # meta.json
    json.dump(meta, open(EXPORTDIR / "meta.json", "w"), ensure_ascii=False, indent=2)
    print("exported to:", str(EXPORTDIR.resolve()))
    for k,v in meta["files"].items():
        print(" -", k, v)

if __name__ == "__main__":
    main()
