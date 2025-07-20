#!/bin/bash
set -e

LOGFILE=~/install-voice-transcriber.log
exec > >(tee -a "$LOGFILE") 2>&1

export DEBIAN_FRONTEND=noninteractive

echo ""
echo "🟣 Voice Transcriber Setup Starting: $(date)"
echo "📄 Log file: $LOGFILE"
echo ""

declare -A SUMMARY
SUMMARY=(
  ["Asterisk"]="❌ Not installed"
  ["AsteriskConfig"]="❌ Not configured"
  ["Whisper"]="❌ Not built"
  ["Models"]="❌ Not all downloaded"
  ["TranscribeScript"]="❌ Not created"
)

echo "🔧 Updating system..."
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
PJSIP_CONF="/etc/asterisk/pjsip.conf"
EXTENSIONS_CONF="/etc/asterisk/extensions.conf"

CONFIGURED=false

if ! grep -q "testuser" "$PJSIP_CONF"; then
  echo "🔧 Configuring Asterisk SIP user..."
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
else
  echo "✅ SIP user 'testuser' already configured"
fi

if ! grep -q "exten => 1000,1,Answer()" "$EXTENSIONS_CONF"; then
  echo "🔧 Configuring Asterisk dialplan..."
  sudo tee "$EXTENSIONS_CONF" > /dev/null <<EOF
[default]
exten => 1000,1,Answer()
 same => n,Playback(hello-world)
 same => n,Record(/tmp/recording.wav,5,60)
 same => n,Hangup()
EOF
  CONFIGURED=true
else
  echo "✅ Dialplan already configured"
fi

if $CONFIGURED; then
  echo "🔄 Restarting Asterisk..."
  sudo systemctl restart asterisk || echo "⚠️ Asterisk restart failed"
  SUMMARY["AsteriskConfig"]="✅ Applied"
else
  SUMMARY["AsteriskConfig"]="✅ Already Configured"
fi

# ----- Whisper.cpp -----
cd ~

if [ ! -d "whisper.cpp" ]; then
  echo "📁 Cloning whisper.cpp..."
  git clone https://github.com/ggerganov/whisper.cpp.git
  cd whisper.cpp
else
  echo "🔄 Updating whisper.cpp..."
  cd whisper.cpp && git pull && cd ..
fi

cd ~/whisper.cpp

if [ ! -f "main" ]; then
  echo "🔨 Building whisper.cpp..."
  make
  ln -sf main whisper
  SUMMARY["Whisper"]="✅ Built"
else
  echo "✅ whisper.cpp already built"
  SUMMARY["Whisper"]="✅ Already Built"
fi

# ----- Models -----
echo "⬇️ Downloading models..."
mkdir -p models
cd models
ALL_MODELS_OK=true
for model in base small medium large; do
  FILE="ggml-${model}.bin"
  if [ ! -f "$FILE" ]; then
    curl -LO "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$FILE"
    if [ ! -f "$FILE" ]; then
      echo "⚠️  Failed to download $FILE"
      ALL_MODELS_OK=false
    fi
  else
    echo "✅ Model $FILE already exists"
  fi
done

if $ALL_MODELS_OK; then
  SUMMARY["Models"]="✅ All Present"
else
  SUMMARY["Models"]="⚠️ Incomplete"
fi
cd ..

# ----- Transcribe Script -----
if [ ! -f "transcribe.sh" ]; then
  echo "🧠 Creating transcribe script..."
  cat <<EOF > transcribe.sh
#!/bin/bash
SOURCE="/tmp/recording.wav"
FORMATTED="/tmp/recording16.wav"
MODEL="models/ggml-medium.bin"

ffmpeg -y -i "\$SOURCE" -ar 16000 -ac 1 -c:a pcm_s16le "\$FORMATTED"
./whisper -m "\$MODEL" -f "\$FORMATTED"
EOF
  chmod +x transcribe.sh
  SUMMARY["TranscribeScript"]="✅ Created"
else
  echo "✅ transcribe.sh already exists"
  SUMMARY["TranscribeScript"]="✅ Already Exists"
fi

# ----- Summary -----
echo ""
echo "✅ Installation Complete!"
echo ""
echo "📋 Summary:"
for key in "${!SUMMARY[@]}"; do
  printf " - %-18s %s\n" "$key:" "${SUMMARY[$key]}"
done

echo ""
echo "🗒️  You can view logs anytime using: less $LOGFILE"
echo "📞 To test: Call extension 1000 from Zoiper and run ./transcribe.sh"

