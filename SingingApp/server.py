#
# server.py
# Created by Koutarou Arima on 2025/07/01.

from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename
from datetime import datetime
import os
from convert import convert_to_wav
from feedback import generate_feedback
from analyze import extract_pitch_array, analyze_audio
from flask import send_from_directory

app = Flask(__name__)
UPLOAD_FOLDER = 'uploads'
WAV_FOLDER = 'uploads_wav'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(WAV_FOLDER, exist_ok=True)

# 画像を返すエンドポイント
@app.route('/analysis/<filename>')
def get_analysis_image(filename):
    return send_from_directory('analysis', filename)

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

    # WAV変換
    wav_path = convert_to_wav(save_path)
    if not wav_path:
        return "WAV変換失敗", 500


    # ステップ2：ピッチ配列を抽出
    pitch_array = extract_pitch_array(wav_path)
    pitch_path, volume_path = analyze_audio(wav_path)  # PNG出力

    if pitch_array is None:
        return "ピッチ解析失敗", 500

    # ステップ3：フィードバック生成
    feedback, score = generate_feedback(pitch_array)

    # レスポンスをJSON形式で返す
    return jsonify({
        "feedback": feedback,
        "score": score,
        "pitch_image": pitch_path,       # ← iOSで今は未使用だが保持
        "volume_image": volume_path
    })


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
