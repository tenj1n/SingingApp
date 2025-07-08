#
# server.py
# Created by Koutarou Arima on 2025/07/01.

from flask import Flask, request, jsonify
from datetime import datetime
import os

from convert import convert_to_wav
from analyze import extract_pitch_array  # ※ pitch配列だけ返す関数が必要
from feedback import generate_feedback

app = Flask(__name__)
UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return 'ファイルがありません', 400

    file = request.files['file']
    if file.filename == '':
        return 'ファイル名が空です', 400

    # 保存先のパス
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filename = f"record_{timestamp}.m4a"
    save_path = os.path.join(UPLOAD_FOLDER, filename)
    file.save(save_path)

    # ステップ1：.wav に変換
    wav_path = convert_to_wav(save_path)

    if wav_path is None:
        return '変換失敗', 500

    # ステップ2：ピッチ配列を抽出
    pitch_array = extract_pitch_array(wav_path)
    if pitch_array is None:
        return 'ピッチ抽出失敗', 500

    # ステップ3：フィードバック生成
    comment, score = generate_feedback(pitch_array)

    # レスポンスをJSON形式で返す
    return jsonify({
        "message": "解析成功",
        "filename": filename,
        "score": score,
        "feedback": comment
    })

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
