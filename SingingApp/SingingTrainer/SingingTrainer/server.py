# server.py
from __future__ import annotations

import os
import io
import json
import uuid
import hashlib
import sqlite3
import wave
import math
import subprocess
import tempfile
import secrets
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Any, Dict, Tuple, List

import numpy as np
from flask import Flask, request, jsonify, g

# ==================================================
# Config
# ==================================================
AI_MODEL_NAME = os.getenv("AI_MODEL_NAME", "gpt-4.1-mini")
PROMPT_VERSION_DEFAULT = os.getenv("PROMPT_VERSION_DEFAULT", "v1")

# Pitch extraction config (FFT)
PITCH_HOP = int(os.getenv("PITCH_HOP", "2048"))
PITCH_FMIN = float(os.getenv("PITCH_FMIN", "80.0"))      # Hz
PITCH_FMAX = float(os.getenv("PITCH_FMAX", "1000.0"))    # Hz
PITCH_ENERGY_TH = float(os.getenv("PITCH_ENERGY_TH", "0.01"))  # RMS threshold (rough)
PITCH_MAX_SECONDS = float(os.getenv("PITCH_MAX_SECONDS", "60.0"))  # safety cap

# OpenAI (optional)
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
openai_client = None
try:
    if OPENAI_API_KEY:
        from openai import OpenAI
        openai_client = OpenAI(api_key=OPENAI_API_KEY)
except Exception:
    openai_client = None


# ==================================================
# Utils（共通関数）
# ==================================================
def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()

