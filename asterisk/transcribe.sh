#!/bin/bash

SOURCE="/tmp/recording.wav"
FORMATTED="/tmp/recording16.wav"
MODEL="models/ggml-medium.bin"
LANGUAGE=${1:-""}  # Optional argument, defaults to auto

# Convert to required format
ffmpeg -y -i "$SOURCE" -ar 16000 -ac 1 -c:a pcm_s16le "$FORMATTED"

# Transcribe using whisper-cli
if [ -f ./whisper-cli ]; then
  echo "🔍 Starting transcription..."
  if [ -z "$LANGUAGE" ]; then
    ./whisper-cli "$FORMATTED" --model "$MODEL"
  else
    ./whisper-cli "$FORMATTED" --model "$MODEL" --language "$LANGUAGE"
  fi
else
  echo "❌ whisper-cli binary not found. Please build whisper.cpp first."
  exit 1
fi
