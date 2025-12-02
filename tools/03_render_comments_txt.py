# -*- coding: utf-8 -*-
"""
events.json を読み取り、初心者向けの分かりやすいコメントをテキスト化します。
出力: SingingApp/analysis/user01/comments.txt
"""

import json, os, math
from pathlib import Path

IN_EVENTS = os.environ.get("IN_EVENTS", "SingingApp/analysis/user01/events.json")
OUT_TXT   = os.environ.get("OUT_TXT",   "SingingApp/analysis/user01/comments.txt")

def mmss(t: float) -> str:
    m = int(t // 60)
    s = t - m*60
    return f"{m:02d}:{s:05.2f}"

# イベント→コメントの定義（やさしい表現）
def event_to_comment(ev):
    t1 = mmss(ev["start"])
    t2 = mmss(ev.get("end", ev["start"] + 0.2))
    typ = ev["type"]
    avg = float(ev.get("avg_cents", 0.0))

    if typ == "pitch_high":
        # 高めにズレ
        return f"{t1}〜{t2}：音が少し高い傾向です。あごを少し下げ、口を縦に開きすぎないで、息を少し弱める意識で歌い直してみましょう。"

    if typ == "pitch_low":
        # 低めにズレ
        return f"{t1}〜{t2}：音が少し低い傾向です。背すじを伸ばして目線をやや上に。口の中を少し広くして、息のスピードを少しだけ速めてみましょう。"

    if typ == "unvoiced_miss":
        # 声が出ていない
        return f"{t1}〜{t2}：声が入っていません。直前で軽く息を吸って、次の言葉を先に口パクで作ってから発声を始めると入りやすいです。"

    # 予備（該当なし）
    return f"{t1}〜{t2}：タイミングや音程が不安定です。姿勢を整え、浅く短く吸ってから余裕をもって入ってみましょう。"

def main():
    ev = json.load(open(IN_EVENTS))
    lines = []
    for e in ev:
        lines.append(event_to_comment(e))

    # 似たコメントをまとめる（多すぎる時の軽い圧縮）
    # 今回はそのまま出力
    Path(os.path.dirname(OUT_TXT)).mkdir(parents=True, exist_ok=True)
    with open(OUT_TXT, "w") as f:
        f.write("■ 要所コメント（自動生成）\n")
        for m in lines[:200]:  # 多すぎると読みにくいので上限
            f.write(f"- {m}\n")

    print(f"wrote: {OUT_TXT}  items:{len(lines)}")

if __name__ == "__main__":
    main()
