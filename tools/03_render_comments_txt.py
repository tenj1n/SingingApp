# -*- coding: utf-8 -*-
"""イベント検出結果を読み込み、初心者にも伝わりやすい文章に整形して書き出すスクリプト。

環境変数で入出力パスを上書きできます:
- ``IN_EVENTS``: 読み込む JSON ファイルへのパス (デフォルト ``SingingApp/analysis/user01/events.json``)
- ``OUT_TXT``: 生成したコメントを保存するパス (デフォルト ``SingingApp/analysis/user01/comments.txt``)
"""

import json
import os
from pathlib import Path
from typing import Any, Dict, List

IN_EVENTS = Path(os.environ.get("IN_EVENTS", "SingingApp/analysis/user01/events.json"))
OUT_TXT = Path(os.environ.get("OUT_TXT", "SingingApp/analysis/user01/comments.txt"))


def mmss(seconds: float) -> str:
    """秒数を ``MM:SS.ss`` 形式に整形する。
    歌唱のフィードバックに直接表示されるため、分と秒をゼロ埋めして
    ぱっと見で位置が分かるようにしている。
    """

    minutes = int(seconds // 60)
    remain = seconds - minutes * 60
    return f"{minutes:02d}:{remain:05.2f}"

# イベント→コメントの定義（やさしい表現）
def event_to_comment(event: Dict[str, Any]) -> str:
    """検出イベント 1 件をわかりやすい日本語コメントに変換する。

    ``start`` と ``end`` (または ``start`` のみ) で時間帯を示し、
    ``type`` に応じて具体的な改善ポイントを案内する。
    不足しているキーは既定値で補い、ユーザーが混乱しない文章を返す。
    """

    start = float(event["start"])
    end = float(event.get("end", start + 0.2))
    t1 = mmss(start)
    t2 = mmss(end)
    typ = str(event["type"])

    if typ == "pitch_high":
        # 高めにズレ
       return (
            f"{t1}〜{t2}：音が少し高い傾向です。"
            "あごを少し下げ、口を縦に開きすぎないで、息を少し弱める意識で歌い直してみましょう。"
        )
    
    if typ == "pitch_low":
        # 低めにズレ
        return (
            f"{t1}〜{t2}：音が少し低い傾向です。背すじを伸ばして目線をやや上に。"
            "口の中を少し広くして、息のスピードを少しだけ速めてみましょう。"
        )
    
    if typ == "unvoiced_miss":
        # 声が出ていない
        return (
            f"{t1}〜{t2}：声が入っていません。直前で軽く息を吸って、"
            "次の言葉を先に口パクで作ってから発声を始めると入りやすいです。"
        )
    
    # 予備（該当なし）
    return (
        f"{t1}〜{t2}：タイミングや音程が不安定です。"
        "姿勢を整え、浅く短く吸ってから余裕をもって入ってみましょう。"
    )

def load_events(path: Path) -> List[Dict[str, Any]]:
    """イベント JSON を読み込む。

    文字コードを UTF-8 に固定し、ファイルが無い場合は FileNotFoundError をそのまま
    伝播させる。検出結果の構造が不正なら json.JSONDecodeError が上がるため、呼び出し
    元でログが確認できる。
    """

    with path.open(encoding="utf-8") as f:
        return json.load(f)

def main() -> None:
    """イベント一覧を読み込み、コメント集をテキストファイルに書き出す。"""

    events = load_events(IN_EVENTS)
    comments = [event_to_comment(event) for event in events]

    OUT_TXT.parent.mkdir(parents=True, exist_ok=True)
    with OUT_TXT.open("w", encoding="utf-8") as f:
        f.write("■ 要所コメント（自動生成）\n")
        for message in comments[:200]:  # 多すぎると読みにくいので上限
            f.write(f"- {message}\n")

    print(f"wrote: {OUT_TXT}  items:{len(comments)}")

if __name__ == "__main__":
    main()
    