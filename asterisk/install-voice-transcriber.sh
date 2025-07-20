#!/bin/bash
set -e

LOGFILE=~/install-voice-transcriber.log
exec > >(tee -a "$LOGFILE") 2>&1

export DEBIAN_FRONTEND=noninteractive

# Suppress region prompt (safe default)
echo "libtonezone1:tzcode string 1" | sudo debconf-set-selections

echo ""
echo "🔧 Voice Transcriber Setup Starting: $(date)"
echo "📄 Log file: $LOGFILE"
echo ""

declare -A SUMMARY=(
  ["Asterisk"]="❌ Not installed"
  ["AsteriskConfig"]="❌ Not configured"
  ["Whisper"]="❌ Not built"
  ["Models"]="❌ Not all downloaded"
  ["TranscribeScript"]="❌ Not created"
)

echo "📦 Updating system..."
sudo apt update -y

echo "📦 Installing dependencies..."
sudo apt install -y wget git build-essential cmake ffmpeg sox curl

# ----- Asterisk Installation -----
if ! command -v asterisk >/dev/null 2>&1; then
  echo "📦 Installing Asterisk from source..."
  cd /usr/src
  sudo wget -N http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-18-current.tar.gz
  sudo tar xvf asterisk-18-current.tar.gz
  cd asterisk-18*/
  sudo contrib/scripts/install_prereq install
  sudo ./configure
  sudo make
  sudo make install
  sudo make samples
  sudo make config
  SUMMARY["Asterisk"]="✅ Installed"
else
  echo "✅ Asterisk already installed"
  SUMMARY["Asterisk"]="✅ Already Installed"
fi

# ----- Asterisk Config -----
PJSIP_CONF=/etc/asterisk/pjsip.conf
EXTENSIONS_CONF=/etc/asterisk/extensions.conf
CONFIGURED=false

if ! grep -q "testuser" "$PJSIP_CONF"; then
  echo "🔧 Adding SIP user to pjsip.conf..."
  sudo tee "$PJSIP_CONF" > /dev/null <<EOF
[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0

[testuser]
type=endpoint
context=default
disallow=all
allow=ulaw
auth=testuser-auth
aors=testuser

[testuser-auth]
type=auth
auth_type=userpass
username=testuser
password=testpass

[testuser]
type=aor
max_contacts=1
EOF
  CONFIGURED=true
fi

if ! grep -q "exten => 1000,1,Answer()" "$EXTENSIONS_CONF"; then
  echo "🔧 Adding dialplan to extensions.conf..."
  sudo tee "$EXTENSIONS_CONF" > /dev/null <<EOF
[default]
exten => 1000,1,Answer()
 same => n,Playback(hello-world)
 same => n,Record(/tmp/recording.wav,5,60)
 same => n,Hangup()
EOF
  CONFIGURED=true
fi

if $CONFIGURED; then
  echo "🔄 Restarting Asterisk..."
  sudo systemctl restart asterisk || echo "⚠️ Asterisk restart may require manual check"
  SUMMARY["AsteriskConfig"]="✅ Applied"
else
  SUMMARY["AsteriskConfig"]="✅ Already Configured"
fi

# ----- Whisper.cpp Installation -----
cd ~
if [ ! -d whisper.cpp ]; then
  echo "📁 Cloning whisper.cpp..."
  git clone https://github.com/ggerganov/whisper.cpp.git
else
  echo "🔄 Updating whisper.cpp..."
  cd whisper.cpp
  git pull
  cd ..
fi

cd ~/whisper.cpp

# Try building, and fallback if needed
if [ ! -f build/main ]; then
  echo "🔨 Building whisper.cpp (first attempt)..."
  cmake -B build
  cmake --build build --config Release
fi

# ensure whisper executable exists
if [ -f build/bin/whisper-cli ]; then
  ln -sf build/bin/whisper-cli whisper-cli
  ln -sf build/bin/main whisper
  SUMMARY["Whisper"]="✅ Built"
  echo "✅ whisper binaries set up"
else
  echo "❗ Failed to build whisper.cpp – retrying..."
  cd ~/whisper.cpp
  make || cmake --build build --config Release
  if [ -f build/bin/whisper-cli ]; then
    ln -sf build/bin/whisper-cli whisper-cli
    ln -sf build/bin/main whisper
    SUMMARY["Whisper"]="✅ Built (retry)"
    echo "✅ whisper binaries set up after retry"
  else
    SUMMARY["Whisper"]="❌ Build failed"
    echo "⚠️ whisper build failed twice. Check errors above."
  fi
fi

# ----- Models Download -----
echo "⬇️ Downloading Whisper models..."
mkdir -p models
cd models
ALL_OK=true
for model in base small medium large; do
  FILE="ggml-${model}.bin"
  if [ ! -f "$FILE" ]; then
    curl -fsSL -O https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$FILE || ALL_OK=false
  fi
done


echo "⬇️ Downloading Whisper models..."

mkdir -p models
cd models

declare -A WHISPER_MODELS=(
  ["ggml-base.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
  ["ggml-small.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
  ["ggml-medium.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
  ["ggml-large.bin"]="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
)

MODEL_STATUS=""

for model in "${!WHISPER_MODELS[@]}"; do
  if [ ! -f "$model" ]; then
    echo "📦 Downloading $model..."
    if curl -fLO "${WHISPER_MODELS[$model]}"; then
      echo "✅ $model downloaded"
    else
      echo "❌ Failed to download $model"
      MODEL_STATUS+=" ❌ $model "
    fi
  else
    echo "✅ $model already exists"
  fi
done

cd ..

SUMMARY["Models"]=$([ "$ALL_OK" = true ] && echo "✅ All present" || echo "⚠️ Some missing")

# ----- Transcribe Script -----
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