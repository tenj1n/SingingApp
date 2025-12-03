# 06_key_offset_check.py
import os, json, math, random
from pathlib import Path
import numpy as np

REF_JSON = os.environ.get("REF_JSON", "SingingApp/analysis/sample01/pitch.json")
USR_JSON = os.environ.get("USR_JSON", "SingingApp/analysis/user01/pitch.json")
OUT_JSON = os.environ.get("OUT_JSON", "SingingApp/analysis/user01/key_offset.json")
OUT_TXT  = os.environ.get("OUT_TXT",  "SingingApp/analysis/user01/key_offset.txt")

# 日本語固定（専門語を使う場合はその場で説明を付ける）
LANG_JA = True

def load_pitch_json(p):
    d = json.load(open(p))
    t = np.array([float(x["t"]) for x in d["track"]], dtype=float)
    f = np.array([np.nan if x["f0_hz"] is None else float(x["f0_hz"]) for x in d["track"]], dtype=float)
    return t, f, d.get("sr", 44100), d.get("hop", 256)

def align_on_ref(t_ref, t_usr):
    idx = np.searchsorted(t_usr, t_ref)
    idx = np.clip(idx, 1, len(t_usr)-1)
    return np.where(np.abs(t_usr[idx-1]-t_ref) <= np.abs(t_usr[idx]-t_ref), idx-1, idx)

# 用語の短い説明（必要なものだけ後で付ける）
def glossary_items(use_octave=False, use_semitone=False, use_cents=False):
    items = []
    if use_octave:
        items.append("オクターブ: 同じメロディを“高さが半分/倍”で歌うこと（とても低い/高い）。")
    if use_semitone:
        items.append("半音: ピアノの隣の鍵盤1つ分の差。カラオケのキー『±1』が半音1つ。")
    if use_cents:
        items.append("セント: 半音を100に細かく割ったもの。±20～40くらいならわずかなズレ。")
    return items

def ja_verdict(verdict, k_oct, semi):
    if verdict == "octave_shift":
        direction = "下" if k_oct < 0 else "上"
        return f"オクターブ{direction}で歌っている可能性が高い（k={k_oct}）"
    if semi == 0:
        return "ほぼ原キー（半音ズレなし）"
    direction = "低い（−）" if semi < 0 else "高い（＋）"
    return f"全体として半音{abs(semi)}つ分{direction}"

def make_advice_ja(verdict, k_oct, semi, med_wrap, std_wrap, within40):
    """
    初心者向けアドバイス。専門語は避け、使う場合は後段の注釈で説明。
    表現は「拍」ではなく、秒やカウントで統一。
    """
    import random
    rnd_seed = int(round(abs(med_wrap or 0) * 10)) + int(std_wrap or 0) + int((within40 or 0)*1000)
    random.seed(rnd_seed)

    tips = []
    # 基礎的な体の使い方（すぐできる内容）
    base_pool = [
        "首と肩の力を抜き、あごを少し引く。力むと音が上がったり下がったりしやすい。",
        "口は横よりも“縦”に開く。声が前に出て、音の上下が合わせやすくなる。",
        "息は止めずに細く長く。吸いすぎると苦しくなり、不安定になりやすい。",
        "大きすぎる声で押さない。中くらいの声量で安定させると合わせやすい。",
        "低い音ではつぶれないよう、口の中を少し広く保つ。"
    ]
    tips += random.sample(base_pool, k=2)

    # 判定別メイン
    if verdict == "octave_shift":
        direction = "下" if k_oct < 0 else "上"
        main = [
            f"今回は歌手より1オクターブ{direction}で歌っています。",
            "歌手と同じ高さで練習したい場合：まずは出だし5〜10秒だけ同じ音でまねる→慣れたら15秒→30秒と伸ばす。",
            "カラオケの“キー変更”で歌いやすい高さに寄せてから、段階的に元の高さへ戻すのも有効。"
        ]
        tips = main + tips
        if med_wrap <= -20:
            tips.append("出だしで下がりやすい。最初の一声は息を少し速く、はっきり出す。")
        elif med_wrap >= 20:
            tips.append("出だしで上がりやすい。押さずに落ち着いた声量で入り、音を落ち着かせる。")
    else:
        if semi != 0:
            sgn = "低い" if semi < 0 else "高い"
            tips.append(f"全体に{sgn}。カラオケの“キー”を『±{abs(semi)}』動かして歌いやすい高さに合わせる（※半音=キー1つ）。")
        if med_wrap <= -20:
            tips.append("音が下に寄りやすい。入りで息を少し速くして、音を“上に置く”意識を持つ。")
        elif med_wrap >= 20:
            tips.append("音が上に寄りやすい。強く押さず、中くらいの声量で安定させてから合わせる。")

    # 揺れが大きい/合致率が低いとき：秒とカウントで指示
    if (std_wrap or 0) > 120 or (within40 or 0) < 0.4:
        tips += [
            "短いフレーズ練習：1つの音を“約2〜3秒”まっすぐ伸ばす→次の音へ。これを3回×2セット。",
            "基準音合わせ：ピアノ音や無料チューナーアプリを鳴らし、その音に吸い寄せるように“1,2,3”と数えながら合わせる。"
        ]

    header = "▼ 練習の方向性（初心者向け）"
    return header + "\n" + "\n".join(f"- {t}" for t in tips)

