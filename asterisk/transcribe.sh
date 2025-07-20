#!/bin/bash
SOURCE="/tmp/recording.wav"
FORMATTED="/tmp/recording16.wav"
MODEL="$HOME/whisper.cpp/models/ggml-medium.bin"
BIN="/usr/local/bin/whisper"

ffmpeg -y -i "$SOURCE" -ar 16000 -ac 1 -c:a pcm_s16le "$FORMATTED"

if [ ! -x "$BIN" ]; then
  echo "❌ whisper binary not found at $BIN"
  exit 1
fi

if [ ! -f "$MODEL" ]; then
  echo "❌ Model file not found at $MODEL"
  exit 1
fi

echo "🧠 Running whisper model..."
"$BIN" -m "$MODEL" -f "$FORMATTED"
