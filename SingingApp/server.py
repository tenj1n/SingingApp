# SingingApp/server.py

from flask import Flask, request, jsonify
from flask_cors import CORS
from pathlib import Path
import uuid, json
import os
from datetime import datetime

from openai import OpenAI  # pip install openai

app = Flask(__name__)
CORS(app)

openai_client = OpenAI()

BASE_DIR = Path(__file__).resolve().parent.parent
PROJECT_DIR = BASE_DIR / "SingingApp"
ANALYSIS_DIR = PROJECT_DIR / "analysis"

UPLOAD_DIR = ANALYSIS_DIR / "user01" / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


# --------------------------------------------------
# 共通ヘルパー
# --------------------------------------------------
def json_error(status: int, code: str, message: str, **extra):
    payload = {"ok": False, "code": code, "message": message}
    if extra:
        payload["extra"] = extra
    return jsonify(payload), status


def read_json_or_error(path: Path, label: str):
    if not path.exists():
        raise FileNotFoundError(f"{label} not found: {path}")
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise ValueError(f"{label} invalid JSON: {path} ({e})")


def safe_len(x):
    return len(x) if isinstance(x, list) else None


def require_openai_key_or_error():
    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY is not set (export OPENAI_API_KEY=...)")


def _normalize_ai_comment(text: str):
    # ```json ... ``` を剥がす
    t = (text or "").strip()
    t = t.replace("```json", "").replace("```", "").strip()

    # JSONなら parse
    try:
        obj = json.loads(t)
        if isinstance(obj, dict):
            title = str(obj.get("title") or "AIコメント")
            body = str(obj.get("body") or "")
            return title, body
    except Exception:
        pass

    # ダメならそのまま本文
    return "AIコメント", t


# --------------------------------------------------
# 履歴（JSONファイル）ユーティリティ
# --------------------------------------------------
def _history_path(user_id: str) -> Path:
    usr_dir = ANALYSIS_DIR / user_id
    usr_dir.mkdir(parents=True, exist_ok=True)
    return usr_dir / "history.json"


