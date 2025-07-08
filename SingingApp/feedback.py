#
#  feedback.py
#  SingingApp

#  Created by Koutarou Arima on 2025/07/07.

import numpy as np

def generate_feedback(pitch_array):
    """
    ピッチの変動から安定性スコアを算出し、フィードバックコメントを返す
    """
    # NaN（無音区間）を除外
    pitch_array = np.array(pitch_array)
    pitch_array = pitch_array[~np.isnan(pitch_array)]

    if len(pitch_array) == 0:
        return "音程が検出できませんでした。録音を確認してください。", 0

    # ピッチの標準偏差で安定性を評価（値が小さいほど安定）
    stability = np.std(pitch_array)
    score = max(0, 100 - int(stability * 10))

    if score >= 85:
        comment = "音程が非常に安定しています！この調子です！"
    elif score >= 60:
        comment = "少し音程が不安定です。ロングトーンを意識して練習してみましょう。"
    else:
        comment = "音程が大きく揺れています。一定の高さを保つトレーニングが効果的です。"

    return comment, score
