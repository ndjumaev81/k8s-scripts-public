#!/bin/bash
SOURCE="/var/spool/asterisk/recordings/recording.wav"
FORMATTED="/tmp/recording16.wav"
FORMATTED_MP3="/tmp/recording16.mp3"
MODEL="$HOME/whisper.cpp/models/ggml-large-v3.bin"
BIN="/usr/local/bin/whisper-cli"

ffmpeg -y -i "$SOURCE" -ar 16000 -ac 1 -c:a pcm_s16le "$FORMATTED"

echo "🎵 Converting WAV to MP3..."
ffmpeg -y -i "$FORMATTED" -c:a libmp3lame -b:a 128k "$FORMATTED_MP3" || { echo "❌ Failed to convert to MP3"; exit 1; }

if [ ! -f "$FORMATTED_MP3" ]; then
  echo "❌ MP3 file was not created at $FORMATTED_MP3"
  exit 1
fi

echo "✅ MP3 created: $FORMATTED_MP3"

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