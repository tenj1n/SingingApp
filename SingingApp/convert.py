
#  convert.py
#  SingingApp

#  Created by Koutarou Arima on 2025/07/07.

import os
import librosa
import soundfile as sf

def convert_to_wav(input_path, output_dir='uploads_wav'):
    """
    m4aファイルを読み込んでwavに変換する。
    出力先は uploads_wav フォルダ（自動作成）。
    """
    # 出力フォルダの作成
    os.makedirs(output_dir, exist_ok=True)

    try:
        y, sr = librosa.load(input_path, sr=None)
        base = os.path.basename(input_path)
        name = os.path.splitext(base)[0]
        output_path = os.path.join('uploads_wav', f'{name}.wav') 
        sf.write(output_path, y, sr)
        print(f'変換成功: {output_path}')
        return output_path
    except Exception as e:
        print(f'変換失敗: {e}')
        return None
