#!/bin/bash

SOURCE="/tmp/recording.wav"
FORMATTED="/tmp/recording16.wav"
MODEL="models/ggml-medium.bin"
LANGUAGE=${1:-""}  # Optional argument, defaults to auto

# Convert to required format
ffmpeg -y -i "$SOURCE" -ar 16000 -ac 1 -c:a pcm_s16le "$FORMATTED"

# Transcribe
if [ -z "$LANGUAGE" ]; then
  ./whisper -m "$MODEL" -f "$FORMATTED"
else
  ./whisper -m "$MODEL" -f "$FORMATTED" -l "$LANGUAGE"
fi

