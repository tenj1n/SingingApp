import os
import json
import uuid
import sqlite3
import hashlib
from pathlib import Path
from datetime import datetime, timezone

from flask import Flask, request, jsonify, g
from flask_cors import CORS

from openai import OpenAI  # pip install openai


app = Flask(__name__)
CORS(app)

openai_client = OpenAI()

BASE_DIR = Path(__file__).resolve().parent.parent
PROJECT_DIR = BASE_DIR / "SingingApp"
ANALYSIS_DIR = PROJECT_DIR / "analysis"
ANALYSIS_DIR.mkdir(parents=True, exist_ok=True)

UPLOAD_DIR = ANALYSIS_DIR / "user01" / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

# SQLite DB
DB_PATH = ANALYSIS_DIR / "history.sqlite3"

# --------------------------------------------------
# 研究ログ用の「実験条件」デフォルト
# --------------------------------------------------
# プロンプトを変えたらここを v2, v3... と更新する想定
PROMPT_VERSION_DEFAULT = "v1"

# ai_comment() で使っているモデル名（履歴にも入れる）
AI_MODEL_NAME = "gpt-5.2"


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


def iso_utc_z():
    # 例: 2025-12-19T10:00:00Z
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


# --------------------------------------------------
# SQLite（履歴）ヘルパー
# --------------------------------------------------
def get_db():
    if "db" not in g:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        g.db = conn
    return g.db