def _sha256(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


# ==================================================
# Path helpers  ★ここが重要（Fly/ローカル両対応）
# ==================================================
BASE_DIR = Path(__file__).resolve().parent  # server.py の場所


def _find_analysis_dir() -> Path:
    """
    解析用のベースディレクトリ（analysis）を確実に見つける。

    優先順位:
      1) ENV: ANALYSIS_DIR（絶対推奨。Flyでは /app/analysis を指定すると安定）
      2) server.py と同階層の ./analysis
      3) iOSプロジェクト構成: ./SingingApp/analysis（ローカル互換）
      4) 親を辿って探す（最大8階層）
      5) fallback: ./analysis を作る
    """
    env = os.getenv("ANALYSIS_DIR")
    if env:
        return Path(env).resolve()

    candidates = [
        (BASE_DIR / "analysis"),
        (BASE_DIR / "SingingApp" / "analysis"),
    ]
    for c in candidates:
        if c.exists():
            return c.resolve()

    cur = BASE_DIR.resolve()
    for _ in range(8):
        c1 = cur / "analysis"
        if c1.exists():
            return c1.resolve()
        c2 = cur / "SingingApp" / "analysis"
        if c2.exists():
            return c2.resolve()
        cur = cur.parent

    # fallback（無ければ作る）
    return (BASE_DIR / "analysis").resolve()


ANALYSIS_DIR = _find_analysis_dir()
SESSIONS_DIR = (ANALYSIS_DIR / "sessions").resolve()

# songs フォルダ（サーバ側の曲カタログ置き場）
SERVER_SONGS_DIR = Path(os.getenv("SERVER_SONGS_DIR", str(ANALYSIS_DIR / "songs"))).resolve()
SERVER_SONGS_JSON = Path(os.getenv("SERVER_SONGS_JSON", str(SERVER_SONGS_DIR / "songs.json"))).resolve()

# DB（重要）
DEFAULT_LOCAL_DB = str((ANALYSIS_DIR / "history.sqlite3").resolve())
DB_PATH = Path(os.getenv("DB_PATH", DEFAULT_LOCAL_DB)).resolve()

# ensure dirs
SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
SERVER_SONGS_DIR.mkdir(parents=True, exist_ok=True)


# ==================================================
# Flask
# ==================================================
app = Flask(__name__)
app.url_map.strict_slashes = False


# ==================================================
# Utils
# ==================================================
def iso_utc_z() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def safe_len(x: Any) -> Optional[int]:
    try:
        return len(x)
    except Exception:
        return None


def json_error(status: int, code: str, message: str, **extra):
    payload = {"ok": False, "code": code, "message": message}
    if extra:
        payload.update(extra)
    return jsonify(payload), status


def read_json_or_error(path: Path, label: str) -> Any:
    if not path.exists():
        raise FileNotFoundError(f"{label} not found: {path}")
    text = path.read_text(encoding="utf-8")
    try:
        return json.loads(text)
    except Exception as e:
        raise ValueError(f"{label} invalid json: {path} ({e})")


@app.get("/api/admin/paths")
def admin_paths():
    return jsonify({
        "ok": True,
        "BASE_DIR": str(BASE_DIR),
        "ANALYSIS_DIR": str(ANALYSIS_DIR),
        "SESSIONS_DIR": str(SESSIONS_DIR),
        "SERVER_SONGS_DIR": str(SERVER_SONGS_DIR),
        "SERVER_SONGS_JSON": str(SERVER_SONGS_JSON),
        "DB_PATH": str(DB_PATH),
        "songs_json_exists": SERVER_SONGS_JSON.exists(),
    })


# ==================================================
# Song catalog (SERVER side)
# ==================================================
@dataclass(frozen=True)
class SongItem:
    id: str
    title: str
    instrumental: str
    singer: str
    lyrics: str


_song_cache: Dict[str, SongItem] = {}
_song_cache_loaded_at: Optional[str] = None


def _load_song_catalog_from_server() -> Dict[str, SongItem]:
    global _song_cache_loaded_at

    if not SERVER_SONGS_JSON.exists():
        raise FileNotFoundError(f"songs.json not found on server: {SERVER_SONGS_JSON}")

    raw = read_json_or_error(SERVER_SONGS_JSON, "songs.json")
    songs = raw.get("songs") if isinstance(raw, dict) else None
    if not isinstance(songs, list):
        raise ValueError(f"songs.json format invalid (songs is not list): {SERVER_SONGS_JSON}")

    out: Dict[str, SongItem] = {}
    for s in songs:
        if not isinstance(s, dict):
            continue
        sid = str(s.get("id") or "").strip()
        if not sid:
            continue

        out[sid] = SongItem(
            id=sid,
            title=str(s.get("title") or sid),
            instrumental=str(s.get("instrumental") or ""),
            singer=str(s.get("singer") or ""),
            lyrics=str(s.get("lyrics") or ""),
        )

    _song_cache_loaded_at = iso_utc_z()
    return out


def get_song_catalog(force_reload: bool = False) -> Dict[str, SongItem]:
    global _song_cache
    if force_reload or not _song_cache:
        _song_cache = _load_song_catalog_from_server()
    return _song_cache


def get_song_or_raise(song_id: str) -> SongItem:
    catalog = get_song_catalog()
    if song_id not in catalog:
        raise FileNotFoundError(f"song_id not found in catalog: {song_id} (catalog={list(catalog.keys())})")
    return catalog[song_id]


def resolve_song_asset_path(filename: str) -> Path:
    if not filename:
        raise FileNotFoundError("asset filename is empty")

    p = (SERVER_SONGS_DIR / filename).resolve()

    if SERVER_SONGS_DIR not in p.parents and p != SERVER_SONGS_DIR:
        raise FileNotFoundError(f"invalid asset path: {filename}")

    if not p.exists():
        raise FileNotFoundError(f"asset not found: {p}")
    return p


@app.get("/api/admin/songs/reload")
def admin_reload_songs():
    try:
        get_song_catalog(force_reload=True)
        return jsonify({
            "ok": True,
            "message": "reloaded",
            "songs_json": str(SERVER_SONGS_JSON),
            "songs_dir": str(SERVER_SONGS_DIR),
            "loaded_at": _song_cache_loaded_at,
            "song_ids": list(_song_cache.keys()),
        })
    except Exception as e:
        return json_error(
            500,
            "SONG_RELOAD_FAILED",
            str(e),
            songs_json=str(SERVER_SONGS_JSON),
            songs_dir=str(SERVER_SONGS_DIR),
        )


# ==================================================
# Session dir
# ==================================================
def make_take_id() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]


def get_session_dir(song_id: str, user_id: str, take_id: Optional[str] = None) -> Path:
    base = (SESSIONS_DIR / song_id / user_id).resolve()
    base.mkdir(parents=True, exist_ok=True)

    if take_id:
        d = (base / take_id).resolve()
        d.mkdir(parents=True, exist_ok=True)
        return d

    candidates = [p for p in base.iterdir() if p.is_dir()]
    if not candidates:
        tid = make_take_id()
        d = (base / tid).resolve()
        d.mkdir(parents=True, exist_ok=True)
        return d

    candidates.sort(key=lambda p: p.name, reverse=True)
    return candidates[0]


