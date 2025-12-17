# tools/07_event_comment_cards.py
import os, json
from pathlib import Path

IN_EVENTS = os.environ.get("IN_EVENTS",  "SingingApp/analysis/user01/events.json")
OUT_JSON  = os.environ.get("OUT_JSON",   "SingingApp/analysis/user01/comments.json")
OUT_TXT   = os.environ.get("OUT_TXT",    "SingingApp/analysis/user01/comments.txt")
MAX_ITEMS = int(os.environ.get("MAX_ITEMS", "200"))

Path(os.path.dirname(OUT_JSON)).mkdir(parents=True, exist_ok=True)

def H(sec: float) -> str:
    m = int(sec // 60)
    s = sec - m*60
    return f"{m:02d}:{s:05.2f}"

def make_message(e: dict) -> str:
    t1 = H(float(e["start"]))
    t2 = H(float(e.get("end", e["start"] + 0.2)))
    typ = e.get("type", "other")
    cents = e.get("avg_cents", 0.0)

    if typ == "pitch_high":
        return f"{t1}–{t2} 少し高め。息を急ぎすぎない、口の形を小さくしすぎない。出だしを落ち着いて。"
    elif typ == "pitch_low":
        return f"{t1}–{t2} 少し低め。息のスピードを少し上げる、口の中を少し広く。声を前に出す意識。"
    elif typ == "unvoiced_miss":
        return f"{t1}–{t2} 声が入っていないか弱い。直前で静かに息を準備→はっきり声を置く。"
    elif typ == "early_entry":
        return f"{t1}–{t2} 早入り。伴奏の区切りを数えて“1,2,3”で入る。足で軽く拍を取る。"
    elif typ == "late_entry":
        return f"{t1}–{t2} 遅入り。入る直前に小さく息を吸い、迷わずあたまの音を置く。"
    else:
        return f"{t1}–{t2} 音程やタイミングが不安定。肩と首の力を抜き、最初の母音をはっきり。"

def main():
    ev = json.load(open(IN_EVENTS))
    ev = sorted(ev, key=lambda x: x.get("start", 0.0))
    if MAX_ITEMS > 0:
        ev = ev[:MAX_ITEMS]

    rows = []
    for e in ev:
        rows.append({
            "start": float(e["start"]),
            "end": float(e.get("end", e["start"]+0.2)),
            "type": e.get("type","other"),
            "text": make_message(e)
        })

    json.dump({"comments": rows}, open(OUT_JSON, "w"), ensure_ascii=False, indent=2)

    with open(OUT_TXT, "w", encoding="utf-8") as f:
        f.write("■ 要所コメント（最大" + str(MAX_ITEMS) + "件）\n")
        for r in rows:
            f.write("- " + r["text"] + "\n")

    print("wrote:", OUT_JSON, "and", OUT_TXT, "items:", len(rows))

if __name__ == "__main__":
    main()
