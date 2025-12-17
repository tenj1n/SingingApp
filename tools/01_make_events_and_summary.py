import json, math, argparse
from pathlib import Path

def cents(a, b):
    return 1200.0 * math.log2(a / b)

def group_events(flags, times, kind, cents_values=None):
    events = []
    n = len(flags)
    i = 0
    while i < n:
        if not flags[i]:
            i += 1
            continue
        j = i
        while j < n and flags[j]:
            j += 1
        start = times[i][0]
        end = times[j-1][1]
        ev = {"start": round(start, 3), "end": round(end, 3), "type": kind}
        if cents_values is not None:
            seg = cents_values[i:j]
            if seg:
                ev["avg_cents"] = round(sum(seg) / len(seg), 1)
                if kind == "pitch_low":
                    ev["max_cents"] = round(min(seg), 1)  # より低い（負方向が大）
                elif kind == "pitch_high":
                    ev["max_cents"] = round(max(seg), 1)
        events.append(ev)
        i = j
    return events

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--usr", required=True)
    ap.add_argument("--out_events", required=True)
    ap.add_argument("--out_summary", required=True)
    ap.add_argument("--tol", type=float, default=40.0)
    args = ap.parse_args()

    ref = json.load(open(args.ref, "r", encoding="utf-8"))
    usr = json.load(open(args.usr, "r", encoding="utf-8"))

    if ref.get("sr") != usr.get("sr") or ref.get("hop") != usr.get("hop"):
        raise RuntimeError(f"sr/hop mismatch ref={ref.get('sr')}/{ref.get('hop')} usr={usr.get('sr')}/{usr.get('hop')}")

    ref_tr = ref["track"]
    usr_tr = usr["track"]
    n = min(len(ref_tr), len(usr_tr))

    sr = float(ref["sr"])
    hop = float(ref["hop"])
    tol = float(args.tol)

    times = []
    cents_list = []
    low_flags = []
    high_flags = []
    unvoiced_miss_flags = []

    voiced_frames = 0
    within = 0

    for i in range(n):
        t0 = float(ref_tr[i]["t"])
        t1 = t0 + hop / sr
        times.append((t0, t1))

        rf = ref_tr[i].get("f0_hz")
        uf = usr_tr[i].get("f0_hz")

        if rf is not None and uf is None:
            unvoiced_miss_flags.append(True)
            low_flags.append(False)
            high_flags.append(False)
            cents_list.append(0.0)
            continue

        unvoiced_miss_flags.append(False)

        if rf is None or uf is None:
            low_flags.append(False)
            high_flags.append(False)
            cents_list.append(0.0)
            continue

        voiced_frames += 1
        c = cents(float(uf), float(rf))
        cents_list.append(c)

        if abs(c) <= tol:
            within += 1

        low_flags.append(c < -tol)
        high_flags.append(c > tol)

    sec_total = round(times[-1][1], 3) if times else 0.0

    voiced_cents = [c for c in cents_list if c != 0.0]
    mean = sum(voiced_cents)/len(voiced_cents) if voiced_cents else 0.0
    std = math.sqrt(sum((x-mean)**2 for x in voiced_cents)/len(voiced_cents)) if voiced_cents else 0.0

    def percentile(xs, q):
        if not xs:
            return 0.0
        xs = sorted(xs)
        k = (len(xs)-1) * q
        f = math.floor(k)
        c = math.ceil(k)
        if f == c:
            return xs[int(k)]
        return xs[f] + (xs[c] - xs[f]) * (k - f)

    unvoiced_miss_seconds = sum((times[i][1]-times[i][0]) for i in range(n) if unvoiced_miss_flags[i])

    summary = {
        "tol_cents": tol,
        "frames": int(n),
        "seconds": sec_total,
        "mean_cents": round(mean, 3),
        "median_cents": round(percentile(voiced_cents, 0.5), 3),
        "std_cents": round(std, 3),
        "percent_within_tol": round((within/voiced_frames) if voiced_frames else 0.0, 4),
        "percent_low": round((sum(low_flags)/voiced_frames) if voiced_frames else 0.0, 4),
        "percent_high": round((sum(high_flags)/voiced_frames) if voiced_frames else 0.0, 4),
        "p10_cents": round(percentile(voiced_cents, 0.10), 3),
        "p90_cents": round(percentile(voiced_cents, 0.90), 3),
        "unvoiced_miss_seconds": round(unvoiced_miss_seconds, 3),
    }

    if summary["percent_within_tol"] >= 0.85:
        summary["verdict"] = "mostly_ok"
        summary["reason"] = "おおむね基準に近いピッチで歌えています。"
        summary["tips"] = "外れている区間だけを重点的に練習すると効率が良いです。"
    else:
        summary["verdict"] = "needs_work"
        summary["reason"] = "基準から外れる区間が目立ちます。"
        summary["tips"] = "低い/高い傾向が強い区間を中心に、音程を合わせる練習をしましょう。"

    events = []
    events += group_events(low_flags, times, "pitch_low", cents_values=cents_list)
    events += group_events(high_flags, times, "pitch_high", cents_values=cents_list)
    events += group_events(unvoiced_miss_flags, times, "unvoiced_miss", cents_values=None)

    Path(args.out_events).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out_summary).parent.mkdir(parents=True, exist_ok=True)

    with open(args.out_events, "w", encoding="utf-8") as f:
        json.dump(events, f, ensure_ascii=False)

    with open(args.out_summary, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False)

    print("WROTE:", args.out_events, "events=", len(events))
    print("WROTE:", args.out_summary, "verdict=", summary.get("verdict"))

if __name__ == "__main__":
    main()