def main():
    tR, fR, srR, hopR = load_pitch_json(REF_JSON)
    tU, fU, srU, hopU = load_pitch_json(USR_JSON)

    idx = align_on_ref(tR, tU)
    fU_on_R = fU[idx]

    mask = (~np.isnan(fR)) & (~np.isnan(fU_on_R)) & (fR > 0) & (fU_on_R > 0)
    out = {}

    if not np.any(mask):
        out = {"error": "no_voiced_overlap"}
    else:
        cents = 1200.0 * np.log2(fU_on_R[mask] / fR[mask])

        med = float(np.nanmedian(cents))
        mean = float(np.nanmean(cents))
        std  = float(np.nanstd(cents))

        semitone_offset = int(round(med / 100.0))            # 100c ≒ 半音1
        cents_of_semitone = semitone_offset * 100

        k_oct = int(round(med / 1200.0))                     # 1200c ≒ 1オクターブ
        wrapped = cents - (k_oct * 1200.0)                   # オクターブ差を除去
        med_wrapped = float(np.nanmedian(wrapped))
        std_wrapped = float(np.nanstd(wrapped))
        within_40c  = float(np.nanmean(np.abs(wrapped) <= 40.0)) if wrapped.size else float("nan")

        likely_octave = (abs(k_oct) >= 1) and (abs(med - 1200.0 * k_oct) < 200.0)
        verdict = "octave_shift" if likely_octave else "key_shift"
        verdict_ja = ja_verdict(verdict, k_oct, semitone_offset)

        # アドバイス本文
        advice_ja = make_advice_ja(verdict, k_oct, semitone_offset, med_wrapped, std_wrapped, within_40c)

        # 必要な用語だけ注釈を付ける
        notes = glossary_items(
            use_octave=True if verdict == "octave_shift" else False,
            use_semitone=True if semitone_offset != 0 else False,
            use_cents=True
        )
        notes_text = ""
        if notes:
            notes_text = "\n※ 用語の説明\n" + "\n".join(f"- {n}" for n in notes)

        summary_ja = (
            "◇ キー／オクターブずれ診断\n"
            f"- セント差の中央値: {med:.1f} c（数値がマイナスなら低め）\n"
            f"- 平均/標準偏差   : {mean:.1f} / {std:.1f} c\n"
            f"- 半音オフセット  : {semitone_offset}（{cents_of_semitone} c）\n"
            f"- オクターブ係数  : {k_oct}（×1200 c）\n"
            f"- オクターブ同値に丸めた中央値: {med_wrapped:.1f} c\n"
            f"- 同値±40c 以内の割合: {within_40c:.3f}\n"
            f"- 判定: {verdict_ja}\n\n"
            f"{advice_ja}\n"
            f"{notes_text}\n"
        )

        out = {
            "frames": int(cents.size),
            "median_cents": round(med, 1),
            "mean_cents": round(mean, 1),
            "std_cents": round(std, 1),
            "semitone_offset": semitone_offset,
            "semitone_offset_cents": cents_of_semitone,
            "octave_k": k_oct,
            "wrapped_median_cents": round(med_wrapped, 1),
            "wrapped_std_cents": round(std_wrapped, 1),
            "wrapped_within_40c": round(within_40c, 3) if not math.isnan(within_40c) else None,
            "verdict": verdict,
            "verdict_ja": verdict_ja,
            "summary_ja": summary_ja,
            "advice_ja": advice_ja,
            "notes_ja": notes,  # JSONにも注釈を入れておく
        }

    Path(os.path.dirname(OUT_JSON)).mkdir(parents=True, exist_ok=True)
    json.dump(out, open(OUT_JSON, "w"), ensure_ascii=False, indent=2)

    with open(OUT_TXT, "w") as f:
        if "error" in out:
            f.write("有声区間の重なりが見つかりませんでした。\n")
        else:
            f.write(out["summary_ja"])

    print("wrote:", OUT_JSON, "and", OUT_TXT)

if __name__ == "__main__":
    main()
