#!/bin/bash

SOURCE="/var/spool/asterisk/recordings/recording.wav"
FORMATTED="/tmp/recording16.wav"
MODEL="$HOME/whisper.cpp/models/ggml-medium.bin"
BIN="/usr/local/bin/whisper-cli"
LANGUAGE="uz"
PROMPT="Yozilgan so‘zlar qanday eshitilsa, shunday yoziladi. Xatoliklar tuzatilmaydi."
OUTPUT_DIR="/tmp/transcriptions"
TIMESTAMP=$(date +%s)
BASENAME="transcript_$TIMESTAMP"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Convert to 16kHz mono WAV (Whisper-friendly format)
ffmpeg -y -i "$SOURCE" -ar 16000 -ac 1 -c:a pcm_s16le "$FORMATTED"

# Sanity checks
if [ ! -x "$BIN" ]; then
  echo "❌ whisper binary not found at $BIN"
  exit 1
fi

if [ ! -f "$MODEL" ]; then
  echo "❌ Model file not found at $MODEL"
  exit 1
fi

# Run whisper.cpp
echo "🧠 Running whisper model..."
"$BIN" -m "$MODEL" \
       -f "$FORMATTED" \
       -l "$LANGUAGE" \
       --prompt "$PROMPT" \
       -otxt \
       -of "$OUTPUT_DIR/$BASENAME"

echo "✅ Transcription saved to $OUTPUT_DIR/$BASENAME.txt"