@app.teardown_appcontext
def close_db(exception=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    conn = sqlite3.connect(DB_PATH)

    # 新規DBなら最初から全部の列を作る
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS history (
            id TEXT PRIMARY KEY,
            song_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            created_at TEXT NOT NULL,

            comment_title TEXT NOT NULL,
            comment_body  TEXT NOT NULL,

            score100 REAL,
            score100_strict REAL,
            score100_octave_invariant REAL,
            octave_invariant_now INTEGER,

            tol_cents REAL,
            percent_within_tol REAL,
            mean_abs_cents REAL,
            sample_count INTEGER,

            -- 二重保存防止
            client_hash TEXT,

            -- 研究ログ用（実験条件）
            comment_source TEXT,
            prompt_version TEXT,
            model TEXT,
            app_version TEXT
        )
        """
    )

    # 既存DBへの後付け（列が無い場合だけ追加）
    cols = [r[1] for r in conn.execute("PRAGMA table_info(history)").fetchall()]

    def add_col(name: str, ddl: str):
        if name not in cols:
            conn.execute(ddl)

    add_col("client_hash", "ALTER TABLE history ADD COLUMN client_hash TEXT")
    add_col("comment_source", "ALTER TABLE history ADD COLUMN comment_source TEXT")
    add_col("prompt_version", "ALTER TABLE history ADD COLUMN prompt_version TEXT")
    add_col("model", "ALTER TABLE history ADD COLUMN model TEXT")
    add_col("app_version", "ALTER TABLE history ADD COLUMN app_version TEXT")

    # user_id + client_hash で一意（同じ保存内容は二重に入らない）
    conn.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_history_user_client_hash ON history(user_id, client_hash)"
    )

    # よく使う並び順
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_history_user_created ON history(user_id, created_at DESC)"
    )

    # 研究用途：sourceやprompt_versionで絞るなら便利（任意）
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_history_user_source_created ON history(user_id, comment_source, created_at DESC)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_history_user_prompt_created ON history(user_id, prompt_version, created_at DESC)"
    )

    conn.commit()
    conn.close()


def row_to_item(r: sqlite3.Row):
    # iOSの HistoryItem.CodingKeys に合わせて snake_case で返す
    return {
        "id": r["id"],
        "song_id": r["song_id"],
        "user_id": r["user_id"],
        "created_at": r["created_at"],

        "comment_title": r["comment_title"],
        "comment_body": r["comment_body"],

        "score100": r["score100"],
        "score100_strict": r["score100_strict"],
        "score100_octave_invariant": r["score100_octave_invariant"],
        "octave_invariant_now": (bool(r["octave_invariant_now"]) if r["octave_invariant_now"] is not None else None),

        "tol_cents": r["tol_cents"],
        "percent_within_tol": r["percent_within_tol"],
        "mean_abs_cents": r["mean_abs_cents"],
        "sample_count": r["sample_count"],

        # ★研究ログ用（追加）
        "comment_source": r["comment_source"],
        "prompt_version": r["prompt_version"],
        "model": r["model"],
        "app_version": r["app_version"],
    }


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
            model=AI_MODEL_NAME,
            input=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        )

        llm_text = (getattr(resp, "output_text", "") or "").strip()
        title, body = _normalize_ai_comment(llm_text)

        # 研究用途：APIで返すだけ（保存は iOS が /append でやる）
        return jsonify({"ok": True, "title": title, "body": body, "model": AI_MODEL_NAME, "prompt_version": PROMPT_VERSION_DEFAULT})

    except RuntimeError as e:
        return json_error(500, "OPENAI_KEY_MISSING", str(e))
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# --------------------------------------------------
# ★履歴：追加（保存） API（SQLite）
# 例: POST /api/history/orphans/user01/append
# --------------------------------------------------
@app.post("/api/history/<song_id>/<user_id>/append")
def history_append(song_id: str, user_id: str):
    try:
        # raw body（ハッシュ用）※ cache=True で後の get_json と両立
        raw = request.get_data(cache=True) or b""
        payload = request.get_json(silent=True) or {}

        # 0.0 や False を潰さない取り方
        def pick(payload, camel, snake):
            if camel in payload:
                return payload[camel]
            return payload.get(snake)

        # iOSからは camelCase で来る（snake_case も許容）
        comment_title = payload.get("commentTitle") or payload.get("comment_title") or "AIコメント"
        comment_body  = payload.get("commentBody")  or payload.get("comment_body")  or ""

        if not str(comment_body).strip():
            return jsonify({"ok": False, "item": None, "message": "commentBody is empty"}), 400

        score100 = pick(payload, "score100", "score100")
        score100_strict = pick(payload, "score100Strict", "score100_strict")
        score100_oct = pick(payload, "score100OctaveInvariant", "score100_octave_invariant")
        octave_now = pick(payload, "octaveInvariantNow", "octave_invariant_now")

        tol_cents = pick(payload, "tolCents", "tol_cents")
        percent_within = pick(payload, "percentWithinTol", "percent_within_tol")
        mean_abs = pick(payload, "meanAbsCents", "mean_abs_cents")
        sample_count = pick(payload, "sampleCount", "sample_count")

        # ★二重保存防止キー（iOSがヘッダーで送る）
        client_hash = request.headers.get("Idempotency-Key")
        if not client_hash:
            # 万一ヘッダーが無い場合の保険（raw bodyで作る）
            client_hash = hashlib.sha256(raw).hexdigest()

        # ★研究ログ用（実験条件）
        # iOS側をまだ変えない前提で、基本はサーバ側デフォルト
        # もし後で iOS から送るなら、ヘッダーを使うと簡単
        comment_source = request.headers.get("X-Comment-Source") or "ai"
        prompt_version = request.headers.get("X-Prompt-Version") or PROMPT_VERSION_DEFAULT
        model_name = request.headers.get("X-AI-Model") or AI_MODEL_NAME
        app_version = request.headers.get("X-App-Version")  # 無ければ None のまま

        history_id = str(uuid.uuid4())
        created_at = iso_utc_z()

        db = get_db()

        # ★重複は INSERT しない
        cur = db.execute(
            """
            INSERT OR IGNORE INTO history (
                id, song_id, user_id, created_at,
                comment_title, comment_body,
                score100, score100_strict, score100_octave_invariant, octave_invariant_now,
                tol_cents, percent_within_tol, mean_abs_cents, sample_count,
                client_hash,
                comment_source, prompt_version, model, app_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                history_id, song_id, user_id, created_at,
                str(comment_title), str(comment_body),
                score100, score100_strict, score100_oct,
                1 if bool(octave_now) else 0,
                tol_cents, percent_within, mean_abs, sample_count,
                client_hash,
                comment_source, prompt_version, model_name, app_version
            )
        )
        db.commit()

        # 追加できなかった＝既に同じ client_hash が存在（重複）
        if (cur.rowcount or 0) == 0:
            row = db.execute(
                "SELECT * FROM history WHERE user_id = ? AND client_hash = ? ORDER BY created_at DESC LIMIT 1",
                (user_id, client_hash)
            ).fetchone()

            if row is None:
                return jsonify({"ok": True, "item": None, "message": "duplicate"}), 200

            item = row_to_item(row)
            return jsonify({"ok": True, "item": item, "message": "duplicate"}), 200

        # 追加成功した場合
        item = {
            "id": history_id,
            "song_id": song_id,
            "user_id": user_id,
            "created_at": created_at,

            "comment_title": str(comment_title),
            "comment_body": str(comment_body),

            "score100": score100,
            "score100_strict": score100_strict,
            "score100_octave_invariant": score100_oct,
            "octave_invariant_now": bool(octave_now),

            "tol_cents": tol_cents,
            "percent_within_tol": percent_within,
            "mean_abs_cents": mean_abs,
            "sample_count": sample_count,

            # ★研究ログ用（追加）
            "comment_source": comment_source,
            "prompt_version": prompt_version,
            "model": model_name,
            "app_version": app_version,
        }
        return jsonify({"ok": True, "item": item, "message": None})

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# --------------------------------------------------
# 履歴：一覧 API（SQLite）
# 例: GET /api/history/user01
# 追加: ?source=ai&prompt=v1&model=gpt-5.2&limit=50&offset=0
# --------------------------------------------------
@app.get("/api/history/<user_id>")
def history_list(user_id: str):
    try:
        # クエリ（未指定なら None）
        source = request.args.get("source")          # 例: ai
        prompt = request.args.get("prompt")          # 例: v1
        model  = request.args.get("model")           # 例: gpt-5.2
        limit  = request.args.get("limit", type=int) # 例: 50
        offset = request.args.get("offset", type=int)

        # limitの安全策
        if limit is None:
            limit = 200
        limit = max(1, min(limit, 500))

        if offset is None:
            offset = 0
        offset = max(0, offset)

        db = get_db()

        where = ["user_id = ?"]
        params = [user_id]

        # 追加フィルタ（指定されたものだけ）
        if source:
            where.append("comment_source = ?")
            params.append(source)
        if prompt:
            where.append("prompt_version = ?")
            params.append(prompt)
        if model:
            where.append("model = ?")
            params.append(model)

        sql = f"""
            SELECT
                id, song_id, user_id, created_at,
                comment_title, comment_body,
                score100, score100_strict, score100_octave_invariant, octave_invariant_now,
                tol_cents, percent_within_tol, mean_abs_cents, sample_count,
                comment_source, prompt_version, model, app_version
            FROM history
            WHERE {" AND ".join(where)}
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """

        rows = db.execute(sql, tuple(params + [limit, offset])).fetchall()

        items = []
        for r in rows:
            items.append({
                "id": r["id"],
                "song_id": r["song_id"],
                "user_id": r["user_id"],
                "created_at": r["created_at"],

                "comment_title": r["comment_title"] or "",
                "comment_body": r["comment_body"] or "",

                "score100": r["score100"],
                "score100_strict": r["score100_strict"],
                "score100_octave_invariant": r["score100_octave_invariant"],
                "octave_invariant_now": bool(r["octave_invariant_now"]) if r["octave_invariant_now"] is not None else None,

                "tol_cents": r["tol_cents"],
                "percent_within_tol": r["percent_within_tol"],
                "mean_abs_cents": r["mean_abs_cents"],
                "sample_count": r["sample_count"],

                "comment_source": r["comment_source"],
                "prompt_version": r["prompt_version"],
                "model": r["model"],
                "app_version": r["app_version"],
            })

        return jsonify({
            "ok": True,
            "user_id": user_id,
            "items": items,
            "message": None
        })

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# --------------------------------------------------
# 履歴：削除 API（SQLite）
# 例: DELETE /api/history/user01/<history_id>
# --------------------------------------------------
@app.delete("/api/history/<user_id>/<history_id>")
def history_delete(user_id: str, history_id: str):
    try:
        db = get_db()
        cur = db.execute(
            "DELETE FROM history WHERE user_id = ? AND id = ?",
            (user_id, history_id)
        )
        db.commit()

        deleted = (cur.rowcount or 0) > 0
        return jsonify({"ok": True, "message": "deleted" if deleted else "not_found"})

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


if __name__ == "__main__":
    init_db()
    app.run(host="127.0.0.1", port=5000, debug=True)