def parse_session_id(session_id: str) -> Tuple[str, str, Optional[str]]:
    parts = [p for p in session_id.split("/") if p]
    if len(parts) >= 3:
        return parts[0], parts[1], parts[2]
    if len(parts) == 2:
        return parts[0], parts[1], None
    raise ValueError(f"invalid session_id: {session_id}")


# ==================================================
# DB (history / users)
# ==================================================
def _ensure_db_parent_dir():
    try:
        DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass


def get_db() -> sqlite3.Connection:
    if "db" not in g:
        _ensure_db_parent_dir()
        conn = sqlite3.connect(
            str(DB_PATH),
            timeout=30,
            check_same_thread=False,
        )
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA synchronous=NORMAL;")
        conn.execute("PRAGMA busy_timeout=5000;")
        g.db = conn
    return g.db


@app.teardown_appcontext
def close_db(_err):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    """
    gunicorn 起動（__main__ じゃない）でも必ず実行されるように、
    ファイル末尾で init_db() を呼ぶ。

    ここで作るテーブル:
    - history: 解析結果/コメント/スコア等の履歴
    - users  : user_id + token_hash を管理（端末なしでも user 発行できるようにする）
    """
    _ensure_db_parent_dir()
    db = sqlite3.connect(
        str(DB_PATH),
        timeout=30,
        check_same_thread=False,
    )
    db.execute("PRAGMA journal_mode=WAL;")
    db.execute("PRAGMA synchronous=NORMAL;")
    db.execute("PRAGMA busy_timeout=5000;")

    # ------------------------------
    # history
    # ------------------------------
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS history (
            id TEXT PRIMARY KEY,
            song_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            created_at TEXT NOT NULL,

            comment_title TEXT,
            comment_body TEXT,

            score100 REAL,
            score100_strict REAL,
            score100_octave_invariant REAL,
            octave_invariant_now INTEGER,

            tol_cents REAL,
            percent_within_tol REAL,
            mean_abs_cents REAL,
            sample_count INTEGER,

            client_hash TEXT,

            comment_source TEXT,
            prompt_version TEXT,
            model TEXT,
            app_version TEXT
        )
        """
    )
    db.execute("CREATE INDEX IF NOT EXISTS idx_history_user_created ON history(user_id, created_at)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_history_user_hash ON history(user_id, client_hash)")

    # ------------------------------
    # users
    # ------------------------------
    db.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            name TEXT,
            token_hash TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
    )
    db.execute("CREATE INDEX IF NOT EXISTS idx_users_token_hash ON users(token_hash)")
    db.execute("CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at)")

    db.commit()
    db.close()


# ==================================================
# OpenAI helpers
# ==================================================
def require_openai_key_or_error():
    if openai_client is None:
        raise RuntimeError("OPENAI_API_KEY is not set or OpenAI client failed to initialize.")


def _normalize_ai_comment(text: str) -> Tuple[str, str]:
    try:
        obj = json.loads(text)
        if isinstance(obj, dict):
            title = str(obj.get("title") or "AIコメント")
            body = str(obj.get("body") or "").strip()
            if not body:
                body = "（本文が空でした）"
            return title, body
    except Exception:
        pass

    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    if not lines:
        return "AIコメント", "（本文が空でした）"
    title = lines[0][:20]
    body = "\n".join(lines[1:6]) if len(lines) > 1 else "（本文が空でした）"
    return title, body


# ==================================================
# Audio decode + FFT pitch
# ==================================================
def _which(cmd: str) -> Optional[str]:
    from shutil import which
    return which(cmd)


def _decode_to_wav_via_ffmpeg(src_path: Path) -> Path:
    ffmpeg = _which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError(
            "ffmpeg が見つかりません。m4a を解析するには ffmpeg が必要です。"
            " 参照音源を wav にするか、ffmpeg を入れてください。"
        )

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".wav")
    tmp_path = Path(tmp.name)
    tmp.close()

    cmd = [
        ffmpeg, "-y",
        "-i", str(src_path),
        "-vn",
        "-ac", "1",
        "-ar", "44100",
        "-f", "wav",
        str(tmp_path),
    ]
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"ffmpeg 変換に失敗しました: {p.stderr[:400]}")
    return tmp_path


def _read_wav_mono_float(path: Path) -> Tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as wf:
        nch = wf.getnchannels()
        sr = wf.getframerate()
        sampwidth = wf.getsampwidth()
        nframes = wf.getnframes()
        raw = wf.readframes(nframes)

    if sampwidth == 2:
        x = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    elif sampwidth == 4:
        x = np.frombuffer(raw, dtype=np.int32).astype(np.float32) / 2147483648.0
    else:
        raise RuntimeError(f"unsupported wav sample width: {sampwidth}")

    if nch >= 2:
        x = x.reshape(-1, nch).mean(axis=1)

    return x, int(sr)


def load_audio_mono_float(path: Path) -> Tuple[np.ndarray, int]:
    ext = path.suffix.lower()
    if ext == ".wav":
        return _read_wav_mono_float(path)

    tmp_wav = _decode_to_wav_via_ffmpeg(path)
    try:
        return _read_wav_mono_float(tmp_wav)
    finally:
        try:
            tmp_wav.unlink(missing_ok=True)
        except Exception:
            pass


def _parabolic_interpolation(y0: float, y1: float, y2: float) -> float:
    denom = (y0 - 2.0 * y1 + y2)
    if abs(denom) < 1e-12:
        return 0.0
    return 0.5 * (y0 - y2) / denom


def extract_pitch_track_fft(
    x: np.ndarray,
    sr: int,
    hop: int = PITCH_HOP,
    fmin: float = PITCH_FMIN,
    fmax: float = PITCH_FMAX,
    energy_th: float = PITCH_ENERGY_TH,
    max_seconds: float = PITCH_MAX_SECONDS,
) -> List[Dict[str, Any]]:
    if x.size == 0 or sr <= 0:
        return []

    max_n = int(sr * max_seconds)
    if x.size > max_n:
        x = x[:max_n]

    frame_len = int(hop * 2)
    if frame_len < 256:
        frame_len = 256

    win = np.hamming(frame_len).astype(np.float32)
    freqs = np.fft.rfftfreq(frame_len, d=1.0 / sr)

    band = (freqs >= fmin) & (freqs <= fmax)
    band_idx = np.where(band)[0]
    if band_idx.size == 0:
        return []

    out: List[Dict[str, Any]] = []
    n = x.size

    for start in range(0, max(0, n - frame_len + 1), hop):
        frame = x[start:start + frame_len]
        if frame.size != frame_len:
            break

        rms = float(np.sqrt(np.mean(frame * frame)))
        t = float(start) / float(sr)

        if rms < energy_th:
            out.append({"t": t, "f0_hz": None})
            continue

        spec = np.fft.rfft(frame * win)
        mag = np.abs(spec).astype(np.float32)

        mag_band = mag[band]
        if mag_band.size == 0:
            out.append({"t": t, "f0_hz": None})
            continue

        k_rel = int(np.argmax(mag_band))
        k = int(band_idx[k_rel])

        if 1 <= k < (mag.size - 1):
            d = _parabolic_interpolation(float(mag[k - 1]), float(mag[k]), float(mag[k + 1]))
        else:
            d = 0.0

        f0 = float((k + d) * (sr / frame_len))

        if not (fmin <= f0 <= fmax) or math.isnan(f0) or math.isinf(f0):
            out.append({"t": t, "f0_hz": None})
        else:
            out.append({"t": t, "f0_hz": f0})

    return out


_ref_pitch_cache: Dict[str, Dict[str, Any]] = {}


def build_pitch_track_from_file(path: Path) -> Dict[str, Any]:
    x, sr = load_audio_mono_float(path)
    track = extract_pitch_track_fft(x, sr, hop=PITCH_HOP)
    return {"algo": "fft_peak", "sr": int(sr), "hop": int(PITCH_HOP), "track": track}


def get_ref_pitch_for_song(song: SongItem) -> Dict[str, Any]:
    if song.id in _ref_pitch_cache:
        return _ref_pitch_cache[song.id]

    singer_path = resolve_song_asset_path(song.singer)
    ref_pitch = build_pitch_track_from_file(singer_path)

    _ref_pitch_cache[song.id] = ref_pitch
    return ref_pitch


# ==================================================
# Core analysis (FFT version)
# ==================================================
def analyze_fft(song_id: str, user_id: str, take_id: str, wav_path: Path) -> Dict[str, Any]:
    try:
        song = get_song_or_raise(song_id)

        _ = resolve_song_asset_path(song.instrumental)
        _ = resolve_song_asset_path(song.singer)
        _ = resolve_song_asset_path(song.lyrics)

        usr_pitch = build_pitch_track_from_file(wav_path)
        ref_pitch = get_ref_pitch_for_song(song)

        usr_n = safe_len(usr_pitch.get("track")) or 0
        ref_n = safe_len(ref_pitch.get("track")) or 0

        if usr_n == 0 or ref_n == 0:
            verdict = "解析失敗"
            reason = "音程データが作れませんでした（無音、または参照音源の読み取りに失敗）"
            tips = [
                "短いフレーズで録音してみてください。",
                "参照音源が再生できる形式か確認してください（m4aの場合はffmpegが必要なことがあります）。",
            ]
        else:
            verdict = "解析完了"
            reason = "音程データを作成しました。"
            tips = [
                "ズレが大きい区間を短く区切って繰り返し練習してください。",
                "出だしの音を狙ってから声を出すと安定しやすいです。",
            ]

        return {
            "ok": True,
            "song_id": song_id,
            "user_id": user_id,
            "take_id": take_id,
            "session_id": f"{song_id}/{user_id}/{take_id}",
            "usr_pitch": usr_pitch,
            "ref_pitch": ref_pitch,
            "events": [],
            "summary": {
                "verdict": verdict,
                "reason": reason,
                "tips": tips,
                "tol_cents": 40.0,
            },
            "meta": {"paths": {}, "counts": {"events": 0, "ref_track": ref_n, "usr_track": usr_n}},
        }

    except Exception as e:
        return {
            "ok": True,
            "song_id": song_id,
            "user_id": user_id,
            "take_id": take_id,
            "session_id": f"{song_id}/{user_id}/{take_id}",
            "usr_pitch": {"algo": "none", "sr": 44100, "hop": PITCH_HOP, "track": []},
            "ref_pitch": {"algo": "none", "sr": None, "hop": None, "track": []},
            "events": [],
            "summary": {
                "verdict": "解析失敗",
                "reason": f"解析中にエラー: {e}",
                "tips": [
                    "song_id が正しいか確認してください。",
                    "参照音源の配置とファイル形式を確認してください（m4aはffmpegが必要）。",
                ],
                "tol_cents": 40.0,
            },
            "meta": {"paths": {}, "counts": {"events": 0, "ref_track": 0, "usr_track": 0}},
        }


# ==================================================
# API: create user (issue user_id + token)
# POST /api/users
# ==================================================
@app.post("/api/users")
def create_user():
    try:
        data = request.get_json(silent=True) or {}
        name = (data.get("name") or "").strip()

        user_id = uuid.uuid4().hex
        token = secrets.token_urlsafe(32)
        token_hash = _sha256(token)

        db = get_db()
        db.execute(
            "INSERT INTO users (id, name, token_hash, created_at) VALUES (?, ?, ?, ?)",
            (user_id, name, token_hash, _now_iso())
        )
        db.commit()

        return jsonify({
            "ok": True,
            "message": "user_created",
            "user_id": user_id,
            "token": token,
            "name": name,
        })

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# ==================================================
# API: upload voice
# POST /api/voice/<user_id>?song_id=xxx
# ==================================================
@app.post("/api/voice/<user_id>")
def upload_voice(user_id: str):
    try:
        song_id = (request.args.get("song_id") or "").strip()
        if not song_id:
            song_id = "orphans"

        up = request.files.get("file")
        if up is None:
            return json_error(400, "NO_FILE", "file is required")

        take_id = make_take_id()
        sess_dir = get_session_dir(song_id, user_id, take_id)
        wav_path = sess_dir / "input.wav"

        up.save(wav_path)

        analysis = analyze_fft(song_id, user_id, take_id, wav_path)

        (sess_dir / "usr_pitch.json").write_text(json.dumps(analysis.get("usr_pitch"), ensure_ascii=False), encoding="utf-8")
        (sess_dir / "ref_pitch.json").write_text(json.dumps(analysis.get("ref_pitch"), ensure_ascii=False), encoding="utf-8")
        (sess_dir / "events.json").write_text(json.dumps(analysis.get("events"), ensure_ascii=False), encoding="utf-8")
        (sess_dir / "summary.json").write_text(json.dumps(analysis.get("summary"), ensure_ascii=False), encoding="utf-8")

        return jsonify({
            "ok": True,
            "message": "uploaded_and_analyzed",
            "saved_path": str(wav_path),
            "session_id": analysis.get("session_id"),
            "song_id": song_id,
            "user_id": user_id,
            "take_id": take_id,
        })

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# ==================================================
# API: analysis
# GET /api/analysis/<session_id>
# ==================================================
@app.get("/api/analysis/<path:session_id>")
def get_analysis(session_id: str):
    try:
        song_id, user_id, take_id = parse_session_id(session_id)
        sess_dir = get_session_dir(song_id, user_id, take_id)

        ref_pitch_path = sess_dir / "ref_pitch.json"
        usr_pitch_path = sess_dir / "usr_pitch.json"
        events_path = sess_dir / "events.json"
        summary_path = sess_dir / "summary.json"

        ref_pitch = read_json_or_error(ref_pitch_path, "ref_pitch")
        usr_pitch = read_json_or_error(usr_pitch_path, "usr_pitch")
        events = read_json_or_error(events_path, "events")
        summary = read_json_or_error(summary_path, "summary")

        return jsonify({
            "ok": True,
            "session_id": session_id,
            "song_id": song_id,
            "user_id": user_id,
            "events": events,
            "ref_pitch": ref_pitch,
            "usr_pitch": usr_pitch,
            "summary": summary,
            "meta": {
                "paths": {
                    "ref_pitch": str(ref_pitch_path),
                    "usr_pitch": str(usr_pitch_path),
                    "events": str(events_path),
                    "summary": str(summary_path),
                },
                "counts": {
                    "ref_track": safe_len(ref_pitch.get("track")) if isinstance(ref_pitch, dict) else None,
                    "usr_track": safe_len(usr_pitch.get("track")) if isinstance(usr_pitch, dict) else None,
                    "events": safe_len(events),
                },
            },
        })

    except FileNotFoundError as e:
        return json_error(404, "FILE_NOT_FOUND", str(e))
    except ValueError as e:
        return json_error(500, "INVALID_JSON", str(e))
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# ==================================================
# AI comment (core + compat routes)
# ==================================================
def _ai_comment_core(song_id: str, user_id: str, take_id: Optional[str]):
    require_openai_key_or_error()

    sess_dir = get_session_dir(song_id, user_id, take_id)

    events_path = sess_dir / "events.json"
    summary_path = sess_dir / "summary.json"

    events: List[Dict[str, Any]] = []
    summary: Dict[str, Any] = {}

    try:
        if events_path.exists():
            events = read_json_or_error(events_path, "events")
        if summary_path.exists():
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
        "take_id": take_id,
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

    return jsonify({
        "ok": True,
        "title": title,
        "body": body,
        "model": AI_MODEL_NAME,
        "prompt_version": PROMPT_VERSION_DEFAULT,
    })


@app.post("/api/comment/<song_id>/<user_id>")
def ai_comment(song_id: str, user_id: str):
    try:
        return _ai_comment_core(song_id, user_id, take_id=None)
    except RuntimeError as e:
        return json_error(500, "OPENAI_KEY_MISSING", str(e))
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


@app.post("/api/comment/<song_id>/<user_id>/<take_id>")
def ai_comment_with_take(song_id: str, user_id: str, take_id: str):
    try:
        return _ai_comment_core(song_id, user_id, take_id=take_id)
    except RuntimeError as e:
        return json_error(500, "OPENAI_KEY_MISSING", str(e))
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


@app.post("/api/comment/<path:session_id>")
def ai_comment_by_session(session_id: str):
    try:
        song_id, user_id, take_id = parse_session_id(session_id)
        return _ai_comment_core(song_id, user_id, take_id=take_id)
    except RuntimeError as e:
        return json_error(500, "OPENAI_KEY_MISSING", str(e))
    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# ==================================================
# History append/list/delete
# ==================================================
@app.post("/api/history/<song_id>/<user_id>/append")
def history_append(song_id: str, user_id: str):
    try:
        raw = request.get_data(cache=True) or b""
        payload = request.get_json(silent=True) or {}

        def pick(payload, camel, snake):
            if camel in payload:
                return payload[camel]
            return payload.get(snake)

        comment_title = payload.get("commentTitle") or payload.get("comment_title") or "AIコメント"
        comment_body = payload.get("commentBody") or payload.get("comment_body") or ""

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

        client_hash = request.headers.get("Idempotency-Key")
        if not client_hash:
            client_hash = hashlib.sha256(raw).hexdigest()

        comment_source = request.headers.get("X-Comment-Source") or "ai"
        prompt_version = request.headers.get("X-Prompt-Version") or PROMPT_VERSION_DEFAULT
        model_name = request.headers.get("X-AI-Model") or AI_MODEL_NAME
        app_version = request.headers.get("X-App-Version")

        history_id = str(uuid.uuid4())
        created_at = iso_utc_z()

        db = get_db()

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
                comment_source, prompt_version, model_name, app_version,
            ),
        )
        db.commit()

        if (cur.rowcount or 0) == 0:
            row = db.execute(
                "SELECT * FROM history WHERE user_id = ? AND client_hash = ? ORDER BY created_at DESC LIMIT 1",
                (user_id, client_hash),
            ).fetchone()

            if row is None:
                return jsonify({"ok": True, "item": None, "message": "duplicate"}), 200

            item = dict(row)
            return jsonify({"ok": True, "item": item, "message": "duplicate"}), 200

        return jsonify({"ok": True, "item": {"id": history_id, "created_at": created_at}, "message": None})

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


@app.get("/api/history/<user_id>")
def history_list(user_id: str):
    try:
        source = request.args.get("source")
        prompt = request.args.get("prompt")
        model = request.args.get("model")
        limit = request.args.get("limit", type=int)
        offset = request.args.get("offset", type=int)

        if limit is None:
            limit = 200
        limit = max(1, min(limit, 500))

        if offset is None:
            offset = 0
        offset = max(0, offset)

        db = get_db()

        where = ["user_id = ?"]
        params = [user_id]

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

        return jsonify({"ok": True, "user_id": user_id, "items": items, "message": None})

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


@app.delete("/api/history/<user_id>/<history_id>")
def history_delete(user_id: str, history_id: str):
    try:
        db = get_db()
        cur = db.execute("DELETE FROM history WHERE user_id = ? AND id = ?", (user_id, history_id))
        db.commit()

        deleted = (cur.rowcount or 0) > 0
        return jsonify({"ok": True, "message": "deleted" if deleted else "not_found"})

    except Exception as e:
        return json_error(500, "INTERNAL_ERROR", str(e))


# ==================================================
# 起動時に必ず DB を初期化（gunicorn 対応）
# ==================================================
init_db()

# 曲カタログは必須ではないので、起動時に失敗してもアプリは落とさない
try:
    get_song_catalog(force_reload=True)
except Exception:
    pass


# ==================================================
# Main（ローカル用）
# ==================================================
if __name__ == "__main__":
    try:
        print("BASE_DIR =", str(BASE_DIR))
        print("ANALYSIS_DIR =", str(ANALYSIS_DIR))
        print("SESSIONS_DIR =", str(SESSIONS_DIR))
        print("SERVER_SONGS_DIR =", str(SERVER_SONGS_DIR))
        print("SERVER_SONGS_JSON =", str(SERVER_SONGS_JSON), "exists=", SERVER_SONGS_JSON.exists())
        print("DB_PATH =", str(DB_PATH))
        print("FFT pitch: hop =", PITCH_HOP, "fmin =", PITCH_FMIN, "fmax =", PITCH_FMAX)
        print("ffmpeg =", _which("ffmpeg"))
        if _song_cache:
            print("song_ids =", list(_song_cache.keys()))
    except Exception:
        pass

    app.run(host="0.0.0.0", port=5000, debug=True)
