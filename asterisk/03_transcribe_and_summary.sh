#!/bin/bash
set -e

if [ ! -f transcribe.sh ]; then
  echo "🧠 Creating transcribe script..."
  cat <<EOF > transcribe.sh
#!/bin/bash
SOURCE="/tmp/recording.wav"
FORMATTED="/tmp/recording16.wav"
MODEL="\$(dirname "\$0")/whisper.cpp/models/ggml-medium.bin"
BIN="\$(dirname "\$0")/whisper.cpp/whisper"

ffmpeg -y -i "\$SOURCE" -ar 16000 -ac 1 -c:a pcm_s16le "\$FORMATTED"
"\$BIN" -m "\$MODEL" -f "\$FORMATTED"
EOF
  chmod +x transcribe.sh
  SUMMARY["TranscribeScript"]="✅ Created"
else
  SUMMARY["TranscribeScript"]="✅ Already Exists"
fi

# ----- Summary -----
echo ""
echo "✅ Installation complete!"
echo ""
echo "📋 Summary:"
for key in "${!SUMMARY[@]}"; do
  printf " - %-18s %s\n" "$key" "${SUMMARY[$key]}"
done

echo ""
echo "🎉 Use Zoiper to call extension 1000, then run: ./transcribe.sh"
echo "📝 View logs with: less $LOGFILE"
