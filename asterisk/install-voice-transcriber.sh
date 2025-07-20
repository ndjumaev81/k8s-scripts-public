#!/bin/bash
set -e

echo "🔧 Updating system..."
sudo apt update

echo "📦 Installing Asterisk dependencies..."
sudo apt install -y wget build-essential subversion git autoconf libjansson-dev libxml2-dev uuid-dev libncurses5-dev libedit-dev pkg-config

echo "📦 Installing Asterisk..."
cd /usr/src
sudo wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-18-current.tar.gz
sudo tar xvf asterisk-18-current.tar.gz
cd asterisk-18*/
sudo contrib/scripts/install_prereq install
sudo ./configure
sudo make
sudo make install
sudo make samples
sudo make config

echo "🔧 Configuring Asterisk for basic SIP + recording..."
sudo tee /etc/asterisk/pjsip.conf > /dev/null <<EOF
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

sudo tee /etc/asterisk/extensions.conf > /dev/null <<EOF
[default]
exten => 1000,1,Answer()
 same => n,Playback(hello-world)
 same => n,Record(/tmp/recording.wav,5,30)
 same => n,Hangup()
EOF

sudo systemctl restart asterisk

echo "✅ Asterisk installed and configured."

echo "📦 Installing Whisper dependencies..."
sudo apt install -y git build-essential cmake ffmpeg sox curl

echo "📁 Cloning whisper.cpp..."
cd ~
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
make whisper

echo "📁 Downloading models..."
mkdir -p models && cd models
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large.bin
cd ..

echo "✅ Whisper installed with models."

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

echo "✅ Done. Call 1000 via Zoiper → record → then run: ./transcribe.sh"

