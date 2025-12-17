# tools/00_scaffold_song.py
import os
from pathlib import Path
from _song_paths import get_song_id, paths

def main():
    song = os.environ.get("SONG", "sample01")
    p = paths(song)
    for d in (p["BASE"], p["REF"], p["USER"], p["EXPORT"]):
        d.mkdir(parents=True, exist_ok=True)

    # 初回用の空ファイルを準備（既存なら触らない）
    li_in = p["files"]["ref_lyrics_input"]
    if not li_in.exists():
        li_in.write_text("(ここに歌詞1行1フレーズで書く)\n", encoding="utf-8")
    print("OK scaffold:", p["BASE"])

if __name__ == "__main__":
    main()
