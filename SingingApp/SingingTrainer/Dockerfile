FROM python:3.11-slim

# ffmpeg インストール
RUN apt-get update && \
    apt-get install -y ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# 作業ディレクトリ
WORKDIR /app

# 依存関係
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# アプリ本体
COPY . .

# SQLite を置くディレクトリ（Fly Volume 用）
RUN mkdir -p /data

ENV DB_PATH=/data/app.db
ENV PYTHONUNBUFFERED=1

# gunicorn で Flask 起動
CMD ["gunicorn", "-b", "0.0.0.0:8080", "server:app"]
