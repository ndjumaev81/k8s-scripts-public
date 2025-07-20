#!/bin/bash
SOURCE="/tmp/recording.wav"
FORMATTED="/tmp/recording16.wav"
MODEL="$HOME/whisper.cpp/models/ggml-medium.bin"

ffmpeg -y -i "$SOURCE" -ar 16000 -ac 1 -c:a pcm_s16le "$FORMATTED"
whisper -m "$MODEL" -f "$FORMATTED"