def _load_history(user_id: str):
    p = _history_path(user_id)
    if not p.exists():
        return []
    try:
        with p.open("r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _save_history(user_id: str, items):
    p = _history_path(user_id)
    with p.open("w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)


# --------------------------------------------------
# ヘルスチェック
# --------------------------------------------------
@app.get("/health")
def health():
    return jsonify({"ok": True, "service": "singing-backend"})


# --------------------------------------------------
# 録音ファイルアップロード
# --------------------------------------------------
@app.post("/upload")
def upload():
    if "audio" not in request.files:
        return jsonify({"ok": False, "error": "no 'audio' field"}), 400

    f = request.files["audio"]
    if not f.filename:
        return jsonify({"ok": False, "error": "empty filename"}), 400

    ext = (Path(f.filename).suffix or ".m4a").lower()
    file_id = str(uuid.uuid4())
    out_path = UPLOAD_DIR / f"{file_id}{ext}"
    f.save(out_path)

    return jsonify(
        {
            "ok": True,
            "file_id": file_id,
            "saved_path": str(out_path),
            "note": "保存のみ。解析は別エンドポイントで行う想定。",
        }
    )


# --------------------------------------------------
# 解析結果をまとめて返す API
# 例: /api/analysis/orphans/user01
# --------------------------------------------------
@app.get("/api/analysis/<song_id>/<user_id>")
def get_analysis(song_id: str, user_id: str):
    try:
        ref_pitch_path = ANALYSIS_DIR / "songs" / song_id / "ref" / "pitch.json"

        usr_dir = ANALYSIS_DIR / user_id
        usr_pitch_path = usr_dir / "pitch.json"
        events_path = usr_dir / "events.json"
        summary_path = usr_dir / "summary.json"

        ref_pitch = read_json_or_error(ref_pitch_path, "ref_pitch")
        usr_pitch = read_json_or_error(usr_pitch_path, "usr_pitch")
        events = read_json_or_error(events_path, "events")
        summary = read_json_or_error(summary_path, "summary")

        resp = {
            "ok": True,
            "session_id": f"demo-{song_id}-{user_id}",
            "song_id": song_id,
            "user_id": user_id,
            "ref_pitch": ref_pitch,
            "usr_pitch": usr_pitch,
            "events": events,
            "summary": summary,
            "meta": {
                "paths": {
                    "ref_pitch": str(ref_pitch_path),
                    "usr_pitch": str(usr_pitch_path),
                    "events": str(events_path),
                    "summary": str(summary_path),
                },
                "sizes": {
                    "ref_pitch_bytes": ref_pitch_path.stat().st_size,
                    "usr_pitch_bytes": usr_pitch_path.stat().st_size,
                    "events_bytes": events_path.stat().st_size,
                    "summary_bytes": summary_path.stat().st_size,
                },
                "counts": {
                    "ref_track": safe_len(ref_pitch.get("track")) if isinstance(ref_pitch, dict) else None,
                    "usr_track": safe_len(usr_pitch.get("track")) if isinstance(usr_pitch, dict) else None,
                    "events": safe_len(events),
                },
            },
        }
        return jsonify(resp)

    except FileNotFoundError as e:
        return json_error(404, "FILE_NOT_FOUND", str(e))
    except ValueError as e:
        return json_error(500, "INVALID_JSON", str(e))
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# --------------------------------------------------
# AIコメント生成 API
# 例: POST /api/comment/orphans/user01
# --------------------------------------------------
@app.post("/api/comment/<song_id>/<user_id>")
def ai_comment(song_id: str, user_id: str):
    try:
        require_openai_key_or_error()

        usr_dir = ANALYSIS_DIR / user_id
        events_path = usr_dir / "events.json"
        summary_path = usr_dir / "summary.json"

        events = []
        summary = {}
        try:
            events = read_json_or_error(events_path, "events")
            summary = read_json_or_error(summary_path, "summary")
        except Exception:
            events = []
            summary = {}

        payload = request.get_json(silent=True) or {}
        stats = payload.get("stats", {}) or {}

        tol_cents = stats.get("tolCents", summary.get("tol_cents", 40.0))
        percent_within = stats.get("percentWithinTol")
        mean_abs = stats.get("meanAbsCents")
        sample_count = stats.get("sampleCount")

        score_strict = stats.get("scoreStrict")
        score_oct = stats.get("scoreOctaveInvariant")
        octave_now = stats.get("octaveInvariantNow")

        event_head = []
        if isinstance(events, list):
            for e in events[:10]:
                if isinstance(e, dict):
                    event_head.append({
                        "start": e.get("start"),
                        "end": e.get("end"),
                        "type": e.get("type"),
                        "avg_cents": e.get("avg_cents"),
                        "max_cents": e.get("max_cents"),
                    })

        model_input = {
            "song_id": song_id,
            "user_id": user_id,
            "tolCents": tol_cents,
            "percentWithinTol": percent_within,
            "meanAbsCents": mean_abs,
            "sampleCount": sample_count,
            "scoreStrict": score_strict,
            "scoreOctaveInvariant": score_oct,
            "octaveInvariantNow": octave_now,
            "summary": {
                "verdict": summary.get("verdict"),
                "reason": summary.get("reason"),
                "tips": summary.get("tips"),
            },
            "events_head": event_head,
        }

        system = """
あなたはカラオケ初心者向けの歌のコーチです。専門用語は使いません。

出力は必ずJSONのみ：
{"title": string, "body": string}

ルール：
- 日本語・短文・絵文字なし
- bodyは4〜6行まで
- cents/Hz/MIDI/オクターブ等の用語は禁止（「高い/低い」「1段上/下」に言い換え）
- 数字は基本1つまで（秒も出さない）
- 必ず「今日やる練習」を2つ書く（すぐできる内容）
- 最後に一言だけ励ます

構成：
1行目：今の傾向
2行目：原因の可能性
3〜4行目：練習①②（具体的に）
5行目：目標
6行目：励まし
""".strip()

        user = "次のJSONを読んでコメントを作成してください。\n" + json.dumps(model_input, ensure_ascii=False)

        resp = openai_client.responses.create(
            model="gpt-5.2",
            input=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        )

        llm_text = (getattr(resp, "output_text", "") or "").strip()
        title, body = _normalize_ai_comment(llm_text)

        return jsonify({"ok": True, "title": title, "body": body})

    except RuntimeError as e:
        return json_error(500, "OPENAI_KEY_MISSING", str(e))
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# --------------------------------------------------
# ★履歴：追加（保存） API
# 例: POST /api/history/orphans/user01/append
# --------------------------------------------------
@app.post("/api/history/<song_id>/<user_id>/append")
def history_append(song_id: str, user_id: str):
    try:
        payload = request.get_json(silent=True) or {}

        # iOSからは camelCase で来てもOKにする
        comment_title = payload.get("commentTitle") or payload.get("comment_title") or "AIコメント"
        comment_body  = payload.get("commentBody")  or payload.get("comment_body")  or ""

        score100 = payload.get("score100")
        score100_strict = payload.get("score100Strict") or payload.get("score100_strict")
        score100_oct = payload.get("score100OctaveInvariant") or payload.get("score100_octave_invariant")
        octave_now = payload.get("octaveInvariantNow") or payload.get("octave_invariant_now")

        tol_cents = payload.get("tolCents") or payload.get("tol_cents")
        percent_within = payload.get("percentWithinTol") or payload.get("percent_within_tol")
        mean_abs = payload.get("meanAbsCents") or payload.get("mean_abs_cents")
        sample_count = payload.get("sampleCount") or payload.get("sample_count")

        item = {
            "id": str(uuid.uuid4()),
            "song_id": song_id,
            "user_id": user_id,
            "created_at": datetime.utcnow().isoformat(timespec="seconds"),
            "comment_title": str(comment_title),
            "comment_body": str(comment_body),

            "score100": score100,
            "score100_strict": score100_strict,
            "score100_octave_invariant": score100_oct,
            "octave_invariant_now": octave_now,

            "tol_cents": tol_cents,
            "percent_within_tol": percent_within,
            "mean_abs_cents": mean_abs,
            "sample_count": sample_count,
        }

        items = _load_history(user_id)
        items.append(item)

        # 新しい順にしたいならここで並べ替え（created_at文字列でもISOならソートできる）
        items.sort(key=lambda x: x.get("created_at", ""), reverse=True)

        _save_history(user_id, items)

        return jsonify({"ok": True, "item": item})

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# --------------------------------------------------
# 履歴：一覧 API（今はUI無くてもOK）
# 例: GET /api/history/user01
# --------------------------------------------------
@app.get("/api/history/<user_id>")
def history_list(user_id: str):
    try:
        items = _load_history(user_id)
        return jsonify({"ok": True, "user_id": user_id, "items": items})
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# --------------------------------------------------
# 履歴：削除 API（今はUI無くてもOK）
# 例: DELETE /api/history/user01/<history_id>
# --------------------------------------------------
@app.delete("/api/history/<user_id>/<history_id>")
def history_delete(user_id: str, history_id: str):
    try:
        items = _load_history(user_id)
        before = len(items)
        items = [x for x in items if str(x.get("id")) != str(history_id)]
        _save_history(user_id, items)
        deleted = (before != len(items))
        return jsonify({"ok": True, "message": "deleted" if deleted else "not_found"})
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)
