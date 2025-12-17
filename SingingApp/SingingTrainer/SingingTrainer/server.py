# SingingApp/server.py

from flask import Flask, request, jsonify
from flask_cors import CORS
from pathlib import Path
import uuid, json
import os

from openai import OpenAI  # pip install openai

app = Flask(__name__)
CORS(app)

# OpenAI クライアント（APIキーは環境変数 OPENAI_API_KEY から読む）
openai_client = OpenAI()

# __file__ = .../SingingTrainerApp/SingingApp/SingingApp/server.py を想定
# parent.parent = .../SingingTrainerApp/SingingApp （プロジェクトのルート）
BASE_DIR = Path(__file__).resolve().parent.parent

# Xcode プロジェクト側のフォルダ（SingingApp 配下に analysis などがある想定）
PROJECT_DIR = BASE_DIR / "SingingApp"

# 解析系ファイルを置いているディレクトリ
ANALYSIS_DIR = PROJECT_DIR / "analysis"

# 録音アップロード先 (例: SingingApp/analysis/user01/uploads)
UPLOAD_DIR = ANALYSIS_DIR / "user01" / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


# --------------------------------------------------
# 共通ヘルパー（「原因が追える」ように強化版）
# --------------------------------------------------
def json_error(status: int, code: str, message: str, **extra):
    """エラーを必ず同じ形で返す"""
    payload = {"ok": False, "code": code, "message": message}
    if extra:
        payload["extra"] = extra
    return jsonify(payload), status


def read_json_or_error(path: Path, label: str):
    """
    JSON を読む。
    - 無い → FileNotFoundError
    - 壊れてる → ValueError
    """
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
    """
    OPENAI_API_KEY が無いときに分かりやすく落とす
    """
    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY is not set (export OPENAI_API_KEY=...)")


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
    """
    マルチパートで audio ファイルを受け取って保存する。
    フィールド名: 'audio' （iOS 側からこれで送る）
    """
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
# 解析結果をまとめて返す API（デバッグ強化版）
# 例: /api/analysis/orphans/user01
# --------------------------------------------------
@app.get("/api/analysis/<song_id>/<user_id>")
def get_analysis(song_id: str, user_id: str):
    """
    1回のリクエストでまとめて返す:
      - ref_pitch:  analysis/songs/<song_id>/ref/pitch.json
      - usr_pitch:  analysis/<user_id>/pitch.json
      - events:     analysis/<user_id>/events.json
      - summary:    analysis/<user_id>/summary.json
    """
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
# ★AIコメント生成 API
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

        # ★ここが「プロンプトを書く場所」：短め初心者向けに差し替え済み
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
1行目：今の傾向（例：全体的に低め）
2行目：原因の可能性（例：高さが1段ずれているかも）
3〜4行目：練習①②（具体的に）
5行目：目標（例：最初の1音を合わせる）
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

        text = (getattr(resp, "output_text", "") or "").strip()

        title = "AIコメント"
        body = text if text else "コメント生成に失敗しました（空の応答）"
        try:
            obj = json.loads(text)
            if isinstance(obj, dict):
                title = str(obj.get("title") or title)
                body = str(obj.get("body") or body)
        except Exception:
            pass

        return jsonify({
            "ok": True,
            "title": title,
            "body": body,
            "meta": {"song_id": song_id, "user_id": user_id}
        })

    except FileNotFoundError as e:
        return json_error(404, "FILE_NOT_FOUND", str(e))
    except ValueError as e:
        return json_error(500, "INVALID_JSON", str(e))
    except RuntimeError as e:
        return json_error(500, "OPENAI_KEY_MISSING", str(e))
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# --------------------------------------------------
# ローカル実行
# --------------------------------------------------
if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)
