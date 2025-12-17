# SingingApp/tools/_song_paths.py
from pathlib import Path

def get_song_id(default="sample01"):
    import os
    return os.environ.get("SONG", default).strip() or default

def paths(song: str):
    """
    返す辞書:
      base:   analysis/songs/<song>
      ref:    参照データ置き場
      user:   ユーザーデータ置き場
      export: アプリへ渡す最終成果物
      files:  主に歌詞とピッチの標準ファイルパス
    """
    ROOT = Path(__file__).resolve().parents[1]            # …/SingingTrainerApp/SingingApp
    ANA  = ROOT / "SingingApp" / "analysis"

    if song == "sample01":
        base   = ANA / "sample01"
        ref    = base
        user   = ANA / "user01"
        export = base / "export"
        files = {
            "ref_pitch":        ref / "pitch.json",
            "ref_lyrics_input": ref / "lyrics_input.txt",
            "ref_lyrics":       ref / "lyrics.json",
        }
    else:
        base   = ANA / "songs" / song
        ref    = base / "ref"
        user   = base / "user"
        export = base / "export"
        files = {
            "ref_pitch":        ref / "pitch.json",
            "ref_lyrics_input": ref / "lyrics_input.txt",
            "ref_lyrics":       ref / "lyrics.json",
        }

    for d in (ref, user, export):
        d.mkdir(parents=True, exist_ok=True)

    return {
        "ROOT": ROOT, "ANA": ANA,
        "base": base, "ref": ref, "user": user, "export": export,
        "files": files,
        # 互換用の大文字キー（00_scaffold_song.py 向け）
        "BASE": base, "REF": ref, "USER": user, "EXPORT": export,
    }
